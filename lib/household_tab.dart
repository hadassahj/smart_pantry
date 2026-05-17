import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'scanner_screen.dart';

class HouseholdTab extends StatefulWidget {
  final String householdId;
  final void Function(String) onHouseholdChanged;
  final VoidCallback? onGoToAccount;

  const HouseholdTab({
    super.key,
    required this.householdId,
    required this.onHouseholdChanged,
    this.onGoToAccount,
  });

  @override
  State<HouseholdTab> createState() => _HouseholdTabState();
}

class _HouseholdTabState extends State<HouseholdTab> {
  final TextEditingController _householdNameController =
      TextEditingController();
  final FocusNode _householdNameFocusNode = FocusNode();
  bool _isSavingName = false;
  bool _ownerRepairAttempted = false;
  final Map<String, int> _suggestedQuantities = {};

  @override
  void dispose() {
    _householdNameController.dispose();
    _householdNameFocusNode.dispose();
    super.dispose();
  }

  bool _isValidHouseholdId(String id) {
    return id.length > 10 && RegExp(r'^[a-zA-Z0-9]+$').hasMatch(id);
  }

  Future<List<Map<String, String>>> _loadMemberNames(
      List<dynamic> memberIds) async {
    final ids = memberIds.whereType<String>().toList();
    if (ids.isEmpty) return [];

    final db = FirebaseFirestore.instance;
    final members = await Future.wait(ids.map((uid) async {
      final userDoc = await db.collection('users').doc(uid).get();
      return {
        'uid': uid,
        'displayName': userDoc.data()?['displayName'] as String? ??
            'Utilizator necunoscut',
      };
    }));
    return members;
  }

  Future<void> _kickMember(String memberUid) async {
    try {
      final db = FirebaseFirestore.instance;
      await db.collection('households').doc(widget.householdId).update({
        'members': FieldValue.arrayRemove([memberUid]),
      });

      await db.collection('users').doc(memberUid).set(
        {'householdId': ''},
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Membru eliminat din gospodărie.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare la eliminarea membrului: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<String> _getUserDisplayName(String? uid) async {
    if (uid == null || uid.isEmpty) {
      return 'Utilizator necunoscut';
    }
    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return userDoc.data()?['displayName'] as String? ?? 'Utilizator necunoscut';
  }

  Future<void> _repairMissingOwnerId(String currentUid) async {
    if (_ownerRepairAttempted) return;
    _ownerRepairAttempted = true;

    try {
      final houseDoc = await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .get();
      final houseData = houseDoc.data() as Map<String, dynamic>? ?? {};
      final ownerId = houseData['ownerId'] as String?;
      final members = List<dynamic>.from(houseData['members'] ?? []);

      if ((ownerId == null || ownerId.isEmpty) &&
          members.contains(currentUid)) {
        await FirebaseFirestore.instance
            .collection('households')
            .doc(widget.householdId)
            .update({'ownerId': currentUid});
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Nu s-a putut repara ownerId: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _leaveHousehold() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nu există utilizator conectat.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Părăsește gospodăria'),
          content:
              const Text('Ești sigur că vrei să părăsești această gospodărie?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Anulează'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Părăsește'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final houseDoc =
          await db.collection('households').doc(widget.householdId).get();
      final houseData = houseDoc.data() as Map<String, dynamic>? ?? {};
      final members = List<String>.from(houseData['members'] ?? []);
      final ownerId = houseData['ownerId'] as String? ?? '';

      if (!members.contains(currentUid)) {
        throw 'Utilizatorul nu este membru al acestei gospodării.';
      }

      final Map<String, dynamic> updateData = {
        'members': FieldValue.arrayRemove([currentUid]),
      };

      if (currentUid == ownerId) {
        final nextOwner = members.firstWhere(
          (uid) => uid != currentUid,
          orElse: () => '',
        );
        updateData['ownerId'] = nextOwner;
      }

      await db.collection('households').doc(widget.householdId).update(
            updateData,
          );

      final newHouseholdRef = db.collection('households').doc();
      await newHouseholdRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'members': [currentUid],
        'ownerId': currentUid,
      });
      await db.collection('users').doc(currentUid).set(
        {'householdId': newHouseholdRef.id},
        SetOptions(merge: true),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ai părăsit gospodăria.'),
          ),
        );
        widget.onHouseholdChanged(newHouseholdRef.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Eroare la părăsirea gospodăriei: $error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Widget _buildAddedByLine(String? uid) {
    if (uid == null || uid.isEmpty) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<String>(
      future: _getUserDisplayName(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        return Text(
          'Adăugat de: ${snapshot.data}',
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        );
      },
    );
  }

  Future<void> _saveHouseholdName(String name) async {
    if (name.trim().isEmpty) return;
    setState(() {
      _isSavingName = true;
    });
    try {
      await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .set({'name': name.trim()}, SetOptions(merge: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Numele gospodăriei a fost actualizat.')),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Eroare la actualizarea numelui gospodăriei.')),
      );
    } finally {
      setState(() {
        _isSavingName = false;
      });
    }
  }

  Future<void> _showInviteSheet() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (sheetContext) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
            left: 20,
            right: 20,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  data: widget.householdId,
                  version: QrVersions.auto,
                  size: 260,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Trimite acest cod către membri pentru a-i invita în gospodăria ta.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.black54),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scanează un cod'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () => _scanHousehold(sheetContext),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _scanHousehold(BuildContext context) async {
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
          content:
              Text('Cod invalid. Te rog scanează un QR de gospodărie valid.'),
        ),
      );
      return;
    }

