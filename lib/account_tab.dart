import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AccountTab extends StatefulWidget {
  final String householdId;
  const AccountTab({super.key, required this.householdId});

  @override
  State<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<AccountTab> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _dietaryController = TextEditingController();
  bool _isProcessing = false;
  bool _isSavingPreferences = false;
  bool isLoginMode = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentName();
    _loadDietaryPreferences();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _dietaryController.dispose();
    super.dispose();
  }

  String _shortId(String id) {
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadCurrentName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final name =
        doc.data()?['displayName'] as String? ?? user.displayName ?? '';
    _nameController.text = name;
  }

  Future<void> _loadDietaryPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final preferences = doc.data()?['dietaryPreferences'] as String? ?? '';
    _dietaryController.text = preferences;
  }

  Future<void> _saveDisplayName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('Te rog introdu numele.');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Nu există utilizator conectat.');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {'displayName': name},
        SetOptions(merge: true),
      );
      await user.updateDisplayName(name);
      _showMessage('Numele a fost salvat.');
      if (mounted) setState(() {});
    } catch (_) {
      _showMessage('Eroare la salvarea numelui.');
    }
  }

  Future<void> _saveDietaryPreferences() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Nu există utilizator conectat.');
      return;
    }

    setState(() {
      _isSavingPreferences = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'dietaryPreferences': _dietaryController.text.trim(),
        },
        SetOptions(merge: true),
      );
      _showMessage('Preferințele culinare au fost salvate.');
    } catch (_) {
      _showMessage('Eroare la salvarea preferințelor culinare.');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingPreferences = false;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchInventoryItems(
      String householdId) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('households')
        .doc(householdId)
        .collection('inventory')
        .get();

    return snapshot.docs.map((doc) {
      final data = Map<String, dynamic>.from(doc.data());
      return data;
    }).toList();
  }

  Future<String> _ensureHouseholdForCurrentUser(User user) async {
    final db = FirebaseFirestore.instance;
    final prefs = await SharedPreferences.getInstance();
    final userRef = db.collection('users').doc(user.uid);
    final userDoc = await userRef.get();

    String? householdId = userDoc.data()?['householdId'] as String?;

    if (householdId != null && householdId.isNotEmpty) {
      final householdDoc =
          await db.collection('households').doc(householdId).get();
      if (!householdDoc.exists) {
        householdId = null;
      }
    }

    if (householdId == null) {
      final newHouseholdRef = db.collection('households').doc();
      await newHouseholdRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'members': [user.uid],
        'ownerId': user.uid,
      });
      householdId = newHouseholdRef.id;
      await userRef.set({
        'householdId': householdId,
        'role': 'admin',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      await db.collection('households').doc(householdId).set({
        'members': FieldValue.arrayUnion([user.uid]),
      }, SetOptions(merge: true));
      await userRef.set({'householdId': householdId}, SetOptions(merge: true));
    }

    await prefs.setString('pantry_household_id', householdId);
    return householdId;
  }

  Future<void> _mergeInventory(
    String fromHouseholdId,
    String toHouseholdId,
    List<Map<String, dynamic>> items,
  ) async {
    if (fromHouseholdId == toHouseholdId || items.isEmpty) return;

    final targetRef = FirebaseFirestore.instance
        .collection('households')
        .doc(toHouseholdId)
        .collection('inventory');

    for (final item in items) {
      await targetRef.add({
        ...item,
        'mergedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> _handleFormSubmit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showMessage('Completează email și parolă.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final String oldHouseholdId = widget.householdId;
      final List<Map<String, dynamic>> oldItems =
          await _fetchInventoryItems(oldHouseholdId);

      if (isLoginMode) {
        final result = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        final user = result.user;
        if (user == null) {
          throw FirebaseAuthException(
              code: 'unknown', message: 'Nu s-a putut autentifica.');
        }

        final newHouseholdId = await _ensureHouseholdForCurrentUser(user);
        await _mergeInventory(oldHouseholdId, newHouseholdId, oldItems);
        _showMessage('Autentificare reușită!');
      } else {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _showMessage('Nu există utilizator conectat.');
          return;
        }

        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        await user.linkWithCredential(credential);
        await _ensureHouseholdForCurrentUser(user);
        _showMessage('Cont creat cu succes!');
      }

      _passwordController.clear();
      if (mounted)
        setState(() {
          isLoginMode = false;
        });
    } on FirebaseAuthException catch (e) {
      final code = e.code;
      String message;
      if (isLoginMode) {
        if (code == 'user-not-found') {
          message = 'Utilizator negăsit.';
        } else if (code == 'wrong-password') {
          message = 'Parolă incorectă.';
        } else if (code == 'invalid-email') {
          message = 'Email invalid.';
        } else {
          message = e.message ?? 'Eroare la autentificare.';
        }
      } else {
        if (code == 'email-already-in-use') {
          message = 'Email-ul este deja folosit. Încearcă alt email.';
        } else if (code == 'weak-password') {
          message = 'Parola este prea slabă.';
        } else if (code == 'invalid-email') {
          message = 'Email invalid.';
        } else {
          message = e.message ?? 'A apărut o eroare la crearea contului.';
        }
      }
      _showMessage(message);
    } catch (_) {
      _showMessage('A apărut o eroare. Încearcă din nou mai târziu.');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showMessage('Te rog introdu email-ul pentru resetare.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showMessage('Email de resetare trimis!');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showMessage('Utilizator negăsit.');
      } else if (e.code == 'invalid-email') {
        _showMessage('Email invalid.');
      } else {
        _showMessage(e.message ?? 'Eroare la trimiterea resetului de parolă.');
      }
    } catch (_) {
      _showMessage('A apărut o eroare. Încearcă din nou mai târziu.');
    }
  }

  Future<void> _signOutAndAnonymous() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pantry_household_id');

      await FirebaseAuth.instance.signOut();
      await FirebaseAuth.instance.signInAnonymously();
      _showMessage('Ai fost deconectat și conectat anonim.');
    } on FirebaseAuthException catch (e) {
      _showMessage(e.message ?? 'Eroare la deconectare.');
    } catch (_) {
      _showMessage('A apărut o eroare la deconectare.');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contul Meu'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final user = snapshot.data ?? FirebaseAuth.instance.currentUser;
            final isAnonymous = user?.isAnonymous ?? true;
            final uid = user?.uid ?? 'necunoscut';
            final email = user?.email ?? '';

            return SingleChildScrollView(
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
                                ? 'Momentan ești un utilizator anonim. Pentru siguranța datelor, creează cont.'
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
                  if (!isAnonymous) ...[
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Numele tău',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _saveDisplayName,
                        child: const Text('Salvează numele'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.restaurant_menu_rounded,
                                    color: Colors.teal),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Preferințe culinare / Dietă',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _dietaryController,
                              decoration: const InputDecoration(
                                hintText:
                                    'Ex: Paleo, Vegan, Fără gluten, Halal, Adventist...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: _isSavingPreferences
                                    ? null
                                    : _saveDietaryPreferences,
                                child: _isSavingPreferences
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Salvează preferințe'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  if (isAnonymous) ...[
                    Text(
                      isLoginMode
                          ? 'Ai deja cont? Autentifică-te pentru a accesa gospodăria.'
                          : 'Momentan ești un utilizator anonim. Pentru siguranța datelor, creează cont.',
                      style: const TextStyle(fontSize: 16),
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
                    if (isLoginMode) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _sendPasswordReset,
                          child: const Text('Ai uitat parola?'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _handleFormSubmit,
                        child: _isProcessing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                isLoginMode ? 'Loghează-te' : 'Creează cont'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: _isProcessing
                            ? null
                            : () {
                                setState(() {
                                  isLoginMode = !isLoginMode;
                                });
                              },
                        child: Text(isLoginMode
                            ? 'Nu ai cont? Creează cont'
                            : 'Ai deja cont? Loghează-te'),
                      ),
                    ),
                  ] else ...[
                    Text(
                      'Cont securizat cu emailul: $email',
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _signOutAndAnonymous,
                        child: _isProcessing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Sign Out'),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
