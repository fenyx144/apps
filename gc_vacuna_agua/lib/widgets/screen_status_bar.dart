import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_theme.dart';

/// Aplica el color de la status bar según el fondo visible de la pantalla.
class ScreenStatusBar extends StatelessWidget {
  const ScreenStatusBar({
    super.key,
    required this.color,
    required this.child,
    this.iconBrightness,
    this.navigationBarColor,
  });

  final Color color;
  final Widget child;
  final Brightness? iconBrightness;
  final Color? navigationBarColor;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayForBackground(
        color,
        iconBrightness: iconBrightness,
        systemNavigationBarColor: navigationBarColor,
      ),
      child: child,
    );
  }
}
