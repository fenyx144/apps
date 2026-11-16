import 'package:flutter/material.dart';

import 'constants.dart';

extension AppThemeContext on BuildContext {
  bool get isDarkTheme => Theme.of(this).brightness == Brightness.dark;

  Color get primaryTextColor =>
      isDarkTheme ? AppColors.darkTextPrimary : AppColors.textPrimary;

  Color get secondaryTextColor =>
      isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary;

  Color get mutedTextColor =>
      isDarkTheme ? AppColors.darkTextMuted : AppColors.textMuted;

  Color get cardColor =>
      Theme.of(this).cardTheme.color ??
      (isDarkTheme ? AppColors.darkCard : AppColors.cardBackground);

  Color get surfaceColor =>
      isDarkTheme ? AppColors.darkBackground : Colors.white;

  Color get borderColor =>
      isDarkTheme ? AppColors.darkBorder : AppColors.borderLight;

  /// Índigo suave para "Machos" (varía según tema).
  Color get maleColor =>
      isDarkTheme ? AppColors.maleAccentDark : AppColors.maleAccent;

  /// Coral suave para "Hembras" (varía según tema).
  Color get femaleColor =>
      isDarkTheme ? AppColors.femaleAccentDark : AppColors.femaleAccent;

  /// Fondo suave para bloques de "Machos" (varía según tema).
  Color get maleBgColor =>
      isDarkTheme
          ? AppColors.maleAccentDark.withValues(alpha: 0.18)
          : AppColors.maleTint;

  /// Fondo suave para bloques de "Hembras" (varía según tema).
  Color get femaleBgColor =>
      isDarkTheme
          ? AppColors.femaleAccentDark.withValues(alpha: 0.18)
          : AppColors.femaleTint;
}

/// Bordes de inputs sin doble línea (contenedor + decoration).
class AppInputStyles {
  static const double radius = 12;

  static OutlineInputBorder borderNone([double r = radius]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(r),
        borderSide: BorderSide.none,
      );

  static OutlineInputBorder borderOf(
    BuildContext context, {
    double r = radius,
    bool focused = false,
    Color? color,
    bool accent = false,
  }) {
    Color sideColor;
    if (color != null) {
      sideColor = color;
    } else if (focused) {
      sideColor = AppColors.primary;
    } else if (accent) {
      sideColor = AppColors.primary.withValues(alpha: 0.28);
    } else {
      sideColor = context.borderColor;
    }

    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(r),
      borderSide: BorderSide(
        color: sideColor,
        width: focused ? 1.5 : 1,
      ),
    );
  }

  static InputDecoration decoration(
    BuildContext context, {
    double r = radius,
    String? labelText,
    String? hintText,
    TextStyle? hintStyle,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
    bool filled = true,
    Color? fillColor,
    EdgeInsetsGeometry? contentPadding,
    bool isDense = false,
    String? counterText,
    bool accentBorder = false,
  }) {
    final isDark = context.isDarkTheme;
    final normal = borderOf(context, r: r, accent: accentBorder);
    final focused = borderOf(context, r: r, focused: true);
    final error = borderOf(context, r: r, color: AppColors.error);

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      hintStyle: hintStyle,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      filled: filled,
      fillColor: fillColor ?? (isDark ? AppColors.darkBackground : Colors.white),
      isDense: isDense,
      contentPadding: contentPadding,
      counterText: counterText,
      border: normal,
      enabledBorder: normal,
      focusedBorder: focused,
      errorBorder: error,
      focusedErrorBorder: error,
      disabledBorder: normal,
    );
  }

  /// Para campos dentro de tarjetas que ya tienen borde exterior.
  static InputDecoration decorationFlat(
    BuildContext context, {
    double r = radius,
    String? labelText,
    String? hintText,
    TextStyle? hintStyle,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
    bool filled = true,
    Color? fillColor,
    String? counterText,
  }) {
    final none = borderNone(r);
    final isDark = context.isDarkTheme;

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      hintStyle: hintStyle,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: errorText,
      filled: filled,
      fillColor: fillColor ?? (isDark ? AppColors.darkBackground : Colors.white),
      counterText: counterText,
      border: none,
      enabledBorder: none,
      focusedBorder: none,
      errorBorder: none,
      focusedErrorBorder: none,
      disabledBorder: none,
    );
  }
}

/// Mensaje de validación debajo del campo.
class AppFieldError extends StatelessWidget {
  final String? message;

  const AppFieldError(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 4),
      child: Text(
        message!,
        style: const TextStyle(
          color: AppColors.error,
          fontSize: 12,
          height: 1.2,
        ),
      ),
    );
  }
}

/// Acentos neutros de pizarra para reportes y auditoría.
/// En el rediseño el color solo indica tipo de dato (Machos/Hembras o el tipo
/// de mortalidad: Incubación, Transporte, Producción, Despacho), por lo que los
/// acentos generales pasan a la escala pizarra (gris azulado) sin teñir cards.
extension PaletaAzulReporte on BuildContext {
  Color get azulAccent =>
      isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary;

  Color get azulTexto =>
      isDarkTheme ? AppColors.darkTextPrimary : AppColors.textPrimary;

  Color get azulTextoSuave =>
      isDarkTheme ? AppColors.darkTextSecondary : AppColors.textSecondary;

  Color get azulTextoMuted =>
      isDarkTheme ? AppColors.darkTextMuted : AppColors.textMuted;
}

/// Tema derivado: acentos neutros sobre superficies del tema base.
ThemeData azulReporteTheme(BuildContext context) {
  final base = Theme.of(context);
  final dark = base.brightness == Brightness.dark;
  final cs = base.colorScheme.copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    onSurface: dark ? AppColors.darkTextPrimary : AppColors.textPrimary,
    onSurfaceVariant:
        dark ? AppColors.darkTextSecondary : AppColors.textSecondary,
  );
  return base.copyWith(
    colorScheme: cs,
    iconTheme: base.iconTheme.copyWith(color: cs.onSurfaceVariant),
  );
}
