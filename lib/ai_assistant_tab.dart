import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  bool _isSending = false;

  Future<String> _processMessage(String text) async {
    // TODO: În viitor, folosește produselor din gospodăria curentă ca context RAG.
    // final snapshot = await FirebaseFirestore.instance
    //     .collection('households')
    //     .doc(widget.householdId)
    //     .collection('inventory')
    //     .where('isConsumed', isEqualTo: false)
    //     .get();
    // final activeProducts = snapshot.docs.map((doc) => doc.data()).toList();

    await Future.delayed(const Duration(seconds: 1));
    return 'Am înțeles! În curând voi adăuga informații inteligente bazate pe cămara ta.';
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
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: message.isUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: message.isUser
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(18),
                          topRight: const Radius.circular(18),
                          bottomLeft: Radius.circular(message.isUser ? 18 : 4),
                          bottomRight: Radius.circular(message.isUser ? 4 : 18),
                        ),
                      ),
                      child: Text(
                        message.text,
                        style: TextStyle(
                          color: message.isUser
                              ? Colors.white
                              : Colors.grey.shade900,
                          fontSize: 15,
                        ),
                      ),
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
                    icon: _isSending
                        ? const CircularProgressIndicator()
                        : const Icon(Icons.send, color: Colors.teal),
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
