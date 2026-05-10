import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'scanner_screen.dart';

class HouseholdTab extends StatelessWidget {
  final String householdId;
  final void Function(String) onHouseholdChanged;

  const HouseholdTab({
    super.key,
    required this.householdId,
    required this.onHouseholdChanged,
  });

  bool _isValidHouseholdId(String id) {
    return id.length > 10 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Gospodăria Mea',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Folosește acest cod pentru a conecta un alt dispozitiv la aceeași cămară.',
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 30),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(20),
                          child: QrImageView(
                            data: householdId,
                            version: QrVersions.auto,
                            size: 260,
                            backgroundColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'Cere unui membru să scaneze acest cod pentru a se alătura cămării tale.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, color: Colors.black54),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'ID gospodărie: $householdId',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scanează codul altei gospodării'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: () async {
                        final String? scannedId = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ScannerScreen(),
                          ),
                        );

                        if (scannedId == null) return;

                        if (!_isValidHouseholdId(scannedId)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Cod invalid. Te rog scanează un QR de gospodărie valid.'),
                            ),
                          );
                          return;
                        }

                        final currentInventory = await FirebaseFirestore
                            .instance
                            .collection('households')
                            .doc(householdId)
                            .collection('inventory')
                            .get();
                        final int itemCount = currentInventory.docs.length;

                        final bool? confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) {
                            if (itemCount > 0) {
                              return AlertDialog(
                                title: const Text('Atenție la datele tale!'),
                                content: Text(
                                  'Cămara ta curentă conține $itemCount produse. Dacă te alături noii gospodării, vei pierde accesul la produsele tale.\n\nSfat inteligent: Pentru a păstra aceste produse, apasă Anulare și cere celuilalt membru să scaneze codul tău QR.',
                                ),
                                actions: [
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.teal,
                                    ),
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Anulează (Recomandat)'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Mă alătur oricum'),
                                  ),
                                ],
                              );
                            }

                            return AlertDialog(
                              title: const Text('Alăturare gospodărie'),
                              content: const Text(
                                'Dorești să te alături acestei cămări?',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(false),
                                  child: const Text('Anulează'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(true),
                                  child: const Text('Confirmă'),
                                ),
                              ],
                            );
                          },
                        );

                        if (confirmed == true) {
                          onHouseholdChanged(scannedId);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
