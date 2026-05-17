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
      extendBody: true,
      // 1. Păstrăm fundalul galben al aplicației
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),

      // 2. Meniul de jos cu bară flotantă
      bottomNavigationBar: Container(
        child: Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 15,
                  offset: const Offset(0, -5),
                )
              ]),
          child: SafeArea(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              child: NavigationBar(
                height: 70,
                backgroundColor: Colors.white,
                elevation: 0,
                indicatorColor: const Color(0xFFF25C05).withOpacity(0.15),
                selectedIndex: _currentIndex,
                onDestinationSelected: (int index) {
                  setState(() {
                    _currentIndex = index;
                  });
                },
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon:
                        Icon(Icons.inventory_2, color: Color(0xFFF25C05)),
                    label: 'Cămară',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.family_restroom_outlined),
                    selectedIcon:
                        Icon(Icons.family_restroom, color: Color(0xFFF25C05)),
                    label: 'Gospodărie',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.auto_awesome_outlined),
                    selectedIcon:
                        Icon(Icons.auto_awesome, color: Color(0xFFF25C05)),
                    label: 'AI',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person, color: Color(0xFFF25C05)),
                    label: 'Cont',
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
