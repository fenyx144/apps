import 'package:flutter/material.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/theme_extensions.dart';

class MortalityDetailsSection extends StatelessWidget {
  final List<MortalityDetail> detalles;
  final MortalityType type;
  final String? agregarError;
  final VoidCallback onAdd;
  final void Function(MortalityDetailGroup group) onEditGroup;
  final void Function(String grupoId) onDeleteGroup;

  const MortalityDetailsSection({
    super.key,
    required this.detalles,
    required this.type,
    required this.onAdd,
    required this.onEditGroup,
    required this.onDeleteGroup,
    this.agregarError,
  });

  bool get _showCausa => mortalityShowsCausaInSummary(type);

  bool get _hasDetalles =>
      MortalityDetail.totalMachos(detalles) + MortalityDetail.totalHembras(detalles) > 0;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final groups = MortalityDetailGroup.fromList(detalles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasDetalles)
          ...groups.asMap().entries.map(
                (e) => Padding(
                  padding: EdgeInsets.only(bottom: e.key < groups.length - 1 ? 6 : 0),
                  child: _DetailGroupRow(
                    index: e.key + 1,
                    group: e.value,
                    showCausa: _showCausa,
                    onEdit: () => onEditGroup(e.value),
                    onDelete: () => onDeleteGroup(e.value.grupoId),
                  ),
                ),
              )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: agregarError != null
                    ? AppColors.error
                    : AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 32,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                Text(
                  'Sin detalles registrados',
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  mortalityShowsCausa(type)
                      ? 'Pulse + para agregar cantidad, causa y fotos'
                      : 'Pulse + para agregar cantidad y fotos',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: Icon(Icons.add_rounded, color: type.accentColor),
            label: Text(
              'Agregar detalle',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: type.accentColor,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: type.accentColor.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        AppFieldError(agregarError),
      ],
    );
  }
}

class _DetailGroupRow extends StatelessWidget {
  final int index;
  final MortalityDetailGroup group;
  final bool showCausa;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _DetailGroupRow({
    required this.index,
    required this.group,
    required this.showCausa,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final accent = AppColors.primary;
    final macho = group.macho;
    final hembra = group.hembra;
    final tieneM = macho != null && macho.cantidad > 0;
    final tieneH = hembra != null && hembra.cantidad > 0;

    final cantM = tieneM ? macho.cantidad : 0;
    final cantH = tieneH ? hembra.cantidad : 0;
    final causaM = tieneM ? mortalityCausaLineText(showCausa: showCausa, causaNombre: macho.causaNombre, causaCodigo: macho.causaCodigo) : null;
    final causaH = tieneH ? mortalityCausaLineText(showCausa: showCausa, causaNombre: hembra.causaNombre, causaCodigo: hembra.causaCodigo) : null;
    final obsM = tieneM ? (macho.observacion ?? '') : '';
    final obsH = tieneH ? (hembra.observacion ?? '') : '';
    final fotosCount = (tieneM ? macho.fotos.length : 0) + (tieneH ? hembra.fotos.length : 0);
    final hasFotos = fotosCount > 0;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 4, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$index',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Total ${group.totalCantidad} aves',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined, size: 18, color: accent),
                  tooltip: 'Editar',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(
                    Icons.delete_outline,
                    size: 18,
                    color: AppColors.error.withValues(alpha: 0.9),
                  ),
                  tooltip: 'Eliminar',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
          // Data rows
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Macho row
                  _buildSexRow(
                    icon: Icons.male_rounded,
                    label: 'Machos',
                    color: AppColors.maleDark,
                    cantidad: cantM,
                    causaTexto: causaM,
                    observacion: obsM,
                    tieneDatos: tieneM,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 4),
                  // Hembra row
                  _buildSexRow(
                    icon: Icons.female_rounded,
                    label: 'Hembras',
                    color: AppColors.femaleDark,
                    cantidad: cantH,
                    causaTexto: causaH,
                    observacion: obsH,
                    tieneDatos: tieneH,
                    isDark: isDark,
                  ),
                  if (hasFotos) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.photo_camera_outlined, size: 14, color: isDark ? Colors.white54 : Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('$fotosCount foto(s)', style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSexRow({
    required IconData icon,
    required String label,
    required Color color,
    required int cantidad,
    required String? causaTexto,
    required String observacion,
    required bool tieneDatos,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        SizedBox(
          width: 60,
          child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: (tieneDatos ? color : Colors.grey).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tieneDatos ? '$cantidad' : '---',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tieneDatos ? (isDark ? Colors.white : AppColors.textPrimary) : (isDark ? Colors.white38 : Colors.grey.shade500),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (tieneDatos && causaTexto != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
            ),
            child: Text(
              causaTexto,
              style: TextStyle(fontSize: 10, color: isDark ? Colors.white70 : Colors.grey.shade700),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (tieneDatos && observacion.isNotEmpty) ...[
          SizedBox(
            width: 100,
            child: Text(
              observacion,
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: isDark ? Colors.white54 : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}
