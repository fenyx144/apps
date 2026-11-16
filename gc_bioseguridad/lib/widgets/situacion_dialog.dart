import 'package:flutter/material.dart';

import '../services/estatus_sanitario_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Color del aviso de situación especial: rojo si alguno de los orígenes está
/// confirmado, ámbar si solo hay sospecha.
Color colorSituacion(EstatusDni e) =>
    e.origenes.any((o) => o.estado == 'CONFIRMADO')
    ? AppColors.errorDark
    : AppColors.warning;

/// Detalle de la situación especial de un DNI, en diálogo.
/// Al tocar el icono o el mensaje de coronavirus se abre esto en vez de un
/// aviso pasajero: se lee de qué granja viene la persona, cuándo ingresó y en
/// qué estado está. Solo informa; el ingreso se registra igual.
Future<void> showSituacionDialog({
  required BuildContext context,
  required EstatusDni estatus,
  required String sujeto,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => SituacionDialog(estatus: estatus, sujeto: sujeto),
  );
}

class SituacionDialog extends StatelessWidget {
  const SituacionDialog({
    super.key,
    required this.estatus,
    required this.sujeto,
  });

  final EstatusDni estatus;

  /// Cómo se nombra a la persona: su nombre si se conoce, si no el DNI.
  final String sujeto;

  @override
  Widget build(BuildContext context) {
    final color = colorSituacion(estatus);
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      title: Row(
        children: [
          Icon(Icons.coronavirus_rounded, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Situación especial',
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
                estatus.avisoIngreso(sujeto),
                style: TextStyle(
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 12),
              if (estatus.origenes.isEmpty)
                Text(
                  '$sujeto viene de una granja en situación especial.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: context.textThemeSecondary,
                  ),
                )
              else
                for (final o in estatus.origenes) ...[
                  _origen(context, o, color),
                  if (o != estatus.origenes.last) const SizedBox(height: 8),
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

  /// Una granja de la que viene la persona, con la frase completa y el estado
  /// resaltado en su color.
  Widget _origen(BuildContext context, EstatusOrigen o, Color color) {
    final trozos = estatus.situacionTrozos(sujeto, o);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            fontSize: 13.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: context.textThemePrimary,
          ),
          children: [
            TextSpan(text: trozos[0]),
            TextSpan(
              text: trozos[1],
              style: TextStyle(fontWeight: FontWeight.w800, color: color),
            ),
            TextSpan(text: trozos[2]),
          ],
        ),
      ),
    );
  }
}
