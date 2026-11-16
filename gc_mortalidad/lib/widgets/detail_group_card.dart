import 'package:flutter/material.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/text_utils.dart';
import '../utils/theme_extensions.dart';
import 'photo_thumb.dart';
import 'sexo_table.dart';

/// Tarjeta compacta de un detalle (grupo Machos/Hembras de la misma sesión).
/// Usa una cuadrícula alineada con columnas Machos | Hembras y filas:
/// Cantidad (o Suma en despacho), una fila por etapa del proceso en
/// despacho, Causa, Observación y Fotos. En modo [readOnly] no muestra
/// los botones de editar/eliminar (ideal para resúmenes).
class DetailGroupCard extends StatelessWidget {
  final int index;
  final MortalityDetailGroup group;
  final bool showCausa;
  final bool isDespacho;
  final bool readOnly;

  /// Muestra una fila por etapa del proceso (despacho) y la fila 'Suma'.
  /// Solo se usa en el resumen al momento de guardar; en el formulario
  /// principal se mantiene la tarjeta simple (solo 'Cantidad').
  final bool desgloseEtapas;

  /// Coloca la fila 'Causa' justo debajo del encabezado Machos | Hembras
  /// para diferenciarla del bloque de cantidades/etapas.
  final bool causaAlInicio;

  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const DetailGroupCard({
    super.key,
    required this.index,
    required this.group,
    required this.showCausa,
    required this.isDespacho,
    this.readOnly = false,
    this.desgloseEtapas = false,
    this.causaAlInicio = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final accent = AppColors.primary;
    final macho = group.macho;
    final hembra = group.hembra;
    final tieneM = macho != null && macho.hasContent;
    final tieneH = hembra != null && hembra.hasContent;

    final cantM = tieneM ? macho.cantidad : 0;
    final cantH = tieneH ? hembra.cantidad : 0;
    final causaM = tieneM
        ? mortalityCausaLineText(
            showCausa: showCausa,
            causaNombre: macho.causaNombre,
            causaCodigo: macho.causaCodigo,
          )
        : null;
    final causaH = tieneH
        ? mortalityCausaLineText(
            showCausa: showCausa,
            causaNombre: hembra.causaNombre,
            causaCodigo: hembra.causaCodigo,
          )
        : null;
    final obsM = tieneM ? (macho.observacion ?? '') : '';
    final obsH = tieneH ? (hembra.observacion ?? '') : '';
    final fotosM = tieneM ? macho.fotos : const <String>[];
    final fotosH = tieneH ? hembra.fotos : const <String>[];

    final hayCausa = causaM != null || causaH != null;
    final tipoM = tieneM ? macho.tipoMuerte : null;
    final tipoH = tieneH ? hembra.tipoMuerte : null;
    final hayTipo = tipoM != null || tipoH != null;
    final hayFotos = fotosM.isNotEmpty || fotosH.isNotEmpty;

    // Valor de una etapa según el sexo (0 si no hay detalle o sin valor).
    int etapaDe(bool tiene, MortalityDetail? d, String id) =>
        (tiene && d != null) ? d.procesoEtapa(id) : 0;

    // Etapas de despacho con datos en al menos un sexo.
    final etapasVisibles = isDespacho
        ? kDespachoEtapas
              .where(
                (e) =>
                    etapaDe(tieneM, macho, e.id) > 0 ||
                    etapaDe(tieneH, hembra, e.id) > 0,
              )
              .toList()
        : <DespachoEtapa>[];

    final maleColor = AppColors.maleDark;
    final femaleColor = AppColors.femaleDark;

    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: isDark ? Colors.white54 : Colors.grey.shade600,
    );

    // Celda vacía/sin dato.
    Widget emptyCell() => Center(
      child: Text(
        '—',
        style: TextStyle(
          fontSize: 11,
          color: isDark ? Colors.white24 : Colors.grey.shade400,
        ),
      ),
    );

    // Celda de cantidad/suma, centrada y con fondo por sexo.
    Widget cantCell(bool tiene, int cant, Color color) => Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
      decoration: BoxDecoration(
        color: (tiene ? color : Colors.grey).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tiene ? '$cant' : '---',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: tiene
              ? (isDark ? Colors.white : AppColors.textPrimary)
              : (isDark ? Colors.white38 : Colors.grey.shade500),
        ),
      ),
    );

    // Celda numérica de una etapa: '0' si el sexo está registrado pero la
    // etapa no tiene aves; '—' si el sexo no está registrado (no aplica).
    Widget etapaCell(bool tiene, int valor, Color color) {
      if (!tiene) return emptyCell();
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          '$valor',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: valor > 0
                ? (isDark ? Colors.white : color)
                : (isDark ? Colors.white38 : Colors.grey.shade500),
          ),
        ),
      );
    }

    Widget tipoCell(String? tipo, int cant) {
      if (tipo == null) return emptyCell();
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.borderLight,
          ),
        ),
        child: Text(
          '${tipo == 'ME' ? 'M.E.' : 'M.N.'} $cant',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
        ),
      );
    }

    // Celda de causa (chip de texto).
    Widget causaCell(String? causa, Color color) {
      if (causa == null) return emptyCell();
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          causa,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: isDark ? Colors.white : color,
          ),
        ),
      );
    }

    // Celda de observación: si el sexo está registrado pero no se ingresó
    // texto, se muestra 'sin observaciones'; si el sexo no está registrado
    // se muestra '—'.
    Widget obsCell(bool tiene, String obs) {
      if (!tiene) return emptyCell();
      final vacio = obs.trim().isEmpty;
      return Center(
        child: Text(
          vacio ? kSinObservaciones : obs.trim(),
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10.5,
            fontStyle: FontStyle.italic,
            height: 1.25,
            color: vacio
                ? (isDark ? Colors.white24 : Colors.grey.shade400)
                : (isDark ? Colors.white60 : Colors.grey.shade700),
          ),
        ),
      );
    }

    // Celda de fotos: miniaturas alineadas bajo la columna de su sexo.
    // Usa FittedBox para que 3 miniaturas no desborden la columna cuando
    // el ancho disponible es menor que el contenido.
    Widget fotosCell(List<String> fotos, Color color) {
      if (fotos.isEmpty) return emptyCell();
      return Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final f in fotos.take(3)) ...[
                PhotoThumb(path: f, size: 30, radius: 6, borderColor: color),
                const SizedBox(width: 4),
              ],
              if (fotos.length > 3) ...[
                Icon(Icons.photo_camera_outlined, size: 13, color: color),
                const SizedBox(width: 2),
                Text(
                  '${fotos.length}',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Una fila de la cuadrícula: etiqueta fija + celdas M/H del mismo ancho.
    Widget fieldRow(Widget label, Widget cellM, Widget cellH) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: kSexoLabelWidth, child: label),
            const SizedBox(width: 8),
            Expanded(child: cellM),
            const SizedBox(width: 8),
            Expanded(child: cellH),
          ],
        ),
      );
    }

    Widget labelTexto(String text) => Text(
      text,
      style: labelStyle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    Widget labelEtapa(DespachoEtapa e) => Row(
      children: [
        Icon(
          e.icon,
          size: 13,
          color: isDark ? Colors.white38 : Colors.grey.shade500,
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            e.nombre,
            style: labelStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

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
            padding: EdgeInsets.fromLTRB(8, 6, readOnly ? 8 : 4, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
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
                if (!readOnly) ...[
                  IconButton(
                    onPressed: onEdit,
                    icon: Icon(Icons.edit_outlined, size: 18, color: accent),
                    tooltip: 'Editar',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
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
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.06,
            ),
          ),
          // Cuerpo: cuadrícula alineada Machos | Hembras.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(width: kSexoLabelWidth + 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.male_rounded, size: 14, color: maleColor),
                          const SizedBox(width: 4),
                          Text(
                            'Machos',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: maleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.female_rounded,
                            size: 14,
                            color: femaleColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Hembras',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: femaleColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // En el resumen al guardar la causa va al inicio para
                // diferenciarla del bloque de cantidades/etapas.
                if (causaAlInicio && showCausa && hayCausa)
                  fieldRow(
                    labelTexto('Causa'),
                    causaCell(causaM, maleColor),
                    causaCell(causaH, femaleColor),
                  ),
                if (hayTipo)
                  fieldRow(
                    labelTexto('Tipo muerte'),
                    tipoCell(tipoM, cantM),
                    tipoCell(tipoH, cantH),
                  ),
                // Despacho con desglose (solo resumen al guardar): una fila
                // por etapa con datos y al final la fila 'Suma'.
                if (isDespacho && desgloseEtapas) ...[
                  for (final e in etapasVisibles)
                    fieldRow(
                      labelEtapa(e),
                      etapaCell(
                        tieneM,
                        etapaDe(tieneM, macho, e.id),
                        maleColor,
                      ),
                      etapaCell(
                        tieneH,
                        etapaDe(tieneH, hembra, e.id),
                        femaleColor,
                      ),
                    ),
                  fieldRow(
                    labelTexto('Suma'),
                    cantCell(tieneM, cantM, maleColor),
                    cantCell(tieneH, cantH, femaleColor),
                  ),
                ] else
                  fieldRow(
                    labelTexto('Cantidad'),
                    cantCell(tieneM, cantM, maleColor),
                    cantCell(tieneH, cantH, femaleColor),
                  ),
                if (!causaAlInicio && showCausa && hayCausa)
                  fieldRow(
                    labelTexto('Causa'),
                    causaCell(causaM, maleColor),
                    causaCell(causaH, femaleColor),
                  ),
                // Observación por sexo: siempre visible en el detalle.
                fieldRow(
                  labelTexto('Observación'),
                  obsCell(tieneM, obsM),
                  obsCell(tieneH, obsH),
                ),
                if (hayFotos)
                  fieldRow(
                    labelTexto('Fotos'),
                    fotosCell(fotosM, maleColor),
                    fotosCell(fotosH, femaleColor),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
