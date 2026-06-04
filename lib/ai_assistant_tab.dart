import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;

class Message {
  final String text;
  final bool isUser;

  Message({required this.text, required this.isUser});
}

class AiAssistantTab extends StatefulWidget {
  final String householdId;
  const AiAssistantTab({super.key, required this.householdId});

  @override
  State<AiAssistantTab> createState() => _AiAssistantTabState();
}

class _AiAssistantTabState extends State<AiAssistantTab> {
  final List<Message> _messages = [
    Message(
      text: 'Hello! How can I help you manage your pantry today?',
      isUser: false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  Future<String> _processMessage(String text) async {
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .get();
      final preferences = userDoc.data()?['dietaryPreferences'] as String? ??
          'No special preferences';

      // Fetch real inventory from Firebase
      final snapshot = await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('inventory')
          .get();

      // 1. Filter out items that are out of stock (quantity <= 0 or null)
      var activeDocs = snapshot.docs.where((doc) {
        final data = doc.data();
        final rawQuantity = data['totalQuantity'];
        if (rawQuantity == null) return false;

        // Safely parse num (handles both int, double, and numeric strings)
        final quantity = num.tryParse(rawQuantity.toString()) ?? 0;
        return quantity > 0;
      }).toList();

      if (activeDocs.isEmpty) {
        final prompt =
            "Context: The user's pantry is currently empty.\n\nUser request: $text";
        return await _queryProxy(prompt);
      }

      // 2. Exact FEFO Sorting using earliest active batch expiry
      activeDocs.sort((a, b) {
        final expiryA = _earliestBatchExpiry(a.data());
        final expiryB = _earliestBatchExpiry(b.data());

        if (expiryA == null && expiryB == null) return 0;
        if (expiryA == null) return 1;
        if (expiryB == null) return -1;
        return expiryA.compareTo(expiryB);
      });

      final List<String> pantryItems = activeDocs.map((doc) {
        return _inventoryLineForItem(doc);
      }).toList();

      final contextText = """
User Culinary/Dietary Preferences: $preferences

Current Pantry Inventory (SORTED BY SOONEST EXPIRY - FEFO PRINCIPLE):
${pantryItems.join('\n')}
""";

      final prompt = "Context: $contextText\n\nUser request: $text";
      return await _queryProxy(prompt);
    } catch (e) {
      String errorMsg = 'An error occurred. Please try again.';
      final errorStr = e.toString().toLowerCase();

      if (errorStr.contains('network') ||
          errorStr.contains('socket') ||
          errorStr.contains('host')) {
        errorMsg =
            'No internet connection. I need network access to generate recipes.';
      } else if (errorStr.contains('api key') ||
          errorStr.contains('unregistered caller')) {
        errorMsg = 'System error: API key is missing or invalid.';
      }
      return errorMsg;
    }
  }

  DateTime? _earliestBatchExpiry(Map<String, dynamic> data) {
    final batches = data['batches'] as List<dynamic>?;
    if (batches == null || batches.isEmpty) return null;

    DateTime? earliest;
    for (final rawBatch in batches) {
      if (rawBatch is! Map) continue;
      final quantityRaw = rawBatch['quantity'] ?? rawBatch['qty'];
      final isConsumed =
          rawBatch['isConsumed'] ?? rawBatch['consumed'] ?? false;
      final quantity = num.tryParse(quantityRaw?.toString() ?? '') ?? 0;
      if (quantity <= 0 || isConsumed == true) continue;

      final rawExpiry = rawBatch['expiryDate'];
      DateTime? expiry;
      if (rawExpiry is Timestamp) {
        expiry = rawExpiry.toDate();
      } else if (rawExpiry is DateTime) {
        expiry = rawExpiry;
      }
      if (expiry == null) continue;

      if (earliest == null || expiry.isBefore(earliest)) {
        earliest = expiry;
      }
    }

    return earliest;
  }

  String _inventoryLineForItem(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final name = data['name'] ?? data['nume'] ?? 'Produs necunoscut';
    final batches = data['batches'] as List<dynamic>?;
    final batchDescriptions = <String>[];
    var batchIndex = 0;

    if (batches != null) {
      for (final rawBatch in batches) {
        if (rawBatch is! Map) continue;
        final quantityRaw = rawBatch['quantity'] ?? rawBatch['qty'];
        final isConsumed =
            rawBatch['isConsumed'] ?? rawBatch['consumed'] ?? false;
        final quantity = num.tryParse(quantityRaw?.toString() ?? '') ?? 0;
        if (quantity <= 0 || isConsumed == true) continue;

        final rawExpiry = rawBatch['expiryDate'];
        DateTime? expiry;
        if (rawExpiry is Timestamp) {
          expiry = rawExpiry.toDate();
        } else if (rawExpiry is DateTime) {
          expiry = rawExpiry;
        }
        if (expiry == null) continue;

        batchIndex += 1;
        final daysRemaining = expiry.difference(DateTime.now()).inDays;
        final unitLabel = quantity == 1 ? 'unit' : 'units';
        batchDescriptions.add(
          '[Batch $batchIndex: $quantity $unitLabel, expires in $daysRemaining days]',
        );
      }
    }

    final batchText = batchDescriptions.join(' | ');
    if (batchText.isEmpty) {
      return '$name: [No active batches]';
    }
    return '$name: $batchText';
  }

  Future<String> _queryProxy(String prompt) async {
    const systemInstruction =
        'SYSTEM INSTRUCTION: You are a smart pantry assistant. You MUST base all consumption recommendations strictly on the precise batch-level expiration data provided below. Ignore general perishability rules. If a batch of \'Pepsi\' expires in 0 days (today), it has absolute priority over a batch of \'Fresh Chicken\' that expires in 5 days. Reference the specific quantities and days remaining when answering the user. STRICT HEALTH SAFETY RULE: You are strictly FORBIDDEN from recommending the consumption of any item that is already expired (where days remaining is less than 0), regardless of the item type. Do not suggest checking for smell or appearance for expired meat, dairy, or cooked food; explicitly instruct the user to DISCARD them. If there are not enough unexpired, safe ingredients to form a coherent meal, DO NOT force a recipe. Instead, clearly state that their options are limited due to expired items, and suggest a smart SHOPPING LIST to complement the remaining safe ingredients. NO FOLLOW-UP QUESTIONS RULE: You are operating in a stateless, single-turn environment. The user cannot reply to you. Therefore, you MUST NOT ask any follow-up questions. Do not end your responses with questions like \'What do you think?\', \'Should I generate a recipe?\', or \'Do you want another option?\'. Provide complete, definitive, and self-contained answers. Never prompt the user for more information.';

    final requestContents = _messages.map<Map<String, dynamic>>((message) {
      return {
        'role': message.isUser ? 'user' : 'model',
        'parts': [
          {'text': message.text}
        ]
      };
    }).toList();

    final lastUserIndex =
        requestContents.lastIndexWhere((entry) => entry['role'] == 'user');
    if (lastUserIndex >= 0) {
      requestContents[lastUserIndex]['parts'][0]['text'] =
          '$systemInstruction\n\n$prompt';
    }

    final uri = Uri.parse('https://ai-pantry-proxy.hadasajercau.workers.dev/');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': requestContents,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
          'Proxy request failed with status ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final text =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    return text ?? 'I could not generate a response.';
  }

  Future<void> _saveRecipe(String recipeText) async {
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final docId = recipeText.hashCode.toString();
      await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('recipes')
          .doc(docId)
          .set({
        'text': recipeText,
        'createdAt': Timestamp.now(),
        'savedBy': currentUid,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recipe saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving recipe: $e')),
        );
      }
    }
  }

