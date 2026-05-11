import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_tab.dart';
import 'ai_assistant_tab.dart';
import 'household_tab.dart';
import 'pantry_tab.dart'; // Importăm noul tab

class HomeScreen extends StatefulWidget {
  final String householdId;
  const HomeScreen({super.key, required this.householdId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  late String _householdId;

  @override
  void initState() {
    super.initState();
    _householdId = widget.householdId;
  }

  Future<void> _updateHouseholdId(String newHouseholdId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pantry_household_id', newHouseholdId);

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final db = FirebaseFirestore.instance;
      await db
          .collection('users')
          .doc(currentUser.uid)
          .set({'householdId': newHouseholdId}, SetOptions(merge: true));
      await db.collection('households').doc(newHouseholdId).set({
        'members': FieldValue.arrayUnion([currentUser.uid])
      }, SetOptions(merge: true));
    }

    setState(() {
      _householdId = newHouseholdId;
      _currentIndex = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      PantryTab(householdId: _householdId), // 0: Cămară
      HouseholdTab(
        householdId: _householdId,
        onHouseholdChanged: _updateHouseholdId,
        onGoToAccount: () {
          setState(() {
            _currentIndex = 3;
          });
        },
      ),
      AiAssistantTab(householdId: _householdId),
      AccountTab(householdId: _householdId),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Pantry',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Cămară',
          ),
          NavigationDestination(
            icon: Icon(Icons.family_restroom_outlined),
            selectedIcon: Icon(Icons.family_restroom),
            label: 'Gospodărie',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Cont',
          ),
        ],
      ),
    );
  }
}
