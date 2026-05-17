import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _isScanned =
      false; // Flag pentru a preveni scanarea multiplă (să nu deschidă 10 ecrane pe secundă)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scanează codul'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      // MobileScanner se ocupă automat de cerut permisiuni și de afișat camera
      body: MobileScanner(
        onDetect: (capture) {
          if (_isScanned)
            return; // Dacă am prins deja unul, ignorăm restul cadrelor

          final List<Barcode> barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            setState(() => _isScanned = true);

            final String code = barcodes.first.rawValue!;
            debugPrint('ScannerScreen onDetect payload: $code');

            // Închidem ecranul de scanare și "trimitem" codul înapoi de unde am venit
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}
