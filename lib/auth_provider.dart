import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final authProvider = StreamProvider<User?>((ref) async* {
  final auth = FirebaseAuth.instance;

  await for (final user in auth.authStateChanges()) {
    if (user != null) {
      yield user;
      continue;
    }

    try {
      final credential = await auth.signInAnonymously();
      yield credential.user;
    } catch (_) {
      yield null;
    }
  }
});
