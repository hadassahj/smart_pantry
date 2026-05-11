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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF26A69A),
          background: const Color(0xFFF5F7F6),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        appBarTheme: AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.black87,
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shadowColor: Colors.black.withOpacity(0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              vertical: 16,
              horizontal: 32,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.all(20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
        ),
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
