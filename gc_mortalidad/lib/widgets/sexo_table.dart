import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import 'dashed_photo_slot.dart';

/// Ancho de la columna de etiquetas (ej.: 'Cantidad', 'Preparar') en las
/// tablas de captura por sexo.
const double kSexoLabelWidth = 104;

/// Tabla compacta de captura por sexo: dos columnas (Machos | Hembras) y
/// filas definidas por el llamador. Cada celda queda alineada y el usuario
/// ve ambos sexos a la vez, sin pestañas.
class SexoGridTable extends StatelessWidget {
  final Color accent;
  final List<Widget> rows;
  final bool showHeader;
  final List<String> errors;

  const SexoGridTable({
    super.key,
    required this.accent,
    required this.rows,
    this.showHeader = true,
    this.errors = const [],
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final divider =
        (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.25)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              if (showHeader) ...[
                _buildHeader(accent, isDark),
                if (rows.isNotEmpty)
                  Divider(height: 1, thickness: 1, color: divider),
              ],
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) Divider(height: 1, thickness: 1, color: divider),
                rows[i],
              ],
            ],
          ),
        ),
        for (final e in errors) _errorLine(context, e),
      ],
    );
  }

  Widget _buildHeader(Color accent, bool isDark) {
    return Container(
      color: accent.withValues(alpha: isDark ? 0.16 : 0.08),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: kSexoLabelWidth),
          const SizedBox(width: 8),
          Expanded(
            child: _headerCell(
              Icons.male_rounded,
              'Machos',
              AppColors.maleDark,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _headerCell(
              Icons.female_rounded,
              'Hembras',
              AppColors.femaleDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCell(IconData icon, String text, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorLine(BuildContext context, String message) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_rounded, size: 14, color: AppColors.error),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de la tabla por sexo: etiqueta a la izquierda y dos celdas alineadas.
class SexoGridRow extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Widget? cellM;
  final Widget? cellH;

  const SexoGridRow({
    super.key,
    required this.label,
    this.icon,
    this.iconColor,
    this.cellM,
    this.cellH,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: kSexoLabelWidth,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 15,
                    color: iconColor ??
                        (isDark ? Colors.white54 : Colors.grey.shade600),
                  ),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: cellM ?? const SizedBox.shrink()),
          const SizedBox(width: 8),
          Expanded(child: cellH ?? const SizedBox.shrink()),
        ],
      ),
    );
  }
}

/// Celda numérica compacta (sin botones +/−): teclado numérico y solo dígitos.
class SexoNumField extends StatelessWidget {
  final TextEditingController controller;
  final Color accent;
  final bool hasError;
  final String hintText;
  final bool enabled;

  const SexoNumField({
    super.key,
    required this.controller,
    required this.accent,
    this.hasError = false,
    this.hintText = '0',
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final errorColor = AppColors.error;
    final textColor = !enabled
        ? (isDark ? Colors.white38 : Colors.grey.shade500)
        : (isDark ? Colors.white : AppColors.textPrimary);

    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      textAlign: TextAlign.center,
      maxLength: 6,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: textColor,
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        counterText: '',
        filled: true,
        fillColor: isDark ? AppColors.darkCard : Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        hintStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white30 : Colors.grey.shade400,
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? errorColor : accent.withValues(alpha: 0.25),
            width: hasError ? 1.4 : 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: hasError ? errorColor : accent,
            width: 1.6,
          ),
        ),
      ),
    );
  }
}

/// Celda tipo selector (Causa): toca y abre el buscador.
class SexoSelectCell extends StatelessWidget {
  final String? value;
  final String placeholder;
  final VoidCallback onTap;
  final Color accent;
  final bool hasError;
  final bool enabled;

  const SexoSelectCell({
    super.key,
    required this.onTap,
    required this.accent,
    this.value,
    this.placeholder = 'Seleccionar',
    this.hasError = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final has = value != null && value!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasError
                  ? AppColors.error
                  : accent.withValues(alpha: 0.25),
              width: hasError ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  has ? value! : placeholder,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: has ? FontWeight.w700 : FontWeight.w500,
                    color: !enabled
                        ? (isDark ? Colors.white38 : Colors.grey.shade500)
                        : has
                            ? (isDark ? Colors.white : AppColors.textPrimary)
                            : (isDark ? Colors.white38 : Colors.grey.shade500),
                  ),
                ),
              ),
              Icon(
                Icons.arrow_drop_down_rounded,
                size: 18,
                color: accent.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chip de estado (ej.: fila Suma) con color por estado.
class SexoStatusChip extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color color;

  const SexoStatusChip({
    super.key,
    required this.text,
    this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloque por sexo (fuera de la cuadrícula): observación + fotos.
class SexoObsFotoBlock extends StatelessWidget {
  final String sexoLabel;
  final IconData icon;
  final Color accent;
  final TextEditingController obsController;
  final List<String> fotos;
  final int maxFotos;
  final VoidCallback onAddFoto;
  final void Function(int index) onEditFoto;
  final void Function(int index) onRemoveFoto;

  const SexoObsFotoBlock({
    super.key,
    required this.sexoLabel,
    required this.icon,
    required this.accent,
    required this.obsController,
    required this.fotos,
    required this.maxFotos,
    required this.onAddFoto,
    required this.onEditFoto,
    required this.onRemoveFoto,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(icon, size: 15, color: accent),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  sexoLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                'Fotos ${fotos.length}/$maxFotos',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: obsController,
            maxLines: 2,
            maxLength: 250,
            textCapitalization: TextCapitalization.sentences,
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
            decoration: AppInputStyles.decoration(
              context,
              r: 10,
              labelText: 'Observación',
              hintText: 'Notas para $sexoLabel...',
              accentBorder: true,
              isDense: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 78,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(top: 4),
              children: [
                ...fotos.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: DashedPhotoSlot(
                          size: 72,
                          imagePath: e.value,
                          onAdd: onAddFoto,
                          onTapImage: () => onEditFoto(e.key),
                          onDeleteImage: () => onRemoveFoto(e.key),
                        ),
                      ),
                    ),
                if (fotos.length < maxFotos)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: DashedPhotoSlot(
                      size: 72,
                      onAdd: onAddFoto,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
