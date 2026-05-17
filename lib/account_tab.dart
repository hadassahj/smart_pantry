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
    if (!mounted) return;
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
    if (!mounted) return;
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
      if (!mounted) return;
      _showMessage('Numele a fost salvat.');
      if (mounted && ModalRoute.of(context)?.isCurrent == false) {
        Navigator.of(context).pop();
      }
      setState(() {});
    } catch (_) {
      if (!mounted) return;
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
      if (!mounted) return;
      _showMessage('Preferințele culinare au fost salvate.');
      if (mounted && ModalRoute.of(context)?.isCurrent == false) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!mounted) return;
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
        if (!mounted) return;
        _showMessage('Autentificare reușită!');
        if (mounted && ModalRoute.of(context)?.isCurrent == false) {
          Navigator.of(context).pop();
        }
      } else {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          if (!mounted) return;
          _showMessage('Nu există utilizator conectat.');
          return;
        }

        final credential = EmailAuthProvider.credential(
          email: email,
          password: password,
        );
        await user.linkWithCredential(credential);
        await _ensureHouseholdForCurrentUser(user);
        if (!mounted) return;
        _showMessage('Cont creat cu succes!');
        if (mounted && ModalRoute.of(context)?.isCurrent == false) {
          Navigator.of(context).pop();
        }
      }

      if (!mounted) return;
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
      if (!mounted) return;
      _showMessage(message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('A apărut o eroare. Încearcă din nou mai târziu.');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
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
      if (!mounted) return;
      _showMessage('Email de resetare trimis!');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'user-not-found') {
        _showMessage('Utilizator negăsit.');
      } else if (e.code == 'invalid-email') {
        _showMessage('Email invalid.');
      } else {
        _showMessage(e.message ?? 'Eroare la trimiterea resetului de parolă.');
      }
    } catch (_) {
      if (!mounted) return;
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
      if (!mounted) return;
      _showMessage('Ai fost deconectat și conectat anonim.');
      if (mounted && ModalRoute.of(context)?.isCurrent == false) {
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _showMessage(e.message ?? 'Eroare la deconectare.');
    } catch (_) {
      if (!mounted) return;
      _showMessage('A apărut o eroare la deconectare.');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _showEditNameSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Schimbă numele',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Numele tău',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isProcessing
                          ? null
                          : () async {
                              await _saveDisplayName();
                              if (mounted) Navigator.of(sheetContext).pop();
                            },
                      child: const Text('Salvează numele'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditDietSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preferințe culinare / Dietă',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _dietaryController,
                    decoration: const InputDecoration(
                      hintText:
                          'Ex: Paleo, Vegan, Fără gluten, Halal, Adventist...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSavingPreferences
                          ? null
                          : () async {
                              await _saveDietaryPreferences();
                              if (mounted) Navigator.of(sheetContext).pop();
                            },
                      child: _isSavingPreferences
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Salvează preferințe'),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showAuthSheet() async {
    bool localLoginMode = isLoginMode;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        localLoginMode ? 'Autentificare' : 'Creează cont',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
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
                      if (localLoginMode) ...[
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
                          onPressed: _isProcessing
                              ? null
                              : () async {
                                  setState(() {
                                    isLoginMode = localLoginMode;
                                  });
                                  await _handleFormSubmit();
                                  if (mounted &&
                                      ModalRoute.of(sheetContext)?.isCurrent ==
                                          true) {
                                    Navigator.of(sheetContext).pop();
                                  }
                                },
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(localLoginMode
                                  ? 'Loghează-te'
                                  : 'Creează cont'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: _isProcessing
                              ? null
                              : () {
                                  sheetSetState(() {
                                    localLoginMode = !localLoginMode;
                                  });
                                  if (mounted) {
                                    setState(() {
                                      isLoginMode = localLoginMode;
                                    });
                                  }
                                },
                          child: Text(localLoginMode
                              ? 'Nu ai cont? Creează cont'
                              : 'Ai deja cont? Loghează-te'),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFFBFBFB);
    const panelColor = Color(0xFFFFFAF0);
    const primaryTextColor = Color(0xFF2C3E50);
    const secondaryTextColor = Color(0xFF7F8C8D);
    const accentColor = Color(0xFFC0392B);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        title: const Text(
          'Contul Meu',
          style:
              TextStyle(color: primaryTextColor, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: primaryTextColor),
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

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFFFCF7), Color(0xFFF6F4EF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    color: panelColor,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        height: 60,
                        width: 60,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 10,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.person_outline,
                            color: Color(0xFF7F8C8D),
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isAnonymous ? 'Cont Anonim' : 'Cont Legat',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              isAnonymous
                                  ? 'Momentan ești un utilizator anonim. Pentru siguranța datelor, creează cont.'
                                  : 'Cont securizat cu email',
                              style: const TextStyle(
                                fontSize: 14,
                                color: secondaryTextColor,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'UID: ${_shortId(uid)}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                        child: Text(
                          'Profil',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.person_outline,
                            color: secondaryTextColor),
                        title: const Text(
                          'Numele tău',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                        subtitle: Text(
                          _nameController.text.isNotEmpty
                              ? _nameController.text
                              : 'Setează un nume',
                          style: const TextStyle(color: secondaryTextColor),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: secondaryTextColor),
                        onTap: _showEditNameSheet,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                        child: Text(
                          'Preferințe',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      ListTile(
                        leading: const Icon(Icons.restaurant_menu_rounded,
                            color: secondaryTextColor),
                        title: const Text(
                          'Preferințe culinare / Dietă',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                        subtitle: Text(
                          _dietaryController.text.isNotEmpty
                              ? _dietaryController.text
                              : 'Adaugă preferințe culinare',
                          style: const TextStyle(color: secondaryTextColor),
                        ),
                        trailing: const Icon(Icons.chevron_right,
                            color: secondaryTextColor),
                        onTap: _showEditDietSheet,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                        child: Text(
                          'Securitate & Cont',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: primaryTextColor,
                          ),
                        ),
                      ),
                      const Divider(height: 0),
                      if (isAnonymous) ...[
                        ListTile(
                          leading: const Icon(Icons.login,
                              color: secondaryTextColor),
                          title: const Text(
                            'Autentificare / Creare Cont',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: primaryTextColor,
                            ),
                          ),
                          subtitle: const Text(
                            'Convertește contul anonim într-un cont complet.',
                            style: TextStyle(color: secondaryTextColor),
                          ),
                          trailing: const Icon(Icons.chevron_right,
                              color: secondaryTextColor),
                          onTap: _showAuthSheet,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                        ),
                      ] else ...[
                        ListTile(
                          leading: const Icon(Icons.logout, color: accentColor),
                          title: const Text(
                            'Deconectare (Sign Out)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: accentColor,
                            ),
                          ),
                          subtitle: Text(
                            'Email: $email',
                            style: const TextStyle(color: secondaryTextColor),
                          ),
                          onTap: _signOutAndAnonymous,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 20),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
