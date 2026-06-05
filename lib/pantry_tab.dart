import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Folosim intl pentru a forma data frumos
import 'add_product_sheet.dart';
import 'database_provider.dart';
import 'scanner_screen.dart'; //
import 'package:http/http.dart' as http;
import 'dart:convert';

class PantryTab extends StatefulWidget {
  final String householdId;
  const PantryTab({super.key, required this.householdId});

  @override
  State<PantryTab> createState() => _PantryTabState();
}

class _PantryTabState extends State<PantryTab> {
  String searchQuery = '';

  // Algoritmul FEFO PENTRU CONSUM (Rămâne neschimbat)
  Future<void> _consumeOneItem(
      String docId, Map<String, dynamic> productData) async {
    List<dynamic> batches = List.from(productData['batches'] ?? []);
    int totalQuantity = productData['totalQuantity'] ?? 0;

    if (totalQuantity <= 0 || batches.isEmpty) return;

    batches.sort((a, b) =>
        (a['expiryDate'] as Timestamp).compareTo(b['expiryDate'] as Timestamp));

    for (int i = 0; i < batches.length; i++) {
      if (batches[i]['quantity'] > 0) {
        batches[i]['quantity'] -= 1;
        break;
      }
    }

    batches.removeWhere((batch) => batch['quantity'] <= 0);

    int newTotal = totalQuantity - 1;
    bool isNowGhost = newTotal <= 0;

    await FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
        .collection('inventory')
        .doc(docId)
        .update({
      'totalQuantity': newTotal,
      'batches': batches,
      'isConsumed': isNowGhost,
      'consumedAt': isNowGhost ? FieldValue.serverTimestamp() : null,
      'consumptionHistory': FieldValue.arrayUnion([Timestamp.now()]),
    });

    if (isNowGhost) {
      await _addSuggestedShoppingItem(name: productData['name'] as String?);
    }
  }

  Future<bool> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete product?'),
          content: const Text(
              'Are you sure you want to remove this item from the pantry?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _markProductConsumed(
      String docId, Map<String, dynamic> productData) async {
    await FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
        .collection('inventory')
        .doc(docId)
        .update({
      'isConsumed': true,
      'totalQuantity': 0,
      'batches': [],
      'consumedAt': FieldValue.serverTimestamp(),
      'consumptionHistory': FieldValue.arrayUnion([Timestamp.now()]),
    });
    await _addSuggestedShoppingItem(name: productData['name'] as String?);
  }

