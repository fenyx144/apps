import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';

class ThemeToggleTile extends StatelessWidget {
  const ThemeToggleTile({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final isDark = context.isDarkTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => themeService.toggleTheme(),
          borderRadius: BorderRadius.circular(16),
          splashColor: AppColors.primary.withValues(alpha: 0.12),
          highlightColor: AppColors.primary.withValues(alpha: 0.06),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: context.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: isDark ? 0.35 : 0.2),
                width: 1.5,
              ),
              boxShadow: isDark ? null : AppColors.lightShadow,
            ),
            child: Row(
              children: [
                Icon(
                  themeService.modeIcon,
                  color: isDark ? AppColors.primaryVibrant : AppColors.primary,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    themeService.modeLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.primaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
