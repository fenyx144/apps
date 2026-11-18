import 'package:flutter/material.dart';
import 'constants.dart';

/// Acento de los formularios de campo (anomalías, artículos, alcoholemia).
const Color acentoTurquesa = Color(0xFF0FA3B1);

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

  /// Fondo de tarjeta y de campo: la superficie del tema, no un blanco fijo.
  Color get superficieCampo => Theme.of(this).colorScheme.surface;

  Color get textoCampo => Theme.of(this).colorScheme.onSurface;

  InputDecoration campoAcento(String label) {
    const borde = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: acentoTurquesa, width: 1.5),
    );
    return InputDecoration(
      filled: true,
      fillColor: superficieCampo,
      isDense: true,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      labelText: label,
      labelStyle: const TextStyle(color: acentoTurquesa, fontWeight: FontWeight.w600),
      floatingLabelStyle: const TextStyle(
        color: acentoTurquesa,
        fontWeight: FontWeight.w700,
        fontSize: 13.5,
      ),
      border: borde,
      enabledBorder: borde,
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: acentoTurquesa, width: 2),
      ),
    );
  }

  ShapeBorder get tarjetaAcento => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: acentoTurquesa, width: 1.4),
      );

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
