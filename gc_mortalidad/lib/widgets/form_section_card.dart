import 'package:flutter/material.dart';
import '../utils/constants.dart';

class FormSectionTitle extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Widget? leading;
  final Color? color;
  final double bottomPadding;
  final double topPadding;

  const FormSectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.color,
    this.bottomPadding = 12,
    this.topPadding = 4,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding, top: topPadding),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: leading ??
                Icon(icon ?? Icons.circle_outlined, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: isDark ? Colors.white : AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class FormSectionCard extends StatelessWidget {
  final int? sectionNumber;
  final String? title;
  final IconData? icon;
  final Widget child;
  final Color? accentColor;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  const FormSectionCard({
    super.key,
    this.sectionNumber,
    this.title,
    this.icon,
    required this.child,
    this.accentColor,
    this.margin,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showHeader = title != null && title!.isNotEmpty;

    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.primary.withValues(alpha: 0.12),
        ),
        boxShadow: isDark ? null : AppColors.lightShadow,
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Row(
                children: [
                  if (sectionNumber != null) ...[
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$sectionNumber',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: color,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: color),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