    if (scannedId == widget.householdId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ești deja în această gospodărie!')),
      );
      return;
    }

    final currentInventory = await FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
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
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Anulează (Recomandat)'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Mă alătur oricum'),
              ),
            ],
          );
        }

        return AlertDialog(
          title: const Text('Alăturare gospodărie'),
          content: const Text('Dorești să te alături acestei cămări?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Anulează'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirmă'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      widget.onHouseholdChanged(scannedId);
      Navigator.of(context).pop();
    }
  }

  Future<void> _showAddShoppingItemDialog() async {
    final nameController = TextEditingController();
    final quantityController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Adaugă item în lista de cumpărături'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nume Produs'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantitate'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Anulează'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                final quantity =
                    int.tryParse(quantityController.text.trim()) ?? 1;
                if (name.isEmpty) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                        content: Text('Te rog introdu numele produsului.')),
                  );
                  return;
                }
                final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                await FirebaseFirestore.instance
                    .collection('households')
                    .doc(widget.householdId)
                    .collection('shopping_list')
                    .add({
                  'name': name,
                  'quantity': quantity,
                  'estimatedPrice': 0.0,
                  'isBought': false,
                  'addedBy': currentUid,
                  'createdAt': FieldValue.serverTimestamp(),
                });
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Adaugă'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleItemBought(String docId, bool isBought) async {
    await FirebaseFirestore.instance
        .collection('households')
        .doc(widget.householdId)
        .collection('shopping_list')
        .doc(docId)
        .update({'isBought': isBought});
  }

  Future<void> _deleteShoppingItem(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('shopping_list')
          .doc(docId)
          .delete();
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eroare la ștergerea itemului.')),
      );
    }
  }

  Future<void> _promoteSuggestedItem(String docId, int quantity) async {
    try {
      await FirebaseFirestore.instance
          .collection('households')
          .doc(widget.householdId)
          .collection('shopping_list')
          .doc(docId)
          .update({'isSuggested': false, 'quantity': quantity});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sugestia a fost promovată în listă.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eroare la promovarea sugestiei.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: Colors.black87,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                backgroundColor: Colors.white.withOpacity(0.85),
              ),
              icon: const Icon(Icons.qr_code),
              label: const Text('Invită / Alătură-te'),
              onPressed: _showInviteSheet,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('households')
              .doc(widget.householdId)
              .snapshots(),
          builder: (context, houseSnapshot) {
            if (houseSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final houseData =
                houseSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final members = List<dynamic>.from(houseData['members'] ?? []);
            final householdName = houseData['name'] as String? ?? '';
            final String currentUid =
                FirebaseAuth.instance.currentUser?.uid ?? '';
            final String ownerId = houseData['ownerId'] as String? ?? '';
            final bool isOwner = currentUid == ownerId;

            if (ownerId.isEmpty &&
                currentUid.isNotEmpty &&
                members.contains(currentUid)) {
              _repairMissingOwnerId(currentUid);
            }

            if (!_householdNameFocusNode.hasFocus &&
                _householdNameController.text != householdName) {
              _householdNameController.text = householdName;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _householdNameController,
                    focusNode: _householdNameFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Nume gospodărie',
                      border: const UnderlineInputBorder(),
                      suffixIcon: _isSavingName
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _saveHouseholdName,
                    onEditingComplete: () =>
                        _saveHouseholdName(_householdNameController.text),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: 3,
                    shadowColor: Colors.black.withOpacity(0.08),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Membri activi în casă',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (ownerId.isEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(
                                'DEBUG: ownerId is missing!',
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          FutureBuilder<List<Map<String, String>>>(
                            future: _loadMemberNames(members),
                            builder: (context, memberSnapshot) {
                              if (memberSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const SizedBox(
                                  height: 40,
                                  child: Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }

                              if (memberSnapshot.hasError) {
                                return Text(
                                  'Eroare la încărcarea membrilor.',
                                  style: TextStyle(
                                    color: Colors.red.shade600,
                                    fontSize: 14,
                                  ),
                                );
                              }

                              final memberData = memberSnapshot.data ?? [];
                              if (memberData.isEmpty) {
                                return const Text(
                                  'Niciun membru activ încă.',
                                  style: TextStyle(
                                      fontSize: 16, color: Colors.black54),
                                );
                              }

                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: memberData.map((member) {
                                  final uid = member['uid'] ?? '';
                                  final displayName = member['displayName'] ??
                                      'Utilizator necunoscut';
                                  final memberIsOwner =
                                      uid.isNotEmpty && uid == ownerId;
                                  final removable = isOwner &&
                                      uid.isNotEmpty &&
                                      uid != ownerId;

                                  return Chip(
                                    label: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(displayName),
                                        if (memberIsOwner) ...[
                                          const SizedBox(width: 6),
                                          const Icon(
                                            Icons.stars,
                                            size: 18,
                                            color: Colors.amber,
                                          ),
                                        ],
                                      ],
                                    ),
                                    backgroundColor: memberIsOwner
                                        ? Colors.amber.shade50
                                        : removable
                                            ? Colors.red.shade50
                                            : Colors.grey.shade100,
                                    deleteIcon: removable
                                        ? const Icon(
                                            Icons.person_remove,
                                            color: Colors.red,
                                          )
                                        : null,
                                    onDeleted: removable
                                        ? () async {
                                            final confirmed =
                                                await showDialog<bool>(
                                              context: context,
                                              builder: (dialogContext) {
                                                return AlertDialog(
                                                  title: const Text(
                                                      'Elimină membru'),
                                                  content: const Text(
                                                      'Ești sigur că vrei să elimini acest membru?'),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                                  dialogContext)
                                                              .pop(false),
                                                      child: const Text(
                                                          'Anulează'),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                                  dialogContext)
                                                              .pop(true),
                                                      child:
                                                          const Text('Elimină'),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                            if (confirmed == true) {
                                              await _kickMember(uid);
                                            }
                                          }
                                        : null,
                                  );
                                }).toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              icon: const Icon(Icons.exit_to_app),
                              label: const Text('Părăsește Gospodăria'),
                              onPressed: _leaveHousehold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Lista de cumpărături partajată',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('households')
                          .doc(widget.householdId)
                          .collection('shopping_list')
                          .orderBy('createdAt', descending: false)
                          .snapshots(),
                      builder: (context, listSnapshot) {
                        if (listSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (listSnapshot.hasError) {
                          return Center(
                              child: Text('Eroare: ${listSnapshot.error}'));
                        }

                        final items = listSnapshot.data?.docs ?? [];
                        final officialItems = <QueryDocumentSnapshot>[];
                        final suggestedItems = <QueryDocumentSnapshot>[];

                        for (final item in items) {
                          final data = item.data() as Map<String, dynamic>;
                          if (data['isSuggested'] == true) {
                            suggestedItems.add(item);
                          } else {
                            officialItems.add(item);
                          }
                        }

                        if (officialItems.isEmpty && suggestedItems.isEmpty) {
                          return Center(
                            child: Text(
                              'Lista de cumpărături este goală. Apasă + pentru a adăuga.',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        return ListView(
                          padding: const EdgeInsets.only(bottom: 16),
                          children: [
                            if (officialItems.isEmpty) ...[
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  'Nicio intrare oficială încă.',
                                  style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 16),
                                ),
                              )
                            ],
                            ...officialItems.map((doc) {
                              final data = doc.data() as Map<String, dynamic>;
                              final name = data['name'] as String? ?? 'Produs';
                              final quantity =
                                  data['quantity']?.toString() ?? '1';
                              final price = (data['estimatedPrice'] != null)
                                  ? (data['estimatedPrice'] as num).toDouble()
                                  : 0.0;
                              final isBought =
                                  data['isBought'] as bool? ?? false;

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 0),
                                child: CheckboxListTile(
                                  value: isBought,
                                  onChanged: (value) {
                                    if (value != null) {
                                      _toggleItemBought(doc.id, value);
                                    }
                                  },
                                  title: Text(name,
                                      style: TextStyle(
                                        decoration: isBought
                                            ? TextDecoration.lineThrough
                                            : null,
                                      )),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'Cantitate: $quantity • Est. Preț: ${price.toStringAsFixed(2)} RON'),
                                      const SizedBox(height: 4),
                                      _buildAddedByLine(
                                          data['addedBy'] as String?),
                                    ],
                                  ),
                                  secondary: IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () =>
                                        _deleteShoppingItem(doc.id),
                                  ),
                                ),
                              );
                            }).toList(),
                            if (suggestedItems.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              const Divider(),
                              const SizedBox(height: 12),
                              Text(
                                'Sugestii din cămară',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...suggestedItems.map((doc) {
                                final data = doc.data() as Map<String, dynamic>;
                                final name =
                                    data['name'] as String? ?? 'Produs';
                                final rawQuantity = data['quantity'];
                                final currentQuantity =
                                    _suggestedQuantities[doc.id] ??
                                        (rawQuantity is int
                                            ? rawQuantity
                                            : int.tryParse(
                                                    rawQuantity?.toString() ??
                                                        '1') ??
                                                1);
                                _suggestedQuantities[doc.id] = currentQuantity;

                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                      vertical: 6, horizontal: 0),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: Colors.teal.shade100,
                                      width: 1,
                                    ),
                                  ),
                                  child: ListTile(
                                    title: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w600),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove,
                                                  color: Colors.redAccent),
                                              onPressed: () {
                                                setState(() {
                                                  final newValue =
                                                      (_suggestedQuantities[
                                                                  doc.id] ??
                                                              1) -
                                                          1;
                                                  _suggestedQuantities[doc.id] =
                                                      newValue < 1
                                                          ? 1
                                                          : newValue;
                                                });
                                              },
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                      vertical: 8),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Text(
                                                '${_suggestedQuantities[doc.id] ?? 1}',
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16),
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add,
                                                  color: Colors.teal),
                                              onPressed: () {
                                                setState(() {
                                                  _suggestedQuantities[doc.id] =
                                                      (_suggestedQuantities[
                                                                  doc.id] ??
                                                              1) +
                                                          1;
                                                });
                                              },
                                            ),
                                            const SizedBox(width: 12),
                                            Flexible(
                                              child: Text(
                                                'Est. Preț: ${data['estimatedPrice'] != null ? (data['estimatedPrice'] as num).toDouble().toStringAsFixed(2) : '0.00'} RON',
                                                style: const TextStyle(
                                                    color: Colors.black54),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        _buildAddedByLine(
                                            data['addedBy'] as String?),
                                      ],
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.add_task,
                                              color: Colors.teal),
                                          onPressed: () {
                                            final promotedQuantity =
                                                _suggestedQuantities[doc.id] ??
                                                    1;
                                            _promoteSuggestedItem(
                                                doc.id, promotedQuantity);
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close,
                                              color: Colors.redAccent),
                                          onPressed: () =>
                                              _deleteShoppingItem(doc.id),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 70.0),
        child: FloatingActionButton(
          onPressed: _showAddShoppingItemDialog,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
