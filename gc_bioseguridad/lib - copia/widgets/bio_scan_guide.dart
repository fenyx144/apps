import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Marco de guía sobre la cámara, con la instrucción y los avisos.
///
/// Se dibuja un único recuadro, con la forma del código de barras del DNI: un
/// rectángulo ancho y bajo. Antes se dibujaban dos (la franja y el cuadrado del
/// QR) superpuestos, y al apuntar se veían como dos marcos que competían entre
/// sí. El escáner sigue leyendo todos los formatos que puede traer el DNI
/// (código de barras, PDF417 o QR); lo que cambia es que el operador ve una
/// sola guía.
class BioScanGuide extends StatelessWidget {
  const BioScanGuide({super.key, this.aviso});

  /// Clave con la que las pruebas localizan el recuadro dibujado.
  static const Key claveFranja = Key('bio-scan-guia-franja');

  /// Instrucción que acompaña al recuadro.
  static const String instruccion = 'Apunte al código de barras del DNI';

  final String? aviso;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = constraints.maxWidth;
        // Un código de barras es ancho y bajo (~3:1).
        final anchoFranja = ancho * 0.90;
        final color =
            aviso == null ? AppColors.primaryLight : AppColors.warning;

        return Column(
          children: [
            const SizedBox(height: 24),
            const Text(
              instruccion,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: SizedBox(
                width: anchoFranja,
                // Se reserva la misma altura que ocupaba la guía anterior para
                // que el recuadro quede en la misma zona de la pantalla.
                height: ancho * 0.78,
                child: Center(
                  child: Container(
                    key: claveFranja,
                    width: anchoFranja,
                    height: anchoFranja * 0.34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: color, width: 3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (aviso != null)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  aviso!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            
          ],
        );
      },
    );
  }
}
