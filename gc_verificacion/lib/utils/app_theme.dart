import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'constants.dart';

const Color kSystemNavBarColor = Color(0xFF0B0F16);

class AppTheme {
  static const String fontFamily = 'Inter';

  static void applySystemChrome([Brightness? brightness]) {
    SystemChrome.setSystemUIOverlayStyle(
      overlayForBackground(
        AppColors.background,
        iconBrightness: brightness == Brightness.light
            ? Brightness.dark
            : Brightness.light,
      ),
    );
  }

  static SystemUiOverlayStyle overlayForBackground(
    Color background, {
    Brightness? iconBrightness,
    Color? systemNavigationBarColor,
  }) {
    final useLightIcons = iconBrightness != null
        ? iconBrightness == Brightness.light
        : ThemeData.estimateBrightnessForColor(background) == Brightness.dark;

    final resolvedNavColor =
        systemNavigationBarColor ??
        (ThemeData.estimateBrightnessForColor(background) == Brightness.dark
            ? AppColors.background
            : kSystemNavBarColor);

    return SystemUiOverlayStyle(
      statusBarColor: background,
      statusBarIconBrightness: useLightIcons
          ? Brightness.light
          : Brightness.dark,
      statusBarBrightness: useLightIcons ? Brightness.dark : Brightness.light,
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

  static ThemeData dark() => _build(dark: true);

  static ThemeData light() => _build(dark: false);

  static ThemeData _build({required bool dark}) {
    final bg = dark ? AppColors.background : AppColors.backgroundLight;
    final surface = dark ? AppColors.cardBackground : AppColors.cardLight;
    final borde = dark ? AppColors.border : AppColors.borderLight;
    final texto = dark ? AppColors.textPrimary : AppColors.textPrimaryLight;
    final texto2 = dark
        ? AppColors.textSecondary
        : AppColors.textSecondaryLight;
    final texto3 = dark ? AppColors.textMuted : AppColors.textMutedLight;

    final colorScheme = ColorScheme(
      brightness: dark ? Brightness.dark : Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.primaryLight,
      onSecondary: texto,
      error: AppColors.error,
      onError: Colors.white,
      surface: surface,
      onSurface: texto,
      onSurfaceVariant: texto2,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      fontFamily: fontFamily,
      primaryColor: AppColors.primary,
      scaffoldBackgroundColor: bg,
      colorScheme: colorScheme,
      dividerColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: statusBarForGradient(),
        titleTextStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      dividerTheme: DividerThemeData(color: borde),
      iconTheme: IconThemeData(color: texto),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusLg),
          side: BorderSide(color: borde),
        ),
        shadowColor: Colors.black.withValues(alpha: 0.08),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusXl),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
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
            fontFamily: fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        labelStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: texto2,
        ),
        hintStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          color: texto3,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: BorderSide(color: borde, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusMd),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: texto,
          letterSpacing: -0.2,
        ),
        titleLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: texto,
        ),
        titleMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: texto,
        ),
        bodyLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: texto,
        ),
        bodyMedium: TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: texto2,
        ),
        labelLarge: TextStyle(
          fontFamily: fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: texto2,
        ),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: bg),
    );
  }
}
