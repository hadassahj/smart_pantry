import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Folosim intl pentru a forma data frumos
import 'add_product_sheet.dart';
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
          title: const Text('Ștergi produsul?'),
          content: const Text(
              'Ești sigur că vrei să elimini acest produs din cămară?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Anulează'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Șterge', style: TextStyle(color: Colors.red)),
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
    });
    await _addSuggestedShoppingItem(name: productData['name'] as String?);
  }

  Future<void> _addSuggestedShoppingItem({String? name}) async {
    final suggestedName =
        (name?.trim().isEmpty ?? true) ? 'Produs' : name!.trim();
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

  // --- NOU: Funcția care arată detaliile loturilor ---
  void _showBatchDetails(
      BuildContext context, String docId, Map<String, dynamic> productData) {
    String currentName = productData['name'] ?? 'Produs';
    final List<dynamic> batches = List.from(productData['batches'] ?? []);
    final sheetContext = context;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Important pentru colțuri rotunjite
      builder: (context) {
        final sortedBatches = List.from(batches)
          ..sort((a, b) => (a['expiryDate'] as Timestamp)
              .compareTo(b['expiryDate'] as Timestamp));

        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Linie de design sus
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
              const SizedBox(height: 24),

              // Nume produs și buton editare
              Row(
                children: [
                  Expanded(
                    child: Text(
                      currentName,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD166).withOpacity(0.3),
                      padding: const EdgeInsets.all(12),
                    ),
                    icon: const Icon(Icons.edit_rounded,
                        color: Color(0xFFF25C05)),
                    onPressed: () {
                      final controller =
                          TextEditingController(text: currentName);
                      showDialog(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            title: const Text('Redenumește produsul'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'Nume produs',
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Anulează'),
                              ),
                              ElevatedButton(
                                onPressed: () async {
                                  final newName = controller.text.trim();
                                  if (newName.isEmpty) return;
                                  await FirebaseFirestore.instance
                                      .collection('households')
                                      .doc(widget.householdId)
                                      .collection('inventory')
                                      .doc(docId)
                                      .update({'name': newName});
                                  currentName = newName;
                                  Navigator.of(context).pop();
                                },
                                child: const Text('Salvează'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Card informativ pentru stoc și expirare
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Builder(builder: (context) {
                  final displayBatches =
                      sortedBatches.where((b) => b['quantity'] > 0).toList();
                  final totalUnits = displayBatches.fold<int>(
                      0, (sum, b) => sum + (b['quantity'] as int));

                  return Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Stoc disponibil',
                              style: TextStyle(
                                  color: Colors.black54,
                                  fontWeight: FontWeight.bold)),
                          Text('$totalUnits unități',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFF25C05))),
                        ],
                      ),
                      const Divider(height: 30),
                      if (displayBatches.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Prima expirare',
                                style: TextStyle(
                                    color: Colors.black54,
                                    fontWeight: FontWeight.bold)),
                            Text(
                              DateFormat('dd MMM yyyy').format((displayBatches
                                      .first['expiryDate'] as Timestamp)
                                  .toDate()),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87),
                            ),
                          ],
                        ),
                      ]
                    ],
                  );
                }),
              ),

              const SizedBox(height: 32),

              // Buton de Ștergere tip "Chunky"
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF476F).withOpacity(0.1),
                  foregroundColor: const Color(0xFFEF476F),
                  elevation: 0,
                  minimumSize: const Size.fromHeight(65),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24)),
                ),
                onPressed: () async {
                  final confirmed = await _confirmDelete();
                  if (!confirmed) return;
                  await _markProductConsumed(docId, productData);
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 28),
                label: const Text('Elimină din cămară',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 16),
            ],
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false, // Lasă albul să curgă până jos
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header-ul vibrant (zona galbenă)
            Container(
              width: double.infinity,
              color: const Color(0xFFFFD166),
              child: const Padding(
                padding: EdgeInsets.only(left: 24.0, top: 20.0, bottom: 24.0),
                child: Text(
                  'Cămara Ta',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: Colors.black87,
                    letterSpacing: -1.5,
                  ),
                ),
              ),
            ),

            // 2. „Foaia” cu fundal rece care conține produsele
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
                          hintText: 'Caută produse',
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
                                  child: Text('Eroare: ${snapshot.error}'));
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
                                    const Text('Cămara e goală.',
                                        style: TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.black87)),
                                    const SizedBox(height: 8),
                                    const Text(
                                        'Apasă pe "Adaugă" pentru a începe!',
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
                                final name = productData['name'] ?? 'Produs';
                                final totalQuantity =
                                    productData['totalQuantity'] ?? 0;
                                List<dynamic> batches =
                                    List.from(productData['batches'] ?? []);

                                String expiryText = 'Fără dată';
                                Color expiryColor = Colors.grey;
                                Color badgeColor = Colors.grey.shade200;

                                if (batches.isNotEmpty) {
                                  batches.sort((a, b) => (a['expiryDate']
                                          as Timestamp)
                                      .compareTo(b['expiryDate'] as Timestamp));
                                  final closestExpiry =
                                      (batches.first['expiryDate'] as Timestamp)
                                          .toDate();
                                  final daysLeft = closestExpiry
                                      .difference(DateTime.now())
                                      .inDays;

                                  if (daysLeft < 0) {
                                    expiryText = 'Expirat!';
                                    expiryColor = Colors.white;
                                    badgeColor = const Color(0xFFEF476F);
                                  } else if (daysLeft == 0) {
                                    expiryText = 'Expiră AZI';
                                    expiryColor = Colors.white;
                                    badgeColor = const Color(0xFFF25C05);
                                  } else if (daysLeft <= 3) {
                                    expiryText = '~$daysLeft zile';
                                    expiryColor = const Color(0xFFF25C05);
                                    badgeColor = const Color(0xFFF25C05)
                                        .withOpacity(0.15);
                                  } else {
                                    expiryText = '~$daysLeft zile';
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
          label: const Text('Adaugă',
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
                          title: const Text('Scanează cod de bare',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 18)),
                          subtitle: const Text('Rapid și automat',
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
                                content: Text('Verific codul de bare...'),
                              ),
                            );
                            try {
                              final response = await http.get(Uri.parse(
                                  'https://world.openfoodfacts.org/api/v0/product/$barcode.json'));
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
                                  ),
                                );
                              } else {
                                scaffoldMessenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Produsul nu a fost găsit.'),
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
                                  ),
                                );
                              }
                            } catch (_) {
                              scaffoldMessenger.showSnackBar(
                                const SnackBar(
                                  content:
                                      Text('Eroare la căutarea produsului.'),
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
                          title: const Text('Adaugă manual',
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
