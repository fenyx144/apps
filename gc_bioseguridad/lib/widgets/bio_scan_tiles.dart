import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Dos acciones grandes de escaneo (DNI y placa), pensadas para ir primero en el flujo.
/// Si se pasan [onManualDni] / [onManualPlaca], el ingreso manual va debajo de cada tile.
class BioScanTiles extends StatelessWidget {
  const BioScanTiles({
    super.key,
    required this.onScanDni,
    required this.onScanPlaca,
    this.onManualDni,
    this.onManualPlaca,
  });

  final VoidCallback onScanDni;
  final VoidCallback onScanPlaca;
  final VoidCallback? onManualDni;
  final VoidCallback? onManualPlaca;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Columna(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Escanear Documento',
            onTap: onScanDni,
            manualLabel: 'Ingreso manual documento',
            onManual: onManualDni,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _Columna(
            icon: Icons.directions_car_rounded,
            title: 'Escanear Placa',
            onTap: onScanPlaca,
            manualLabel: 'Ingreso manual placa',
            onManual: onManualPlaca,
          ),
        ),
      ],
    );
  }
}

class _Columna extends StatelessWidget {
  const _Columna({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.manualLabel,
    this.onManual,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String manualLabel;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tile(icon: icon, title: title, onTap: onTap),
        if (onManual != null) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.keyboard_rounded, size: 18),
            label: Text(
              manualLabel,
              textAlign: TextAlign.center,
              maxLines: 2,
              softWrap: true,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryDark,
              minimumSize: const Size.fromHeight(46),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.15,
              ),
              side: BorderSide(color: context.borderSubtle, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: Material(
        color: context.surfaceCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: context.borderSubtle, width: 1.2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 32, color: AppColors.primaryDark),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: context.textThemePrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
