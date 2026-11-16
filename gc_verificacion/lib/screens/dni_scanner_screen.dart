import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/constants.dart';
import '../utils/dni_code_parser.dart';
import '../utils/theme_colors.dart';
import '../widgets/screen_status_bar.dart';
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
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
    formats: const [
      BarcodeFormat.qrCode,
      BarcodeFormat.pdf417,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
  );
  bool _torchOn = false;
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final dni = DniCodeParser.parse(b.rawValue);
      if (dni == null) continue;
      _done = true;
      Navigator.of(context).pop(dni);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenStatusBar(
      color: context.scaffoldMuted,
      child: Scaffold(
        appBar: SectionAppBar(
          title: 'Escanear DNI',
          sectionIcon: Icons.qr_code_scanner_rounded,
          showDrawerButton: false,
          actions: [
            IconButton(
              icon: Icon(
                _torchOn ? Icons.flash_on : Icons.flash_off,
                color: Colors.white,
              ),
              onPressed: () async {
                setState(() => _torchOn = !_torchOn);
                await _controller.toggleTorch();
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.cameraswitch_rounded,
                color: Colors.white,
              ),
              onPressed: () async {
                await _controller.switchCamera();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 280,
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 3),
                  borderRadius:
                      BorderRadius.circular(AppColors.radiusLg),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 48,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Apunte al código',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
