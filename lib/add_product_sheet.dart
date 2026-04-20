import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Avem nevoie pentru formatarea datei

class AddProductSheet extends StatefulWidget {
  final String householdId;
  const AddProductSheet({super.key, required this.householdId});

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  final TextEditingController _nameController = TextEditingController();
  int _quantity = 1;
  DateTime _selectedExpiryDate =
      DateTime.now().add(const Duration(days: 7)); // Default 7 zile
  bool _isLoading = false;

  // Funcția pentru a deschide calendarul
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedExpiryDate,
      firstDate: DateTime.now(), // Nu putem seta expirare în trecut
      lastDate: DateTime.now().add(const Duration(days: 3650)), // +10 ani
    );
    if (picked != null) {
      setState(() => _selectedExpiryDate = picked);
    }
  }

  Future<void> _saveProduct() async {
    final productName = _nameController.text.trim();
    if (productName.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final inventoryRef = FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('inventory');

      final querySnapshot = await inventoryRef
          .where('name', isEqualTo: productName)
          .limit(1)
          .get();

      // Creăm noul lot (batch)
      final newBatch = {
        'quantity': _quantity,
        'expiryDate': Timestamp.fromDate(_selectedExpiryDate),
        'addedAt': Timestamp.now(), // <--- AICI AM FĂCUT MODIFICAREA
        'source': 'manual'
      };

      if (querySnapshot.docs.isNotEmpty) {
        // PRODUSUL EXISTĂ: Adăugăm lotul la lista existentă
        final doc = querySnapshot.docs.first;
        final docId = doc.id;
        final currentTotal = doc.data()['totalQuantity'] ?? 0;

        List<dynamic> currentBatches = List.from(doc.data()['batches'] ?? []);
        currentBatches.add(newBatch);

        await inventoryRef.doc(docId).update({
          'totalQuantity': currentTotal + _quantity,
          'batches': currentBatches,
          'isConsumed': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // PRODUS NOU
        await inventoryRef.add({
          'name': productName,
          'totalQuantity': _quantity,
          'isConsumed': false,
          'batches': [newBatch], // Array cu un singur element momentan
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$productName adăugat! 🥫')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Eroare: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20,
        right: 20,
        top: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Adaugă Produs',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
                labelText: 'Nume Produs',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.fastfood)),
            autofocus: true,
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Expiră la:', style: TextStyle(fontSize: 16)),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(
                    DateFormat('dd MMM yyyy').format(_selectedExpiryDate),
                    style: const TextStyle(fontSize: 16)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cantitate:', style: TextStyle(fontSize: 16)),
              Row(
                children: [
                  IconButton(
                      onPressed: () {
                        if (_quantity > 1) setState(() => _quantity--);
                      },
                      icon: const Icon(Icons.remove_circle_outline)),
                  Text('$_quantity',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                      onPressed: () => setState(() => _quantity++),
                      icon: const Icon(Icons.add_circle_outline)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _isLoading ? null : _saveProduct,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Salvează în Cămară',
                      style: TextStyle(fontSize: 16)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
