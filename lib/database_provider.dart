import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_provider.dart';
import 'package:flutter/material.dart';

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

final databaseProvider =
    ChangeNotifierProvider.family<DatabaseProvider, String>(
  (ref, householdId) => DatabaseProvider(householdId),
);

class DatabaseProvider extends ChangeNotifier {
  DatabaseProvider(this.householdId) {
    _subscribeToInventory();
  }

  final String householdId;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _inventorySubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _inventoryDocuments = [];

  void _subscribeToInventory() {
    _inventorySubscription = FirebaseFirestore.instance
        .collection('households')
        .doc(householdId)
        .collection('inventory')
        .snapshots()
        .listen((snapshot) {
      _inventoryDocuments = snapshot.docs;
      notifyListeners();
    }, onError: (_) {
      // If the inventory stream has an error, keep previous state but notify listeners
      notifyListeners();
    });
  }

  DatabaseProvider.withoutSubscription(this.householdId);

  Future<String?> getLocalBarcodeName(String barcode) async {
    if (barcode.trim().isEmpty) return null;

    final householdDoc = await FirebaseFirestore.instance
        .collection('households')
        .doc(householdId)
        .get();
    if (!householdDoc.exists) return null;

    final savedBarcodes = householdDoc.data()?['savedBarcodes'];
    if (savedBarcodes is Map<String, dynamic>) {
      final barcodeName = savedBarcodes[barcode];
      return barcodeName is String ? barcodeName : null;
    }
    return null;
  }

  Future<void> saveLocalBarcodeName(String barcode, String name) async {
    final cleanedBarcode = barcode.trim();
    final cleanedName = name.trim();
    if (cleanedBarcode.isEmpty || cleanedName.isEmpty) return;

    final householdRef =
        FirebaseFirestore.instance.collection('households').doc(householdId);

    try {
      await householdRef.update({'savedBarcodes.$cleanedBarcode': cleanedName});
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' ||
          e.message?.contains('No document to update') == true) {
        await householdRef.set(
          {
            'savedBarcodes': {cleanedBarcode: cleanedName}
          },
          SetOptions(merge: true),
        );
      } else {
        rethrow;
      }
    }
  }

  Map<String, int> getPantryStatistics() {
    int totalItems = 0;
    int expiredItems = 0;
    int atRiskItems = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final doc in _inventoryDocuments) {
      final data = doc.data();
      if (data['isConsumed'] == true) continue;

      final batches = data['batches'];
      if (batches is! List) continue;

      for (final rawBatch in batches) {
        if (rawBatch is! Map) continue;

        final int batchQty = _parseBatchQuantity(rawBatch['quantity']);
        if (batchQty <= 0) continue;

        final expiryDate = _normalizeExpiryDate(rawBatch['expiryDate']);
        totalItems += batchQty;
        if (expiryDate == null) continue;

        final expiryDay = DateTime(
          expiryDate.year,
          expiryDate.month,
          expiryDate.day,
        );

        final daysLeft = expiryDay.difference(today).inDays;
        if (daysLeft < 0) {
          expiredItems += batchQty;
        } else if (daysLeft <= 3) {
          atRiskItems += batchQty;
        }
      }
    }

    return {
      'total': totalItems,
      'expired': expiredItems,
      'atRisk': atRiskItems,
    };
  }

  int _parseBatchQuantity(dynamic quantity) {
    if (quantity is int) return quantity;
    if (quantity is double) return quantity.toInt();
    if (quantity is String) return int.tryParse(quantity) ?? 0;
    return 0;
  }

  DateTime? _normalizeExpiryDate(dynamic expiryValue) {
    if (expiryValue is Timestamp) {
      return expiryValue.toDate();
    }
    if (expiryValue is DateTime) {
      return expiryValue;
    }
    if (expiryValue is String) {
      return DateTime.tryParse(expiryValue);
    }
    return null;
  }

  @override
  void dispose() {
    _inventorySubscription?.cancel();
    super.dispose();
  }
}

Future<String?> getLocalBarcodeNameForHousehold(
    String householdId, String barcode) {
  return DatabaseProvider.withoutSubscription(householdId)
      .getLocalBarcodeName(barcode);
}

Future<void> saveLocalBarcodeNameForHousehold(
    String householdId, String barcode, String name) {
  return DatabaseProvider.withoutSubscription(householdId)
      .saveLocalBarcodeName(barcode, name);
}
