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
    try {
      final householdDoc = await db
          .collection('households')
          .doc(householdId)
          .get(GetOptions(source: Source.serverAndCache));
      if (!householdDoc.exists ||
          !(List.from(householdDoc.data()?['members'] ?? [])
              .contains(user.uid))) {
        householdId = null;
      }
    } catch (_) {
      // Offline or cache miss; keep the locally cached householdId if present.
    }
  }

  final userRef = db.collection('users').doc(user.uid);
  try {
    final userDoc =
        await userRef.get(GetOptions(source: Source.serverAndCache));
    final existingHouseholdId = userDoc.data()?['householdId'] as String?;
    if (existingHouseholdId != null && existingHouseholdId.isNotEmpty) {
      householdId = existingHouseholdId;
    }
  } catch (_) {
    // Offline or cache miss; preserve current householdId.
  }

  if (householdId == null) {
    final newHouseholdRef = db.collection('households').doc();
    newHouseholdRef.set({
      'createdAt': FieldValue.serverTimestamp(),
      'members': [user.uid],
      'ownerId': user.uid,
      'name': 'Household',
    });
    householdId = newHouseholdRef.id;

    userRef.set({
      'householdId': householdId,
      'role': 'admin',
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  } else {
    db.collection('households').doc(householdId).set({
      'members': FieldValue.arrayUnion([user.uid]),
    }, SetOptions(merge: true));
    userRef.set({'householdId': householdId}, SetOptions(merge: true));
  }

  prefs.setString('pantry_household_id', householdId);

  return householdId;
});
