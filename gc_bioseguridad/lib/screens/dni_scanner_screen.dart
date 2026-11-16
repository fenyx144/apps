import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/plan_visitas_service.dart';
import '../utils/bio_scan_result.dart';
import '../utils/constants.dart';
import '../utils/dni_utils.dart';
import '../widgets/bio_scan_guide.dart';
import '../widgets/section_app_bar.dart';

/// Pantalla del escáner de **códigos del DNI** (barras / QR / PDF417).
/// La placa del vehículo no lleva código de barras: se ingresa con
/// [PlacaInputDialog]. Este escáner solo aplica al documento de identidad.
class DniScannerScreen extends StatefulWidget {
  const DniScannerScreen({super.key, this.modo = BioScanModo.dni});

  final BioScanModo modo;

  /// Abre el escáner y devuelve el DNI leído, o `null` si se canceló.
  static Future<String?> open(BuildContext context) {
    return openResult(context, modo: BioScanModo.dni).then((r) => r?.dni);
  }

  /// Abre el escáner según [modo] y devuelve DNI y/o placa.
  static Future<BioScanResult?> openResult(
    BuildContext context, {
    BioScanModo modo = BioScanModo.auto,
  }) {
    return Navigator.of(context).push<BioScanResult>(
      MaterialPageRoute(
        builder: (_) => DniScannerScreen(modo: modo),
      ),
    );
  }

  @override
  State<DniScannerScreen> createState() => _DniScannerScreenState();
}

class _DniScannerScreenState extends State<DniScannerScreen> {
  static const int _minPlaca = 5;

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

  String get _titulo => switch (widget.modo) {
        BioScanModo.placa => 'Escanear placa',
        BioScanModo.auto => 'Escanear código',
        BioScanModo.dni => 'DNI',
      };

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
    _limpiarAviso = Timer(_vigenciaAviso, () {
      if (mounted) setState(() => _aviso = null);
    });
    setState(() => _aviso = mensaje);
  }

  BioScanResult? _parseRaw(String? raw) {
    final leido = raw?.trim() ?? '';
    if (leido.isEmpty) return null;

    final dni = DniCodeParser.parse(leido);
    final placaNorm = PlanDescarga.normPlaca(leido);

    switch (widget.modo) {
      case BioScanModo.dni:
        if (dni == null) return null;
        return BioScanResult.dni(dni);
      case BioScanModo.placa:
        if (placaNorm.length < _minPlaca) return null;
        return BioScanResult.placa(placaNorm);
      case BioScanModo.auto:
        if (dni != null) return BioScanResult.dni(dni);
        if (placaNorm.length >= _minPlaca) {
          return BioScanResult.placa(placaNorm);
        }
        return null;
    }
  }

  String get _avisoInvalido => switch (widget.modo) {
        BioScanModo.placa =>
          'Código leído sin placa válida (mín. $_minPlaca caracteres).',
        BioScanModo.auto =>
          'Código leído sin DNI ni placa reconocibles. Intente de nuevo.',
        BioScanModo.dni => 'Código leído sin DNI válido. Intente de nuevo.',
      };

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_procesando) return;
    for (final code in capture.barcodes) {
      final parsed = _parseRaw(code.rawValue);
      if (parsed == null) continue;
      _procesando = true;
      await _controller.stop();
      if (!mounted) return;
      Navigator.of(context).pop(parsed);
      return;
    }

    final leido = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (leido.isEmpty || !mounted) return;
    _avisar(_avisoInvalido);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: SectionAppBar(
        title: _titulo,
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
