import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'constants.dart';

/// Barra de navegación del sistema (referencia imagen gris claro).
const Color kSystemNavBarColor = Color(0xFFF5F5F5);

class AppTheme {
  static void applySystemChrome([Brightness? brightness]) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF121212) : AppColors.background;
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
            ? const Color(0xFF121212)
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
    final bg = isDark ? const Color(0xFF121212) : AppColors.background;
    final surface = isDark ? const Color(0xFF1E1E1E) : AppColors.cardBackground;
    final textPrimary =
        isDark ? const Color(0xFFA5D6A7) : AppColors.textPrimary;
    final textSelected =
        isDark ? const Color(0xFFE8F5E9) : AppColors.textSelectedValue;
    final textMuted =
        isDark ? const Color(0xFF81C784) : AppColors.textMuted;
    final textLabel =
        isDark ? const Color(0xFF9E9E9E) : AppColors.textLabel;
    final borderColor =
        isDark ? const Color(0xFF424242) : Colors.grey.shade300;

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
      cardTheme: CardThemeData(
        color: surface,
        elevation: isDark ? 2 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : AppColors.dialogBackground,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF2C2C2C) : AppColors.dialogBackground,
        surfaceTintColor: Colors.transparent,
      ),
      expansionTileTheme: ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: const Border(),
        collapsedShape: const Border(),
        childrenPadding: EdgeInsets.zero,
        tilePadding: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(
          fontSize: AppColors.inputLabelFontSize,
          fontWeight: FontWeight.w600,
          color: textLabel,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: AppColors.inputFloatingLabelFontSize,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
        hintStyle: TextStyle(fontSize: 14, color: textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
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
          color: textMuted,
        ),
      ),
      extensions: [
        _AgFormColors(
          valueSelected: textSelected,
          valuePlaceholder: textMuted,
          labelMuted: textLabel,
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
    required this.labelMuted,
    required this.iconAccent,
  });

  final Color valueSelected;
  final Color valuePlaceholder;
  final Color labelMuted;
  final Color iconAccent;

  @override
  _AgFormColors copyWith({
    Color? valueSelected,
    Color? valuePlaceholder,
    Color? labelMuted,
    Color? iconAccent,
  }) {
    return _AgFormColors(
      valueSelected: valueSelected ?? this.valueSelected,
      valuePlaceholder: valuePlaceholder ?? this.valuePlaceholder,
      labelMuted: labelMuted ?? this.labelMuted,
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
      labelMuted: Color.lerp(labelMuted, other.labelMuted, t)!,
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
        labelMuted: AppColors.textLabel,
        iconAccent: AppColors.iconAccent,
      );
}
