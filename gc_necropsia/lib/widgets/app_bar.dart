import 'package:flutter/material.dart';

import '../utils/constants.dart';

PreferredSizeWidget buildAppBar(
  BuildContext context,
  String title, {
  bool showBackButton = false,
  IconData appIcon = Icons.list_alt,
  IconData? rightIcon,
  VoidCallback? onRightIconPressed,
  Color? rightIconColor,
}) {
  return PreferredSize(
    preferredSize: const Size.fromHeight(70),
    child: Container(
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        boxShadow: AppColors.strongShadow,
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(
          color: rightIconColor ?? AppColors.textOnPrimary,
          size: 24,
        ),
        leading: Builder(
          builder: (context) {
            if (showBackButton) {
              // Mostrar flecha de retroceso
              return IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded, // o Icons.arrow_back
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(), // retroceder
              );
            } else {
              // Mostrar menú (AppDrawer)
              return IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.menu_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: () => Scaffold.of(context).openDrawer(),
              );
            }
          },
        ),
        title: Row(
          children: [
            Icon(
              appIcon,
              color: AppColors.textOnPrimary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ],
        ),
        actions: rightIcon != null
            ? [
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      rightIcon,
                      color: rightIconColor ?? AppColors.textOnPrimary,
                      size: 20,
                    ),
                  ),
                  onPressed: onRightIconPressed ?? () {},
                  tooltip: 'Acción',
                ),
              ]
            : null,
      ),
    ),
  );
}