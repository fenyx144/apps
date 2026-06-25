import 'package:flutter/material.dart';
import '../utils/constants.dart';

class ChoiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final LinearGradient? gradient;
  final Color accentColor;
  final VoidCallback onTap;
  final bool compact;

  const ChoiceCard({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
    this.gradient,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconGrad = gradient ??
        LinearGradient(
          colors: [accentColor, accentColor.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: EdgeInsets.symmetric(
            vertical: compact ? 8 : 10,
            horizontal: compact ? 4 : 8,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accentColor.withValues(alpha: isDark ? 0.18 : 0.08)
                : (isDark ? AppColors.darkSurface : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? accentColor : AppColors.primary.withValues(alpha: 0.2),
              width: selected ? 2 : 1.2,
            ),
            boxShadow: selected ? AppColors.lightShadow : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(compact ? 6 : 8),
                decoration: BoxDecoration(
                  gradient: iconGrad,
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                ),
                child: Icon(icon, color: Colors.white, size: compact ? 16 : 18),
              ),
              SizedBox(height: compact ? 4 : 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: compact ? 10 : 11,
                  color: isDark ? Colors.white : AppColors.textPrimary,
                  height: 1.1,
                ),
              ),
              if (selected && !compact) ...[
                const SizedBox(height: 4),
                Icon(Icons.check_circle, color: accentColor, size: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
