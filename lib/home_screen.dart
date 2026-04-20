import 'package:flutter/material.dart';
import 'pantry_tab.dart'; // Importăm noul tab

class HomeScreen extends StatefulWidget {
  final String householdId;
  const HomeScreen({super.key, required this.householdId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Lista de ecrane (câte unul pentru fiecare iconiță din meniul de jos)
    final List<Widget> screens = [
      PantryTab(householdId: widget.householdId), // 0: Cămara
      const Center(
          child: Text('Asistentul AI va fi aici 🤖',
              style: TextStyle(fontSize: 20))), // 1: AI Chat
      const Center(
          child: Text('Setările contului vor fi aici ⚙️',
              style: TextStyle(fontSize: 20))), // 2: Setări
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Pantry',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      // Aici e magia: afișăm doar ecranul corespunzător indexului selectat
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
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'AI Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Setări',
          ),
        ],
      ),
    );
  }
}