  Future<Widget> _buildAddedByLine(String? uid) async {
    if (uid == null || uid.isEmpty) {
      return const SizedBox.shrink();
    }

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final displayName =
        userDoc.data()?['displayName'] as String? ?? 'Unknown user';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.person_outline, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Text(
          displayName,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Future<void> _showSavedRecipes() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            top: 20,
            left: 20,
            right: 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Saved recipes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: MediaQuery.of(sheetContext).size.height * 0.7,
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('households')
                      .doc(widget.householdId)
                      .collection('recipes')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final recipes = snapshot.data?.docs ?? [];
                    if (recipes.isEmpty) {
                      return const Center(
                        child: Text('No saved recipes yet.'),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: recipes.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final doc = recipes[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final recipeText = data['text'] as String? ?? '';
                        return Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: MarkdownBody(
                                        data: recipeText,
                                        styleSheet: MarkdownStyleSheet(
                                          p: TextStyle(
                                            color: Colors.grey.shade900,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline),
                                      onPressed: () async {
                                        await doc.reference.delete();
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                FutureBuilder<Widget>(
                                  future: _buildAddedByLine(
                                      data['savedBy'] as String?),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const SizedBox.shrink();
                                    }
                                    return snapshot.data!;
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(Message(text: text, isUser: true));
      _isSending = true;
      _controller.clear();
    });

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );

    final response = await _processMessage(text);

    setState(() {
      _messages.add(Message(text: response, isUser: false));
      _isSending = false;
    });

    await Future.delayed(const Duration(milliseconds: 50));
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent + 80,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Assistant'),
        centerTitle: true,
        leading: const Icon(Icons.auto_awesome),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: _showSavedRecipes,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length + (_isSending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade200,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(4),
                              bottomRight: Radius.circular(18),
                            ),
                          ),
                          child: const Text(
                            'Assistant is thinking...',
                            style: TextStyle(
                              color: Colors.black54,
                              fontStyle: FontStyle.italic,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  final message = _messages[index];
                  if (message.isUser) {
                    return Align(
                      alignment: Alignment.centerRight,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          child: Text(
                            message.text,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    );
                  }

                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(18),
                                topRight: Radius.circular(18),
                                bottomLeft: Radius.circular(4),
                                bottomRight: Radius.circular(18),
                              ),
                            ),
                            child: MarkdownBody(
                              data: message.text,
                              styleSheet: MarkdownStyleSheet(
                                p: TextStyle(
                                  color: Colors.grey.shade900,
                                  fontSize: 15,
                                ),
                                code: const TextStyle(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.teal,
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: () => _saveRecipe(message.text),
                          icon: const Icon(
                            Icons.bookmark_add_outlined,
                            size: 16,
                          ),
                          label: const Text(
                            'Save',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Type your message...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.teal),
                    disabledColor: Colors.grey.shade400,
                    onPressed: _isSending ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
