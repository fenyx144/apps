import 'package:flutter/material.dart';
import 'constants.dart';

/// Colores y estilos que respetan el modo claro/oscuro del sistema.
extension AppThemeColors on BuildContext {
  bool get isAppDark => Theme.of(this).brightness == Brightness.dark;

  Color get surfaceCard =>
      isAppDark ? AppColors.darkCard : AppColors.cardBackground;

  Color get surfaceElevated =>
      isAppDark ? AppColors.darkCard : AppColors.cardBackground;

  Color get scaffoldMuted =>
      isAppDark ? AppColors.darkBackground : AppColors.background;

  Color get borderSubtle =>
      isAppDark ? AppColors.darkBorder : AppColors.borderLight;

  Color get shadowColor =>
      isAppDark ? Colors.black : Colors.grey.shade200;

  Color get textThemePrimary =>
      isAppDark ? AppColors.darkTextPrimary : AppColors.textPrimary;

  Color get textThemeSecondary =>
      isAppDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

  Color get textThemeMuted =>
      isAppDark ? AppColors.darkTextMuted : AppColors.textMuted;

  Color get chartLabelColor =>
      isAppDark ? AppColors.darkTextSecondary : AppColors.textMuted;

  Color get dialogSurface =>
      isAppDark ? AppColors.darkCard : AppColors.dialogBackground;

  // ── Tablas ─────────────────────────────────────────────────────────────
  // La tabla nació con el blanco de la app Android antigua. En modo oscuro eso
  // deja una cuadrícula blanca sobre el fondo oscuro, así que ahí las filas
  // pasan a gris pizarra (el mismo de las tarjetas) y la alterna sube un tono.

  /// Fondo de una fila de tabla.
  Color get tableCell =>
      isAppDark ? AppColors.darkTableRow : AppColors.cardBackground;

  /// Fondo de la fila alterna.
  Color get tableCellAlt =>
      isAppDark ? AppColors.darkTableRowAlt : AppColors.tableRowAlt;

  /// Borde de las celdas.
  Color get tableCellBorder =>
      isAppDark ? AppColors.darkTableBorder : AppColors.tableBorder;

  /// Fondo del título de la tabla.
  Color get tableCaption =>
      isAppDark ? AppColors.darkTableAccent : AppColors.tableAccent;

  /// Verde de la hora registrada. El de la app antigua (`horaText`) es oscuro y
  /// sobre el gris de la tabla en modo oscuro no se leía.
  Color get horaTexto => isAppDark ? const Color(0xFF66BB6A) : AppColors.horaText;

  EdgeInsets get dialogInsetPadding =>
      const EdgeInsets.symmetric(horizontal: 12, vertical: 24);

  List<BoxShadow> cardShadow({double blur = 10, double dy = 3}) => [
        BoxShadow(
          color: shadowColor.withValues(alpha: isAppDark ? 0.35 : 0.65),
          blurRadius: blur,
          offset: Offset(0, dy),
        ),
      ];
}
