import 'package:flutter/material.dart';
import 'constants.dart';

/// Colores y estilos que respetan el modo claro/oscuro del sistema.
extension AppThemeColors on BuildContext {
  bool get isAppDark => Theme.of(this).brightness == Brightness.dark;

  Color get surfaceCard =>
      isAppDark ? const Color(0xFF1E1E1E) : Colors.white;

  Color get surfaceElevated =>
      isAppDark ? const Color(0xFF2C2C2C) : Colors.white;

  Color get scaffoldMuted =>
      isAppDark ? const Color(0xFF121212) : AppColors.background;

  Color get borderSubtle =>
      isAppDark ? const Color(0xFF424242) : Colors.grey.shade300;

  Color get shadowColor =>
      isAppDark ? Colors.black : Colors.grey.shade200;

  Color get textThemePrimary => Theme.of(this).colorScheme.onSurface;

  Color get textThemeSecondary =>
      isAppDark ? const Color(0xFF81C784) : AppColors.textSecondary;

  Color get textThemeMuted =>
      isAppDark ? const Color(0xFF9E9E9E) : AppColors.textMuted;

  Color get chartLabelColor =>
      isAppDark ? const Color(0xFFB0B0B0) : Colors.grey;

  Color get dialogSurface =>
      isAppDark ? const Color(0xFF2C2C2C) : AppColors.dialogBackground;

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
