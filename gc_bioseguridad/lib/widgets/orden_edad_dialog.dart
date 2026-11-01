import 'package:flutter/material.dart';

import '../services/estatus_sanitario_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

Color colorOrdenEdad() => AppColors.primaryDark;

Future<void> showOrdenEdadDialog({
  required BuildContext context,
  required OrdenEdadDni aviso,
  required String sujeto,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => OrdenEdadDialog(aviso: aviso, sujeto: sujeto),
  );
}

class OrdenEdadDialog extends StatelessWidget {
  const OrdenEdadDialog({
    super.key,
    required this.aviso,
    required this.sujeto,
  });

  final OrdenEdadDni aviso;
  final String sujeto;

  @override
  Widget build(BuildContext context) {
    final color = colorOrdenEdad();
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          Icon(Icons.swap_vert_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Visita por edad',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.textThemePrimary,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                aviso.avisoIngreso(sujeto),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (aviso.origenes.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final o in aviso.origenes) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      border: Border.all(color: color.withValues(alpha: 0.45)),
                      borderRadius: BorderRadius.circular(AppColors.radiusMd),
                    ),
                    child: Text(
                      aviso.detalleOrigen(sujeto, o),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: context.textThemePrimary,
                      ),
                    ),
                  ),
                  if (o != aviso.origenes.last) const SizedBox(height: 8),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    );
  }
}
