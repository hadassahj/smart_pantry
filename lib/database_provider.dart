import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_provider.dart';

final householdProvider = FutureProvider<String?>((ref) async {
  final user = await ref.watch(authProvider.future);
  if (user == null) return null;

  final db = FirebaseFirestore.instance;
  final prefs = await SharedPreferences.getInstance();

  // Verificăm DACĂ avem deja un Household ID salvat local în browser/telefon
  String? householdId = prefs.getString('pantry_household_id');

  if (householdId != null) {
    return householdId;
  }

  // Dacă nu avem salvat local, căutăm în Firebase după User UID
  final userRef = db.collection('users').doc(user.uid);
  final userDoc = await userRef.get();

  if (userDoc.exists) {
    householdId = userDoc.data()?['householdId'];
  } else {
    // Creăm unul nou dacă nu există niciunde
    final newHouseholdRef = db.collection('households').doc();
    await newHouseholdRef.set({
      'createdAt': FieldValue.serverTimestamp(),
    });

    householdId = newHouseholdRef.id;

    await userRef.set({
      'householdId': householdId,
      'role': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // SALVĂM LOCAL ID-ul ca să nu-l mai pierdem la refresh
  if (householdId != null) {
    await prefs.setString('pantry_household_id', householdId);
  }

  return householdId;
});
