import 'package:flutter/material.dart';

import 'constants.dart';

extension AppThemeColors on BuildContext {
  bool get isAppDark => Theme.of(this).brightness == Brightness.dark;

  Color get surfaceCard =>
      isAppDark ? AppColors.cardBackground : AppColors.cardLight;

  Color get surfaceElevated =>
      isAppDark ? AppColors.surface : AppColors.surfaceLight;

  Color get scaffoldMuted =>
      isAppDark ? AppColors.background : AppColors.backgroundLight;

  Color get borderSubtle =>
      isAppDark ? AppColors.border : AppColors.borderLight;

  Color get shadowColor => Colors.black;

  Color get textThemePrimary =>
      isAppDark ? AppColors.textPrimary : AppColors.textPrimaryLight;

  Color get textThemeSecondary =>
      isAppDark ? AppColors.textSecondary : AppColors.textSecondaryLight;

  Color get textThemeMuted =>
      isAppDark ? AppColors.textMuted : AppColors.textMutedLight;

  Color get chartLabelColor => textThemeSecondary;

  Color get dialogSurface => surfaceCard;

  EdgeInsets get dialogInsetPadding =>
      const EdgeInsets.symmetric(horizontal: 12, vertical: 24);

  List<BoxShadow> cardShadow({double blur = 10, double dy = 3}) => [
    BoxShadow(
      color: shadowColor.withValues(alpha: isAppDark ? 0.35 : 0.12),
      blurRadius: blur,
      offset: Offset(0, dy),
    ),
  ];
}
