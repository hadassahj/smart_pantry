import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final authProvider = FutureProvider<User?>((ref) async {
  final auth = FirebaseAuth.instance;
  final prefs = await SharedPreferences.getInstance();

  // 1. Încercăm să vedem dacă Firebase are deja sesiunea activă
  User? user = auth.currentUser;

  // 2. Dacă nu, așteptăm puțin (pentru Web)
  if (user == null) {
    user = await auth
        .authStateChanges()
        .first
        .timeout(const Duration(milliseconds: 500), onTimeout: () => null);
  }

  // 3. Dacă tot e null, verificăm dacă avem un "Custom ID" salvat de noi anterior
  if (user == null) {
    final String? savedUid = prefs.getString('saved_uid');

    if (savedUid != null) {
      // Teoretic aici am putea face re-logare, dar pentru Anonymous Auth pe Web,
      // cea mai sigură metodă este să lăsăm Firebase să creeze unul și să îl salvăm.
      final userCredential = await auth.signInAnonymously();
      user = userCredential.user;
      await prefs.setString('saved_uid', user!.uid);
    } else {
      // Prima rulare absolută
      final userCredential = await auth.signInAnonymously();
      user = userCredential.user;
      await prefs.setString('saved_uid', user!.uid);
    }
  }

  return user;
});
