import 'package:flutter/material.dart';

import '../services/plan_visitas_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import 'granja_campania_picker.dart';

/// Hoja para elegir una visita planificada (acceso rápido, igual criterio que reportes web).
Future<PlanVisita?> showPlanificadasSheet({
  required BuildContext context,
  required List<PlanVisita> visitas,
  required String fecha,
  String titulo = 'Planificadas de hoy',
}) {
  return showModalBottomSheet<PlanVisita>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) => Material(
        color: context.dialogSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              decoration: BoxDecoration(
                color: context.textThemeMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textThemePrimary,
                          ),
                        ),
                        Text(
                          '$fecha · ${visitas.length} '
                          '${visitas.length == 1 ? 'visita' : 'visitas'}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            color: context.textThemeMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                itemCount: visitas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _PlanificadaTile(
                  visita: visitas[i],
                  onTap: () => Navigator.pop(context, visitas[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlanificadaTile extends StatelessWidget {
  const _PlanificadaTile({required this.visita, required this.onTap});

  final PlanVisita visita;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final granja = [visita.granja, visita.nombreGranja]
        .where((e) => e.trim().isNotEmpty)
        .join(' ');
    final campania = visita.campania.trim().isEmpty
        ? '—'
        : GranjaCampaniaPicker.padCampania(visita.campania);
    final proveedor = visita.razonSocial.trim().isNotEmpty
        ? visita.razonSocial.trim()
        : visita.areaProveedorEtiqueta;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: context.surfaceCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              proveedor.isEmpty ? 'Visita #${visita.id}' : proveedor,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: context.textThemePrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Placa: ${visita.placasTexto.isEmpty ? '—' : visita.placasTexto.toUpperCase()} · '
              'Granja: ${granja.isEmpty ? '—' : granja} · Camp: $campania',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textThemeMuted,
              ),
            ),
            if (visita.proceso.trim().isNotEmpty ||
                visita.areaProveedorValor.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                visita.proceso.trim().isNotEmpty
                    ? visita.proceso.trim()
                    : visita.areaProveedorValor.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: context.textThemeSecondary,
                ),
              ),
            ],
            if (visita.galpones.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Galpones: ${visita.galpones.join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textThemeSecondary,
                ),
              ),
            ],
            if (visita.observacion.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                visita.observacion.trim(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textThemeSecondary,
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              '${visita.personas.length} DNI(s) · Tocar para seleccionar',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
