import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AccountTab extends StatefulWidget {
  final String householdId;
  const AccountTab({super.key, required this.householdId});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLinking = false;

  String _shortId(String id) {
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  Future<void> _linkAccount() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completează email și parolă.')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nu există utilizator conectat.')),
      );
      return;
    }

    setState(() {
      _isLinking = true;
    });

    try {
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.linkWithCredential(credential);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cont securizat cu succes!')),
      );
      setState(() {});
    } on FirebaseAuthException catch (e) {
      final message = e.code == 'email-already-in-use'
          ? 'Email-ul este deja folosit. Încearcă alt email.'
          : e.message ?? 'A apărut o eroare la securizarea contului.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('A apărut o eroare. Încearcă din nou mai târziu.')),
      );
    } finally {
      setState(() {
        _isLinking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final isAnonymous = user?.isAnonymous ?? true;
    final uid = user?.uid ?? 'necunoscut';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contul Meu'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAnonymous ? 'Cont Anonim' : 'Cont Legat',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isAnonymous ? Colors.orange : Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isAnonymous
                            ? 'Risc de pierdere a datelor'
                            : 'Cont securizat cu email',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          const Icon(Icons.account_circle_outlined,
                              color: Colors.grey),
                          const SizedBox(width: 8),
                          Text(
                            'UID: ${_shortId(uid)}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (isAnonymous) ...[
                const Text(
                  'Securizează contul cu email pentru a nu pierde accesul la gospodăria ta.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Parolă',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLinking ? null : _linkAccount,
                    child: _isLinking
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Securizează Contul'),
                  ),
                ),
              ] else ...[
                const Text(
                  'Contul tău este legat de un email și este securizat.',
                  style: TextStyle(fontSize: 16),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
