import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'database_provider.dart';
import 'home_screen.dart'; // <--- Noul import

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: SmartPantryApp()));
}

class SmartPantryApp extends ConsumerWidget {
  const SmartPantryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final householdState = ref.watch(householdProvider);

    return MaterialApp(
      title: 'Smart Pantry',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: householdState.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (err, stack) => Scaffold(
          body: Center(child: Text('Eroare: $err')),
        ),
        data: (householdId) {
          if (householdId == null) {
            return const Scaffold(
              body: Center(child: Text('Eroare la crearea contului.')),
            );
          }
          // Aici trimitem utilizatorul către noul ecran cu meniu
          return HomeScreen(householdId: householdId);
        },
      ),
    );
  }
}
