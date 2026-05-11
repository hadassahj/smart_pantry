import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_provider.dart';

final householdProvider = FutureProvider<String?>((ref) async {
  final user = await ref.watch(authProvider.future);
  if (user == null) return null;

  final db = FirebaseFirestore.instance;
  final prefs = await SharedPreferences.getInstance();

  String? householdId = prefs.getString('pantry_household_id');

  if (householdId != null) {
    final householdDoc =
        await db.collection('households').doc(householdId).get();
    if (!householdDoc.exists ||
        !(List.from(householdDoc.data()?['members'] ?? [])
            .contains(user.uid))) {
      householdId = null;
    }
  }

  final userRef = db.collection('users').doc(user.uid);
  final userDoc = await userRef.get();
  final existingHouseholdId = userDoc.data()?['householdId'] as String?;

  if (existingHouseholdId != null && existingHouseholdId.isNotEmpty) {
    householdId = existingHouseholdId;
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
});
