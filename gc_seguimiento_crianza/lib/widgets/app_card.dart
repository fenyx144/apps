import 'package:flutter/material.dart';
import '../utils/theme_colors.dart';

/// Contenedor tipo card con soporte de modo oscuro.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.borderRadius = 20,
    this.elevated = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: elevated ? context.surfaceElevated : context.surfaceCard,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: context.borderSubtle, width: 1),
        boxShadow: context.cardShadow(),
      ),
      child: child,
    );
  }
}
