import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/constants.dart';
import '../utils/dni_code_parser.dart';
import '../widgets/section_app_bar.dart';

class DniScannerScreen extends StatefulWidget {
  const DniScannerScreen({super.key});

  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DniScannerScreen()),
    );
  }

  @override
  State<DniScannerScreen> createState() => _DniScannerScreenState();
}

class _DniScannerScreenState extends State<DniScannerScreen> {
  static const List<BarcodeFormat> _formatos = [
    BarcodeFormat.code128,
    BarcodeFormat.code39,
    BarcodeFormat.code93,
    BarcodeFormat.pdf417,
    BarcodeFormat.qrCode,
    BarcodeFormat.dataMatrix,
    BarcodeFormat.ean13,
    BarcodeFormat.itf14,
    BarcodeFormat.codabar,
  ];

  late final MobileScannerController _controller;
  bool _procesando = false;
  String? _aviso;
  Timer? _limpiarAviso;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: _formatos,
      detectionSpeed: DetectionSpeed.normal,
      autoStart: true,
    );
  }

  @override
  void dispose() {
    _limpiarAviso?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _avisar(String mensaje) {
    _limpiarAviso?.cancel();
    _limpiarAviso = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _aviso = null);
    });
    setState(() => _aviso = mensaje);
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_procesando) return;
    for (final code in capture.barcodes) {
      final dni = DniCodeParser.parse(code.rawValue);
      if (dni == null) continue;
      _procesando = true;
      await _controller.stop();
      if (!mounted) return;
      Navigator.of(context).pop(dni);
      return;
    }
    final leido = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (leido.isEmpty || !mounted) return;
    _avisar('DNI no válido');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: SectionAppBar(
        title: 'Escanear DNI',
        sectionIcon: Icons.qr_code_scanner_rounded,
        showDrawerButton: false,
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              final permiso =
                  error.errorCode == MobileScannerErrorCode.permissionDenied;
              return Center(
                child: Text(
                  permiso ? 'Sin permiso de cámara' : 'No se pudo abrir la cámara',
                  style: const TextStyle(color: Colors.white),
                ),
              );
            },
          ),
          Column(
            children: [
              const SizedBox(height: 28),
              const Text(
                'Apunte al código de barras del DNI',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: Container(
                  width: MediaQuery.sizeOf(context).width * 0.86,
                  height: 110,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _aviso == null
                          ? AppColors.primaryLight
                          : AppColors.warning,
                      width: 3,
                    ),
                  ),
                ),
              ),
              if (_aviso != null) ...[
                const SizedBox(height: 16),
                Text(
                  _aviso!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
