import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // Folosim intl pentru a forma data frumos
import 'add_product_sheet.dart';
import 'scanner_screen.dart'; //
import 'package:http/http.dart' as http;
import 'dart:convert';

class PantryTab extends StatelessWidget {
  final String householdId;
  const PantryTab({super.key, required this.householdId});

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
        .doc(householdId)
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

  Future<void> _addSuggestedShoppingItem({String? name}) async {
    final suggestedName =
        (name?.trim().isEmpty ?? true) ? 'Produs' : name!.trim();
    try {
      await FirebaseFirestore.instance
          .collection('households')
          .doc(householdId)
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
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        final sortedBatches = List.from(batches)
          ..sort((a, b) => (a['expiryDate'] as Timestamp)
              .compareTo(b['expiryDate'] as Timestamp));

        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(currentName,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.teal),
                    onPressed: () {
                      final controller =
                          TextEditingController(text: currentName);
                      showDialog(
                        context: context,
                        builder: (dialogContext) {
                          return AlertDialog(
                            title: const Text('Redenumește produsul'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                  hintText: 'Nume produs'),
                              autofocus: true,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(),
                                child: const Text('Anulează'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final newName = controller.text.trim();
                                  if (newName.isEmpty) return;
                                  await FirebaseFirestore.instance
                                      .collection('households')
                                      .doc(householdId)
                                      .collection('inventory')
                                      .doc(docId)
                                      .update({'name': newName});
                                  currentName = newName;
                                  Navigator.of(dialogContext).pop();
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
              const SizedBox(height: 10),
              const Divider(),
              Builder(builder: (context) {
                final displayBatches = sortedBatches
                    .where((batch) => batch['quantity'] > 0)
                    .toList();
                final totalUnits = displayBatches.fold<int>(
                    0, (sum, batch) => sum + (batch['quantity'] as int));
                final nextExpiryDate = displayBatches.isNotEmpty
                    ? (displayBatches.first['expiryDate'] as Timestamp).toDate()
                    : null;
                final daysUntilNext = nextExpiryDate != null
                    ? nextExpiryDate.difference(DateTime.now()).inDays
                    : null;
                final summaryColor = daysUntilNext != null
                    ? (daysUntilNext <= 3
                        ? Colors.red
                        : daysUntilNext <= 7
                            ? Colors.orange
                            : Colors.teal)
                    : Colors.grey.shade600;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total: $totalUnits unități',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(
                      nextExpiryDate != null
                          ? 'Următoarea expirare: ${DateFormat('dd MMM yyyy').format(nextExpiryDate)}'
                          : 'Nicio expirare disponibilă',
                      style: TextStyle(
                          fontSize: 14,
                          color: summaryColor,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    if (displayBatches.length > 1) ...[
                      const Divider(),
                      const SizedBox(height: 10),
                      ...displayBatches.map((batch) {
                        final expiryDate =
                            (batch['expiryDate'] as Timestamp).toDate();
                        final quantity = batch['quantity'];
                        final formattedDate =
                            DateFormat('dd MMM yyyy').format(expiryDate);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(formattedDate,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ),
                              Text('x$quantity',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ],
                );
              }),
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Șterge produsul'),
                        content: const Text(
                            'Ești sigur că vrei să ștergi complet acest produs?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Anulează'),
                          ),
                          TextButton(
                            onPressed: () async {
                              try {
                                await FirebaseFirestore.instance
                                    .collection('households')
                                    .doc(householdId)
                                    .collection('inventory')
                                    .doc(docId)
                                    .update({
                                  'isConsumed': true,
                                  'totalQuantity': 0,
                                  'batches': [],
                                });
                                await _addSuggestedShoppingItem(
                                    name: currentName);
                              } catch (_) {
                                // ignore failures in delete sheet action
                              }
                              Navigator.of(dialogContext).pop();
                              Navigator.of(sheetContext).pop();
                            },
                            child: const Text('Șterge'),
                          ),
                        ],
                      );
                    },
                  );
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Șterge produsul'),
              ),
              const SizedBox(height: 10),
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
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('households')
            .doc(householdId)
            .collection('inventory')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Center(child: Text('Eroare: ${snapshot.error}'));
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());

          final activeProducts = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['isConsumed'] == false;
          }).toList();

          DateTime? closestExpiry(Map<String, dynamic> data) {
            final batches = List.from(data['batches'] ?? []);
            batches.removeWhere((batch) => batch['expiryDate'] == null);
            if (batches.isEmpty) return null;
            batches.sort((a, b) => (a['expiryDate'] as Timestamp)
                .compareTo(b['expiryDate'] as Timestamp));
            return (batches.first['expiryDate'] as Timestamp).toDate();
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
                  Icon(Icons.kitchen, size: 80, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  const Text('Cămara e goală.',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding:
                const EdgeInsets.only(bottom: 90, left: 16, right: 16, top: 8),
            itemCount: activeProducts.length,
            itemBuilder: (context, index) {
              final doc = activeProducts[index];
              final productData = doc.data() as Map<String, dynamic>;
              final name = productData['name'] ?? 'Produs';
              final totalQuantity = productData['totalQuantity'] ?? 0;
              List<dynamic> batches = List.from(productData['batches'] ?? []);

              String expiryText = 'Fără dată';
              Color expiryColor = Colors.grey;

              if (batches.isNotEmpty) {
                batches.sort((a, b) => (a['expiryDate'] as Timestamp)
                    .compareTo(b['expiryDate'] as Timestamp));
                final closestExpiry =
                    (batches.first['expiryDate'] as Timestamp).toDate();
                final daysLeft =
                    closestExpiry.difference(DateTime.now()).inDays;

                if (daysLeft < 0) {
                  expiryText = 'Expirat de ${daysLeft.abs()} zile!';
                  expiryColor = Colors.red;
                } else if (daysLeft == 0) {
                  expiryText = 'Expiră AZI!';
                  expiryColor = Colors.orange;
                } else {
                  expiryText = 'Expiră în: ~$daysLeft zile';
                  expiryColor =
                      daysLeft <= 3 ? Colors.orange : Colors.grey.shade700;
                }
              }

              return Dismissible(
                key: Key(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  color: Colors.orange.shade300,
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Șterge produsul'),
                        content: const Text(
                            'Confirmi ștergerea completă a acestui produs?'),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Anulează'),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Șterge'),
                          ),
                        ],
                      );
                    },
                  );
                },
                onDismissed: (direction) async {
                  try {
                    await FirebaseFirestore.instance
                        .collection('households')
                        .doc(householdId)
                        .collection('inventory')
                        .doc(doc.id)
                        .update({
                      'isConsumed': true,
                      'totalQuantity': 0,
                      'batches': [],
                      'consumedAt': FieldValue.serverTimestamp(),
                    });
                    await _addSuggestedShoppingItem(
                        name: productData['name'] as String?);
                  } catch (_) {
                    // ignore failures for dismiss action
                  }
                },
                child: Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    onTap: () =>
                        _showBatchDetails(context, doc.id, productData),
                    title: Text(name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(expiryText, style: TextStyle(color: expiryColor)),
                        const SizedBox(height: 4),
                        FutureBuilder<String>(
                          future: _getDisplayName(
                              productData['addedBy'] as String?),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return const Text('',
                                  style: TextStyle(fontSize: 12));
                            }
                            return Text(
                              'Adăugat de: ${snapshot.data}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            );
                          },
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon:
                              const Icon(Icons.remove, color: Colors.redAccent),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _consumeOneItem(doc.id, productData),
                        ),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade50,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$totalQuantity',
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.teal.shade900,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, color: Colors.teal),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(20))),
                              builder: (context) => AddProductSheet(
                                householdId: householdId,
                                prefilledName: name,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Adaugă'),
        onPressed: () {
          // Deschidem un mini-meniu elegant cu două opțiuni
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (BuildContext sheetContext) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 10),
                    Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(10))),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: const CircleAvatar(
                          backgroundColor: Colors.teal,
                          child: Icon(Icons.camera_alt, color: Colors.white)),
                      title: const Text('Scanează cod de bare',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle:
                          const Text('Recunoaștere automată a produsului'),
                      onTap: () async {
                        // Închidem meniul folosind contextul lui specific
                        Navigator.pop(sheetContext);
                        await Future.delayed(const Duration(milliseconds: 200));

                        final messenger = ScaffoldMessenger.of(context);
                        debugPrint(
                            'Scanner onTap: bottom sheet closed, opening scanner');

                        final String? barcode = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const ScannerScreen()),
                        );

                        debugPrint(
                            'Scanner returned barcode: $barcode, context.mounted: ${context.mounted}');

                        if (barcode != null) {
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Row(
                                children: [
                                  SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2)),
                                  SizedBox(width: 15),
                                  Text('Căutăm produsul...'),
                                ],
                              ),
                              duration: Duration(seconds: 10),
                            ),
                          );

                          try {
                            final url = Uri.parse(
                                'https://world.openfoodfacts.org/api/v0/product/$barcode.json');
                            final response = await http.get(url);
                            debugPrint(
                                'OpenFoodFacts API response status: ${response.statusCode}');

                            if (response.statusCode == 200) {
                              final data = json.decode(response.body);
                              messenger.hideCurrentSnackBar();

                              if (data['status'] == 1) {
                                final String productName = data['product']
                                        ['product_name_ro'] ??
                                    data['product']['product_name'] ??
                                    'Produs necunoscut';

                                if (!context.mounted) {
                                  debugPrint(
                                      'Context not mounted before opening AddProductSheet (prefilled)');
                                  return;
                                }

                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(20))),
                                  builder: (context) => AddProductSheet(
                                    householdId: householdId,
                                    prefilledName: productName,
                                  ),
                                );
                              } else {
                                messenger.showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Produsul nu e în baza de date. Adaugă-l manual!')),
                                );

                                if (!context.mounted) {
                                  debugPrint(
                                      'Context not mounted before opening AddProductSheet (manual)');
                                  return;
                                }

                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (context) =>
                                      AddProductSheet(householdId: householdId),
                                );
                              }
                            } else {
                              messenger.hideCurrentSnackBar();
                              messenger.showSnackBar(
                                SnackBar(
                                    content: Text(
                                        'Eroare server: ${response.statusCode}')),
                              );
                            }
                          } catch (e, stack) {
                            debugPrint('Scanner OpenFoodFacts error: $e');
                            debugPrint('$stack');
                            messenger.hideCurrentSnackBar();
                            messenger.showSnackBar(
                              const SnackBar(
                                  content:
                                      Text('Eroare de conexiune la internet.')),
                            );
                          }
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      leading: CircleAvatar(
                          backgroundColor: Colors.grey.shade200,
                          child: const Icon(Icons.edit, color: Colors.grey)),
                      title: const Text('Adaugă manual'),
                      subtitle: const Text(
                          'Pentru alimente homemade sau fără etichetă'),
                      onTap: () {
                        Navigator.pop(context); // Închidem meniul
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) =>
                              AddProductSheet(householdId: householdId),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
