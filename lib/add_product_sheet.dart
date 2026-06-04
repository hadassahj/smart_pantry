import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // Avem nevoie pentru formatarea datei

class AddProductSheet extends StatefulWidget {
  final String householdId;
  final String? prefilledName;
  const AddProductSheet({
    super.key,
    required this.householdId,
    this.prefilledName, // <--- ADAUGĂ ACEASTĂ LINIE
  });

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  late final TextEditingController _nameController;
  int _quantity = 1;
  DateTime _selectedExpiryDate =
      DateTime.now().add(const Duration(days: 10)); // Default 10 zile
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Dacă am primit un nume de la scaner, îl punem direct în câmpul de text!
    _nameController = TextEditingController(text: widget.prefilledName ?? '');
  }

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

  DateTime _normalizeDate(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  String _dateKey(DateTime? date) {
    if (date == null) return 'no-date';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  List<Map<String, dynamic>> _consolidateBatches(List<dynamic> rawBatches) {
    final Map<String, Map<String, dynamic>> normalized = {};
    for (final rawBatch in rawBatches.whereType<Map<String, dynamic>>()) {
      final int quantity = rawBatch['quantity'] as int? ?? 0;
      if (quantity <= 0) continue;

      DateTime? expiry;
      final expiryValue = rawBatch['expiryDate'];
      if (expiryValue is Timestamp) {
        expiry = expiryValue.toDate();
      } else if (expiryValue is DateTime) {
        expiry = expiryValue;
      }

      final String key =
          _dateKey(expiry != null ? _normalizeDate(expiry) : null);
      final Timestamp? normalizedExpiry =
          expiry != null ? Timestamp.fromDate(_normalizeDate(expiry)) : null;

      if (normalized.containsKey(key)) {
        normalized[key]!['quantity'] =
            (normalized[key]!['quantity'] as int? ?? 0) + quantity;
      } else {
        final batchCopy = Map<String, dynamic>.from(rawBatch);
        batchCopy['quantity'] = quantity;
        batchCopy['expiryDate'] = normalizedExpiry;
        normalized[key] = batchCopy;
      }
    }
    return normalized.values.toList();
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

      final Timestamp normalizedExpiry =
          Timestamp.fromDate(_normalizeDate(_selectedExpiryDate));
      final String newBatchKey = _dateKey(_selectedExpiryDate);

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final docId = doc.id;
        final currentTotal = doc.data()['totalQuantity'] as int? ?? 0;
        final currentBatches = List<dynamic>.from(doc.data()['batches'] ?? []);
        final consolidatedBatches = _consolidateBatches(currentBatches);

        var matched = false;
        for (final batch in consolidatedBatches) {
          final expiryValue = batch['expiryDate'];
          DateTime? expiry;
          if (expiryValue is Timestamp) {
            expiry = expiryValue.toDate();
          } else if (expiryValue is DateTime) {
            expiry = expiryValue;
          }
          if (_dateKey(expiry != null ? _normalizeDate(expiry) : null) ==
              newBatchKey) {
            batch['quantity'] = (batch['quantity'] as int? ?? 0) + _quantity;
            matched = true;
            break;
          }
        }

        if (!matched) {
          consolidatedBatches.add({
            'quantity': _quantity,
            'expiryDate': normalizedExpiry,
            'addedAt': Timestamp.now(),
            'source': 'manual',
          });
        }

        await inventoryRef.doc(docId).update({
          'totalQuantity': currentTotal + _quantity,
          'batches': consolidatedBatches,
          'isConsumed': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        await inventoryRef.add({
          'name': productName,
          'totalQuantity': _quantity,
          'isConsumed': false,
          'batches': [
            {
              'quantity': _quantity,
              'expiryDate': normalizedExpiry,
              'addedAt': Timestamp.now(),
              'source': 'manual',
            }
          ],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$productName added! 🥫')));
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
      ),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20,
          right: 20,
          top: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add Product',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                  labelText: 'Product Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.fastfood)),
              autofocus: true,
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Expires on:', style: TextStyle(fontSize: 16)),
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
                const Text('Quantity:', style: TextStyle(fontSize: 16)),
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
                    : const Text('Save to Pantry',
                        style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
