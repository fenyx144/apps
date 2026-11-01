import 'package:flutter/material.dart';

import '../screens/dni_scanner_screen.dart';
import '../screens/mrz_scanner_screen.dart';

/// Elige escáner de código DNI o MRZ de carné de extranjería.
Future<String?> escanearDocumentoPersona(BuildContext context) async {
  final modo = await showModalBottomSheet<_ModoDoc>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_scanner_rounded),
            title: const Text('DNI'),
            onTap: () => Navigator.pop(ctx, _ModoDoc.dni),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Carné de extranjería'),
            onTap: () => Navigator.pop(ctx, _ModoDoc.mrz),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (!context.mounted || modo == null) return null;
  switch (modo) {
    case _ModoDoc.dni:
      return DniScannerScreen.open(context);
    case _ModoDoc.mrz:
      return MrzScannerScreen.open(context);
  }
}

enum _ModoDoc { dni, mrz }
