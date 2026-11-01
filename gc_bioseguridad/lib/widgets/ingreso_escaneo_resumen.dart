import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Lista compacta de DNIs y placas ya leídos (fase «Identificar»).
class IngresoEscaneoResumen extends StatelessWidget {
  const IngresoEscaneoResumen({
    super.key,
    required this.dnis,
    required this.placas,
    this.onQuitarDni,
    this.onQuitarPlaca,
  });

  final List<({String dni, String nombre})> dnis;
  final List<String> placas;
  final ValueChanged<String>? onQuitarDni;
  final ValueChanged<String>? onQuitarPlaca;

  @override
  Widget build(BuildContext context) {
    if (dnis.isEmpty && placas.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in dnis)
          _Chip(
            icon: Icons.badge_outlined,
            label: p.nombre.trim().isNotEmpty
                ? '${p.dni} · ${p.nombre.trim()}'
                : p.dni,
            onDelete: onQuitarDni == null ? null : () => onQuitarDni!(p.dni),
          ),
        for (final placa in placas)
          _Chip(
            icon: Icons.directions_car_outlined,
            label: placa,
            onDelete:
                onQuitarPlaca == null ? null : () => onQuitarPlaca!(placa),
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.onDelete,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.surfaceCard,
      shape: StadiumBorder(side: BorderSide(color: context.borderSubtle)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.primaryDark),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.textThemePrimary,
                ),
              ),
            ),
            if (onDelete != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: AppColors.errorDark,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
