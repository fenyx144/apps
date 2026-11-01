import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/constants.dart';
import '../utils/dni_utils.dart';
import '../widgets/bio_scan_guide.dart';
import '../widgets/section_app_bar.dart';

/// Pantalla del escáner de DNI.
///
/// Sirve tanto para código de barras como para QR (el DNI peruano usa uno u otro
/// según el modelo), así que se habilitan todos los formatos plausibles, pero la
/// guía sobre la cámara es un solo recuadro con la forma del código de barras
/// (ver `BioScanGuide`). Al leer un código devuelve el DNI por `Navigator.pop`;
/// si el contenido no trae un número de 8 dígitos avisa y sigue escaneando.
class DniScannerScreen extends StatefulWidget {
  const DniScannerScreen({super.key});

  /// Abre el escáner y devuelve el DNI leído, o `null` si se canceló.
  static Future<String?> open(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DniScannerScreen()),
    );
  }

  @override
  State<DniScannerScreen> createState() => _DniScannerScreenState();
}

class _DniScannerScreenState extends State<DniScannerScreen> {
  // Se habilitan los formatos que pueden traer el DNI: el código de barras de
  // los DNI antiguos (Code 128) y el PDF417/QR de los electrónicos.
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

  /// Cuánto se mantiene el aviso de lectura inválida en pantalla.
  static const Duration _vigenciaAviso = Duration(seconds: 3);

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
      // Sin esto el mismo código se relee en cada frame mientras siga a la vista.
      autoStart: true,
    );
  }

  @override
  void dispose() {
    _limpiarAviso?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Muestra el aviso y programa su retiro para no dejar el texto pegado si el
  /// operador deja de pasar códigos.
  void _avisar(String mensaje) {
    _limpiarAviso?.cancel();
    _limpiarAviso = Timer(_vigenciaAviso, () {
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

    // Se leyó algo, pero no parece un DNI: se avisa y se sigue escaneando.
    final leido = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (leido.isEmpty || !mounted) return;
    _avisar('Código leído sin DNI válido. Intente de nuevo.');
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
            tooltip: 'Linterna',
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flashlight_on_rounded),
            color: Colors.white,
          ),
          IconButton(
            tooltip: 'Cambiar cámara',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_rounded),
            color: Colors.white,
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _ErrorCamara(error: error),
          ),
          BioScanGuide(aviso: _aviso),
        ],
      ),
    );
  }
}

/// Mensaje cuando la cámara no está disponible o falta el permiso.
class _ErrorCamara extends StatelessWidget {
  const _ErrorCamara({required this.error});

  final MobileScannerException error;

  String get _mensaje => switch (error.errorCode) {
        MobileScannerErrorCode.permissionDenied =>
          'Falta el permiso de cámara. Actívelo en los ajustes del teléfono '
              'para poder escanear el DNI.',
        MobileScannerErrorCode.unsupported =>
          'Este dispositivo no permite escanear códigos.',
        _ => 'No se pudo abrir la cámara. Escriba el DNI a mano.',
      };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_rounded,
              color: AppColors.warning,
              size: 46,
            ),
            const SizedBox(height: 14),
            Text(
              _mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
