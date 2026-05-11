import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'firebase_options.dart';
import 'database_provider.dart';
import 'home_screen.dart';

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

    // === PALETA PRINCIPALA ===
    const primaryOrange = Color(0xFFF97316);
    const warmBackground = Color(0xFFFFF4E6);
    const softCream = Color(0xFFFFFBF7);
    const darkText = Color(0xFF3D2C1E);
    const mutedText = Color(0xFF8B7355);
    const softGreen = Color(0xFFA3B18A);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,

        // BACKGROUND GENERAL
        scaffoldBackgroundColor: const Color(0xFFFFD54F),

        // TYPOGRAPHY
        textTheme: GoogleFonts.poppinsTextTheme().copyWith(
          headlineLarge: GoogleFonts.poppins(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A1A),
          ),
          headlineMedium: GoogleFonts.poppins(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A1A),
          ),
          bodyLarge: GoogleFonts.poppins(
            color: const Color(0xFF2B2B2B),
            fontWeight: FontWeight.w500,
          ),
          bodyMedium: GoogleFonts.poppins(
            color: const Color(0xFF4A4A4A),
          ),
        ),

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF6B00),
          primary: const Color(0xFFFF6B00),
          secondary: const Color(0xFFFFB703),
          surface: Colors.white,
          brightness: Brightness.light,
        ),

        // APP BAR
        appBarTheme: AppBarTheme(
          backgroundColor: const Color(0xFFFFD54F),
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.poppins(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A1A),
          ),
          iconTheme: const IconThemeData(
            color: Color(0xFF1A1A1A),
            size: 28,
          ),
        ),

        // CARDURI
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.symmetric(
            vertical: 10,
            horizontal: 4,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),

        // BUTOANE
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6B00),
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 18,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            textStyle: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),

        // INPUTS
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 18,
          ),
          hintStyle: GoogleFonts.poppins(
            color: Colors.grey.shade500,
            fontWeight: FontWeight.w500,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide.none,
          ),
        ),

        // FLOATING BUTTON
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFF6B00),
          foregroundColor: Colors.white,
          elevation: 0,
        ),

        // ICONS
        iconTheme: const IconThemeData(
          color: Color(0xFF1A1A1A),
          size: 24,
        ),

        // LIST TILES
        listTileTheme: ListTileThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 8,
          ),
        ),
      ),
      home: householdState.when(
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
        error: (err, stack) => Scaffold(
          body: Center(
            child: Text(
              'Eroare: $err',
            ),
          ),
        ),
        data: (householdId) {
          if (householdId == null) {
            return const Scaffold(
              body: Center(
                child: Text(
                  'Eroare la crearea contului.',
                ),
              ),
            );
          }

          return HomeScreen(
            householdId: householdId,
          );
        },
      ),
    );
  }
}
