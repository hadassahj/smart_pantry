import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Folosim intl pentru a formata data frumos
import 'add_product_sheet.dart';

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
  }

  // --- NOU: Funcția care arată detaliile loturilor ---
  void _showBatchDetails(
      BuildContext context, String name, List<dynamic> batches) {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          // Ordonăm și aici loturile ca să le vadă de la cel mai critic la cel mai sigur
          final sortedBatches = List.from(batches)
            ..sort((a, b) => (a['expiryDate'] as Timestamp)
                .compareTo(b['expiryDate'] as Timestamp));

          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Detalii stoc: $name',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Divider(),
                // Construim lista de loturi
                ...sortedBatches.where((b) => b['quantity'] > 0).map((batch) {
                  final expiryDate =
                      (batch['expiryDate'] as Timestamp).toDate();
                  final quantity = batch['quantity'];
                  final formattedDate =
                      DateFormat('dd MMM yyyy').format(expiryDate);

                  final daysLeft = expiryDate.difference(DateTime.now()).inDays;
                  Color textColor = daysLeft <= 3 ? Colors.red : Colors.teal;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text('Expiră pe: $formattedDate',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, color: textColor)),
                    subtitle: Text(
                        'Adăugat manual'), // Aici va scrie "Scanat" mai târziu
                    trailing: Text('x$quantity',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                  );
                }),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonal(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Închide'),
                  ),
                ),
              ],
            ),
          );
        });
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
                  color: Colors.red.shade400,
                  child: const Icon(Icons.check_circle_outline,
                      color: Colors.white),
                ),
                onDismissed: (direction) {
                  FirebaseFirestore.instance
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
                },
                child: Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    // --- NOU: Aici ascultăm click-ul pe card ---
                    onTap: () => _showBatchDetails(context, name, batches),
                    leading: const CircleAvatar(
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.fastfood, color: Colors.white)),
                    title: Text(name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(expiryText,
                        style: TextStyle(
                            color: expiryColor, fontWeight: FontWeight.w500)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (totalQuantity > 1)
                          IconButton(
                            icon: Icon(Icons.remove_circle_outline,
                                color: Colors.teal.shade300),
                            onPressed: () =>
                                _consumeOneItem(doc.id, productData),
                          ),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: Colors.teal.shade50,
                              borderRadius: BorderRadius.circular(10)),
                          child: Text('x$totalQuantity',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal)),
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
        onPressed: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (context) => AddProductSheet(householdId: householdId)),
        icon: const Icon(Icons.barcode_reader),
        label: const Text('Adaugă'),
      ),
    );
  }
}