  Future<void> _addSuggestedShoppingItem({String? name}) async {
    final suggestedName =
        (name?.trim().isEmpty ?? true) ? 'Product' : name!.trim();
    try {
      await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('shopping_list')
          .add({
        'name': suggestedName,
        'quantity': '1',
        'estimatedPrice': 0.0,
        'isBought': false,
        'isSuggested': true,
        'addedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Silently ignore suggestion write failures for now.
    }
  }

  Widget _buildSmartInsightCard(Map<String, dynamic> data) {
    final int totalQuantity = data['totalQuantity'] as int? ?? 0;
    final List<dynamic> rawHistory =
        data['consumptionHistory'] as List<dynamic>? ?? [];
    final history = <DateTime>[];

    for (final entry in rawHistory) {
      if (entry is Timestamp) {
        history.add(entry.toDate());
      } else if (entry is DateTime) {
        history.add(entry);
      }
    }

    if (totalQuantity == 0 || history.length < 2) {
      return Card(
        elevation: 0,
        color: Colors.grey.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.black54),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Keep using the app to unlock smart consumption predictions.',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    history.sort();
    final firstDate = history.first;
    final lastDate = history.last;
    final timespanInDays = lastDate.difference(firstDate).inHours / 24.0;

    // Strict Rule: Require at least 24 hours of real history
    if (timespanInDays < 1.0) {
      return Card(
        elevation: 0,
        color: Colors.grey.shade50,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: Colors.black54),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Keep using the app to unlock smart consumption predictions.',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final averageDaysPerUnit = timespanInDays / (history.length - 1);
    final daysRemaining = totalQuantity * averageDaysPerUnit;
    final exhaustionDate =
        DateTime.now().add(Duration(days: daysRemaining.round()));
    final nextUnitText = averageDaysPerUnit.toStringAsFixed(1);
    final exhaustionDateText = DateFormat('dd MMM yyyy').format(exhaustionDate);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.blue.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(Icons.auto_graph, color: Color(0xFF1E3A8A)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'Based on your habits, you consume one unit every ~${nextUnitText} days. Current stock will likely run out around $exhaustionDateText.',
                style: const TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- NOU: Funcția care arată detaliile loturilor ---
  void _showBatchDetails(
      BuildContext context, String docId, Map<String, dynamic> productData) {
    final String currentName = productData['name'] as String? ?? 'Product';
    final int totalQuantity = productData['totalQuantity'] as int? ?? 0;
    final String unitLabel =
        (productData['unit'] as String?)?.trim().isNotEmpty == true
            ? productData['unit'] as String
            : 'units';
    final List<dynamic> batches =
        List.from(productData['batches'] as List<dynamic>? ?? []);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      builder: (context) {
        final Map<String, Map<String, dynamic>> normalizedMap = {};
        for (final rawBatch in batches.whereType<Map<String, dynamic>>()) {
          final int quantity = rawBatch['quantity'] as int? ?? 0;
          if (quantity <= 0) continue;

          DateTime? expiry;
          final expiryValue = rawBatch['expiryDate'];
          if (expiryValue is Timestamp) {
            expiry = expiryValue.toDate();
          } else if (expiryValue is DateTime) {
            expiry = expiryValue;
          }

          final String key = expiry != null
              ? '${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}'
              : 'no-date';
          final Timestamp? normalizedExpiry = expiry != null
              ? Timestamp.fromDate(
                  DateTime(expiry.year, expiry.month, expiry.day))
              : null;

          if (normalizedMap.containsKey(key)) {
            normalizedMap[key]!['quantity'] =
                (normalizedMap[key]!['quantity'] as int? ?? 0) + quantity;
          } else {
            final batchCopy = Map<String, dynamic>.from(rawBatch);
            batchCopy['quantity'] = quantity;
            batchCopy['expiryDate'] = normalizedExpiry;
            normalizedMap[key] = batchCopy;
          }
        }

        final displayBatches = normalizedMap.values.toList();
        displayBatches.sort((a, b) {
          final aExpiry = a['expiryDate'] as Timestamp?;
          final bExpiry = b['expiryDate'] as Timestamp?;
          if (aExpiry == null && bExpiry == null) return 0;
          if (aExpiry == null) return 1;
          if (bExpiry == null) return -1;
          return aExpiry.compareTo(bExpiry);
        });

        final Timestamp? rootExpiryDate =
            productData['expiryDate'] as Timestamp?;
        final bool hasBatches = displayBatches.isNotEmpty;

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.78,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 6,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentName,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    Text(
                      '$totalQuantity $unitLabel',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF25C05),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildSmartInsightCard(productData),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Expanded(
                  child: hasBatches
                      ? ListView.separated(
                          itemCount: displayBatches.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final batch = displayBatches[index];
                            final batchQuantity =
                                batch['quantity'] as int? ?? 0;
                            final expiryTimestamp =
                                batch['expiryDate'] as Timestamp?;
                            String expiryText = 'No date';
                            Color expiryColor = Colors.black54;

                            if (expiryTimestamp != null) {
                              final expiryDate = expiryTimestamp.toDate();
                              final now = DateTime.now();
                              final today =
                                  DateTime(now.year, now.month, now.day);
                              final expiryDay = DateTime(
                                expiryDate.year,
                                expiryDate.month,
                                expiryDate.day,
                              );
                              final daysLeft =
                                  expiryDay.difference(today).inDays;

                              if (daysLeft < 0) {
                                expiryText = 'Expired!';
                                expiryColor = const Color(0xFFEF476F);
                              } else if (daysLeft == 0) {
                                expiryText = 'Expires TODAY';
                                expiryColor = const Color(0xFFF25C05);
                              } else if (daysLeft <= 3) {
                                expiryText = '~$daysLeft days';
                                expiryColor = const Color(0xFFF25C05);
                              } else {
                                expiryText = '~$daysLeft days';
                                expiryColor = Colors.green.shade700;
                              }
                            }

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 0, vertical: 4),
                              title: Text(
                                '$batchQuantity $unitLabel',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                expiryText,
                                style: TextStyle(color: expiryColor),
                              ),
                              trailing: expiryTimestamp != null
                                  ? Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(expiryTimestamp.toDate()),
                                      style: const TextStyle(
                                          color: Colors.black87),
                                    )
                                  : null,
                            );
                          },
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$totalQuantity $unitLabel',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                rootExpiryDate != null
                                    ? DateFormat('dd MMM yyyy')
                                        .format(rootExpiryDate.toDate())
                                    : 'No date',
                                style: const TextStyle(
                                  fontSize: 16,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF476F).withOpacity(0.1),
                    foregroundColor: const Color(0xFFEF476F),
                    elevation: 0,
                    minimumSize: const Size.fromHeight(60),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                  onPressed: () async {
                    final confirmed = await _confirmDelete();
                    if (!confirmed) return;
                    await _markProductConsumed(docId, productData);
                    FocusManager.instance.primaryFocus?.unfocus();
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 26),
                  label: const Text('Remove from pantry',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String> _getDisplayName(String? uid) async {
    if (uid == null || uid.isEmpty) return 'Utilizator necunoscut';
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data()?['displayName'] as String? ?? 'Utilizator necunoscut';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      backgroundColor: const Color(0xFFFFD54F),
      body: SafeArea(
        bottom: false, // Lasă albul să curgă până jos
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header-ul vibrant (zona galbenă)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFD54F),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('households')
                    .doc(widget.householdId)
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() as Map<String, dynamic>?;
                  final householdName =
                      (data?['name'] as String?)?.trim() ?? 'Household';
                  final titleText =
                      snapshot.connectionState == ConnectionState.waiting &&
                              !snapshot.hasData
                          ? 'Pantry'
                          : "$householdName's Pantry";

                  return Padding(
                    padding: const EdgeInsets.only(
                        left: 24.0, top: 20.0, bottom: 24.0),
                    child: Text(
                      titleText,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                        letterSpacing: -1.5,
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. The sheet containing the products
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: TextField(
                        onChanged: (val) => setState(() => searchQuery = val),
                        decoration: InputDecoration(
                          hintText: 'Search products',
                          prefixIcon:
                              const Icon(Icons.search, color: Colors.grey),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 0),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(40)),
                        child: StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('households')
                              .doc(widget.householdId)
                              .collection('inventory')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                  child: Text('Error: ${snapshot.error}'));
                            }
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: Color(0xFFF25C05)));
                            }

                            var activeProducts =
                                snapshot.data!.docs.where((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              return data['isConsumed'] == false;
                            }).toList();

                            final query = searchQuery.trim().toLowerCase();
                            if (query.isNotEmpty) {
                              activeProducts = activeProducts.where((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final name =
                                    (data['name'] as String?)?.toLowerCase() ??
                                        '';
                                return name.contains(query);
                              }).toList();
                            }

                            DateTime? closestExpiry(Map<String, dynamic> data) {
                              final batches = List.from(data['batches'] ?? []);
                              batches.removeWhere(
                                  (batch) => batch['expiryDate'] == null);
                              if (batches.isEmpty) return null;
                              batches.sort((a, b) =>
                                  (a['expiryDate'] as Timestamp)
                                      .compareTo(b['expiryDate'] as Timestamp));
                              return (batches.first['expiryDate'] as Timestamp)
                                  .toDate();
                            }

                            activeProducts.sort((a, b) {
                              final aData = a.data() as Map<String, dynamic>;
                              final bData = b.data() as Map<String, dynamic>;
                              final aExpiry = closestExpiry(aData);
                              final bExpiry = closestExpiry(bData);

                              if (aExpiry == null && bExpiry == null) return 0;
                              if (aExpiry == null) return 1;
                              if (bExpiry == null) return -1;
                              return aExpiry.compareTo(bExpiry);
                            });

                            if (activeProducts.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(30),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFD166)
                                            .withOpacity(0.3),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(Icons.kitchen_rounded,
                                          size: 80, color: Color(0xFFF25C05)),
                                    ),
                                    const SizedBox(height: 24),
                                    const Text('Pantry is empty.',
                                        style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87)),
                                    const SizedBox(height: 8),
                                    const Text('Tap "Add" to get started!',
                                        style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.black54)),
                                  ],
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.only(
                                  bottom: 160, left: 20, right: 20, top: 0),
                              itemCount: activeProducts.length,
                              itemBuilder: (context, index) {
                                final doc = activeProducts[index];
                                final productData =
                                    doc.data() as Map<String, dynamic>;
                                final name = productData['name'] ?? 'Product';
                                final totalQuantity =
                                    productData['totalQuantity'] ?? 0;
                                List<dynamic> batches =
                                    List.from(productData['batches'] ?? []);

                                String expiryText = 'No date';
                                Color expiryColor = Colors.grey;
                                Color badgeColor = Colors.grey.shade200;

                                if (batches.isNotEmpty) {
                                  batches.sort((a, b) => (a['expiryDate']
                                          as Timestamp)
                                      .compareTo(b['expiryDate'] as Timestamp));
                                  final closestExpiry =
                                      (batches.first['expiryDate'] as Timestamp)
                                          .toDate();
                                  final now = DateTime.now();
                                  final today =
                                      DateTime(now.year, now.month, now.day);
                                  final expiryDay = DateTime(
                                    closestExpiry.year,
                                    closestExpiry.month,
                                    closestExpiry.day,
                                  );
                                  final daysLeft =
                                      expiryDay.difference(today).inDays;

                                  if (daysLeft < 0) {
                                    expiryText = 'Expired!';
                                    expiryColor = Colors.white;
                                    badgeColor = const Color(0xFFEF476F);
                                  } else if (daysLeft == 0) {
                                    expiryText = 'Expires TODAY';
                                    expiryColor = Colors.white;
                                    badgeColor = const Color(0xFFF25C05);
                                  } else if (daysLeft <= 3) {
                                    expiryText = '~$daysLeft days';
                                    expiryColor = const Color(0xFFF25C05);
                                    badgeColor = const Color(0xFFF25C05)
                                        .withOpacity(0.15);
                                  } else {
                                    expiryText = '~$daysLeft days';
                                    expiryColor = Colors.green.shade700;
                                    badgeColor = Colors.green.shade50;
                                  }
                                }

                                return Dismissible(
                                  key: Key(doc.id),
                                  direction: DismissDirection.endToStart,
                                  confirmDismiss: (direction) =>
                                      _confirmDelete(),
                                  background: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    alignment: Alignment.centerRight,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 24),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF476F),
                                      borderRadius: BorderRadius.circular(28),
                                    ),
                                    child: const Icon(
                                        Icons.delete_sweep_rounded,
                                        color: Colors.white,
                                        size: 32),
                                  ),
                                  onDismissed: (direction) async {
                                    try {
                                      await _markProductConsumed(
                                          doc.id, productData);
                                    } catch (_) {}
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(28),
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.03),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3)),
                                      ],
                                    ),
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(28),
                                      onTap: () => _showBatchDetails(
                                          context, doc.id, productData),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16.0, vertical: 12.0),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: Colors.black87),
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 10,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: badgeColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                    ),
                                                    child: Text(
                                                      expiryText,
                                                      style: TextStyle(
                                                          color: expiryColor,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(30),
                                                  boxShadow: [
                                                    BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.03),
                                                        blurRadius: 10,
                                                        offset:
                                                            const Offset(0, 4))
                                                  ]),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.remove_rounded,
                                                        color: Colors.grey),
                                                    onPressed: () =>
                                                        _consumeOneItem(doc.id,
                                                            productData),
                                                  ),
                                                  Padding(
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8.0),
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                              minWidth: 24),
                                                      child: Text(
                                                        '$totalQuantity',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                            fontSize: 16,
                                                            fontWeight:
                                                                FontWeight.w900,
                                                            color:
                                                                Colors.black87),
                                                      ),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    icon: const Icon(
                                                        Icons.add_rounded,
                                                        color: Colors.black87),
                                                    onPressed: () {
                                                      showModalBottomSheet(
                                                        context: context,
                                                        isScrollControlled:
                                                            true,
                                                        backgroundColor:
                                                            Colors.white,
                                                        shape:
                                                            const RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.vertical(
                                                                  top: Radius
                                                                      .circular(
                                                                          40)),
                                                        ),
                                                        builder: (context) =>
                                                            AddProductSheet(
                                                          householdId: widget
                                                              .householdId,
                                                          prefilledName: name,
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      // Floating Action Button stilizat
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70.0),
        child: FloatingActionButton.extended(
          backgroundColor: const Color(0xFFF25C05),
          foregroundColor: Colors.white,
          elevation: 4,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          icon: const Icon(Icons.add_rounded, size: 28),
          label: const Text('Add',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          onPressed: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: Colors.white,
              shape: const RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(32))),
              builder: (BuildContext sheetContext) {
                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 50,
                            height: 6,
                            decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(10))),
                        const SizedBox(height: 32),
                        ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          tileColor: const Color(0xFFFFF9EC),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                                color: Color(0xFFF25C05),
                                shape: BoxShape.circle),
                            child: const Icon(Icons.document_scanner_rounded,
                                color: Colors.white),
                          ),
                          title: const Text('Scan barcode',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18)),
                          subtitle: const Text('Fast and automatic',
                              style: TextStyle(color: Colors.black54)),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            final barcode = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const ScannerScreen()));
                            if (barcode == null ||
                                barcode.toString().trim().isEmpty) {
                              return;
                            }
                            final scaffoldMessenger =
                                ScaffoldMessenger.of(context);
                            scaffoldMessenger.showSnackBar(
                              const SnackBar(
                                content: Text('Checking barcode...'),
                              ),
                            );
                            final rawBarcode = barcode.toString().trim();
                            final localName =
                                await getLocalBarcodeNameForHousehold(
                                    widget.householdId, rawBarcode);
                            if (localName != null && localName.isNotEmpty) {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(40)),
                                ),
                                builder: (context) => AddProductSheet(
                                  householdId: widget.householdId,
                                  prefilledName: localName,
                                  barcode: rawBarcode,
                                ),
                              );
                              return;
                            }
                            try {
                              final response = await http.get(Uri.parse(
                                  'https://world.openfoodfacts.org/api/v0/product/$rawBarcode.json'));
                              final data = json.decode(response.body)
                                  as Map<String, dynamic>;
                              final status = data['status'] as int? ?? 0;
                              final product =
                                  data['product'] as Map<String, dynamic>? ??
                                      {};
                              final productName =
                                  (product['product_name_ro'] as String?)
                                              ?.trim()
                                              .isNotEmpty ==
                                          true
                                      ? product['product_name_ro'] as String
                                      : (product['product_name'] as String?)
                                          ?.trim();
                              if (status == 1 &&
                                  productName != null &&
                                  productName.isNotEmpty) {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(40)),
                                  ),
                                  builder: (context) => AddProductSheet(
                                    householdId: widget.householdId,
                                    prefilledName: productName,
                                    barcode: rawBarcode,
                                  ),
                                );
                              } else {
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Product was not found.'),
                                  ),
                                );
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  backgroundColor: Colors.white,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(40)),
                                  ),
                                  builder: (context) => AddProductSheet(
                                    householdId: widget.householdId,
                                    barcode: rawBarcode,
                                  ),
                                );
                              }
                            } catch (_) {
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Error searching for the product.'),
                                ),
                              );
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                backgroundColor: Colors.white,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(40)),
                                ),
                                builder: (context) => AddProductSheet(
                                  householdId: widget.householdId,
                                  barcode: rawBarcode,
                                ),
                              );
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          tileColor: const Color(0xFFFFF9EC),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.grey.shade300,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.edit_rounded,
                                color: Colors.black87),
                          ),
                          title: const Text('Add manually',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18)),
                          onTap: () {
                            Navigator.pop(context);
                            showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (context) => AddProductSheet(
                                    householdId: widget.householdId));
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
