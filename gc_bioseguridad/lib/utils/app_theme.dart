import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';

/// Barra de navegación del sistema (referencia imagen gris claro).
const Color kSystemNavBarColor = Color(0xFFF5F5F5);

class AppTheme {
  static void applySystemChrome([Brightness? brightness]) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    SystemChrome.setSystemUIOverlayStyle(overlayForBackground(bg));
  }

  static SystemUiOverlayStyle overlayForBackground(
    Color background, {
    Brightness? iconBrightness,
    Color? systemNavigationBarColor,
  }) {
    final useLightIcons = iconBrightness != null
        ? iconBrightness == Brightness.light
        : ThemeData.estimateBrightnessForColor(background) == Brightness.dark;

    final resolvedNavColor = systemNavigationBarColor ??
        (ThemeData.estimateBrightnessForColor(background) == Brightness.dark
            ? AppColors.darkBackground
            : kSystemNavBarColor);

    return SystemUiOverlayStyle(
      statusBarColor: background,
      statusBarIconBrightness:
          useLightIcons ? Brightness.light : Brightness.dark,
      statusBarBrightness:
          useLightIcons ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: resolvedNavColor,
      systemNavigationBarIconBrightness:
          ThemeData.estimateBrightnessForColor(resolvedNavColor) ==
                  Brightness.dark
              ? Brightness.light
              : Brightness.dark,
      systemNavigationBarDividerColor: Colors.transparent,
    );
  }

  static SystemUiOverlayStyle statusBarForGradient() {
    return overlayForBackground(
      AppColors.primary,
      iconBrightness: Brightness.light,
    );
  }

  static SystemUiOverlayStyle statusBarForSplash() {
    return overlayForBackground(
      AppColors.primaryDark,
      iconBrightness: Brightness.light,
    );
  }

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBackground : AppColors.background;
    final surface = isDark ? AppColors.darkCard : AppColors.cardBackground;
    final textPrimary =
        isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final textSelected =
        isDark ? AppColors.darkTextPrimary : AppColors.textSelectedValue;
    final textMuted =
        isDark ? AppColors.darkTextMuted : AppColors.textMuted;
    final borderColor =
        isDark ? AppColors.darkBorder : AppColors.borderLight;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryLight,
      onSecondary: textPrimary,
      error: AppColors.error,
      onError: Colors.white,
      surface: surface,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: bg,
      colorScheme: colorScheme,
      dividerColor: isDark ? Colors.transparent : null,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: statusBarForGradient(),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      dividerTheme: DividerThemeData(color: borderColor),
      iconTheme: IconThemeData(color: textPrimary),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLg),
          side: isDark
              ? const BorderSide(color: AppColors.darkBorder)
              : BorderSide.none,
        ),
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.dialogBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusXl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkCard : AppColors.dialogBackground,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: Border(),
        collapsedShape: Border(),
        childrenPadding: EdgeInsets.zero,
        tilePadding: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusMd),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
        // Rótulo flotante (el texto que salta al borde cuando el campo se
        // enfoca): se declara aparte y más grande. Sin declararlo, Flutter usa
        // `labelStyle` y lo encoge por su cuenta (×0.75), así que a 13 quedaba
        // en 9.75 px y apenas se leía.
        floatingLabelStyle: const TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryDark,
        ),
        hintStyle: TextStyle(fontSize: 14, color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: textPrimary,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: bg),
      extensions: [
        _AgFormColors(
          valueSelected: textSelected,
          valuePlaceholder: textMuted,
          iconAccent: AppColors.iconAccent,
        ),
      ],
    );
  }
}

class _AgFormColors extends ThemeExtension<_AgFormColors> {
  const _AgFormColors({
    required this.valueSelected,
    required this.valuePlaceholder,
    required this.iconAccent,
  });

  final Color valueSelected;
  final Color valuePlaceholder;
  final Color iconAccent;

  @override
  _AgFormColors copyWith({
    Color? valueSelected,
    Color? valuePlaceholder,
    Color? iconAccent,
  }) {
    return _AgFormColors(
      valueSelected: valueSelected ?? this.valueSelected,
      valuePlaceholder: valuePlaceholder ?? this.valuePlaceholder,
      iconAccent: iconAccent ?? this.iconAccent,
    );
  }

  @override
  _AgFormColors lerp(ThemeExtension<_AgFormColors>? other, double t) {
    if (other is! _AgFormColors) return this;
    return _AgFormColors(
      valueSelected: Color.lerp(valueSelected, other.valueSelected, t)!,
      valuePlaceholder:
          Color.lerp(valuePlaceholder, other.valuePlaceholder, t)!,
      iconAccent: Color.lerp(iconAccent, other.iconAccent, t)!,
    );
  }
}

extension AgFormColorsX on BuildContext {
  _AgFormColors get formColors =>
      Theme.of(this).extension<_AgFormColors>() ??
      const _AgFormColors(
        valueSelected: AppColors.textSelectedValue,
        valuePlaceholder: AppColors.textMuted,
        iconAccent: AppColors.iconAccent,
      );
}
