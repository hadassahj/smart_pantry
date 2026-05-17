import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

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
      text:
          'Salut! Sunt asistentul tău culinar. Te pot ajuta cu rețete pe baza cămării tale sau poți să-mi spui ce ai gătit pentru a actualiza stocul.',
      isUser: false,
    ),
  ];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final GenerativeModel _model;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _model = GenerativeModel(
      model: 'gemini-3.1-flash-lite',
      apiKey: const String.fromEnvironment('GEMINI_API_KEY'),
      systemInstruction: Content.system(
          '''You are a helpful culinary AI assistant for a smart pantry app. 
You will receive the user's current inventory. Based on it, suggest recipes or acknowledge consumed items. 
Keep answers concise, friendly, and structured using Markdown (bullet points, bold text). 
Always reply in the exact language the user used in their last message. Romanian is the default. 
When the user asks what is in their pantry, you must list absolutely every item provided in the context, including non-culinary or placeholder names like 'test'. Do not filter out any items based on your own assumptions. 
You must strictly respect the user's culinary/dietary preferences. Additionally, prioritize creating recipes that use the items at the top of the pantry list first, as they are closest to expiring.'''),
    );
  }

  Future<String> _processMessage(String text) async {
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUid)
          .get();
      final preferences = userDoc.data()?['dietaryPreferences'] as String? ??
          'Nicio preferință specială';

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
        final response = await _model.generateContent([Content.text(prompt)]);
        return response.text ?? 'Nu am putut formula un răspuns.';
      }

      // 2. Exact FEFO Sorting using 'expiryDate' on the filtered active items
      activeDocs.sort((a, b) {
        final dataA = a.data();
        final dataB = b.data();

        final rawDateA = dataA['expiryDate'];
        final rawDateB = dataB['expiryDate'];

        if (rawDateA == null && rawDateB == null) return 0;
        if (rawDateA == null) return 1;
        if (rawDateB == null) return -1;

        DateTime dateA;
        DateTime dateB;

        if (rawDateA is Timestamp) {
          dateA = rawDateA.toDate();
        } else if (rawDateA is DateTime) {
          dateA = rawDateA;
        } else {
          dateA = DateTime.now().add(const Duration(days: 3650));
        }

        if (rawDateB is Timestamp) {
          dateB = rawDateB.toDate();
        } else if (rawDateB is DateTime) {
          dateB = rawDateB;
        } else {
          dateB = DateTime.now().add(const Duration(days: 3650));
        }

        return dateA.compareTo(dateB);
      });

      // 3. Exact Data Mapping using 'totalQuantity' from active items
      final List<String> pantryItems = activeDocs.map((doc) {
        final data = doc.data();
        final name = data['name'] ?? data['nume'] ?? 'Produs necunoscut';
        final rawQuantity = data['totalQuantity'];
        final quantity = rawQuantity != null ? rawQuantity.toString() : '0';
        final unit = data['unit'] ?? data['unitMeasure'] ?? '';

        return "- $name (Cantitate: $quantity $unit)".trim();
      }).toList();

      final contextText = """
User Culinary/Dietary Preferences: $preferences

Current Pantry Inventory (SORTED BY SOONEST EXPIRY - FEFO PRINCIPLE):
${pantryItems.join('\n')}
""";

      final prompt = "Context: $contextText\n\nUser request: $text";
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? 'Nu am putut formula un răspuns.';
    } catch (e) {
      return 'Eroare tehnică: $e';
    }
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
          const SnackBar(content: Text('Rețetă salvată cu succes!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Eroare la salvarea rețetei: $e')),
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
        userDoc.data()?['displayName'] as String? ?? 'Utilizator necunoscut';

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
                    'Rețete salvate',
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
                      return Center(child: Text('Eroare: ${snapshot.error}'));
                    }

                    final recipes = snapshot.data?.docs ?? [];
                    if (recipes.isEmpty) {
                      return const Center(
                        child: Text('Nu există rețete salvate încă.'),
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
        title: const Text('Asistent Inteligent'),
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
                            'Asistentul gândește...',
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
                            'Salvează',
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
                        hintText: 'Scrie mesajul tău...',
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
