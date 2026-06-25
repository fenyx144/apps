import 'package:flutter/material.dart';
import '../utils/constants.dart';

PreferredSizeWidget buildAppBar(
  BuildContext context,
  String title, {
  bool showBackButton = false,
  IconData appIcon = Icons.list_alt,
  Widget? appIconWidget,
  IconData? rightIcon,
  VoidCallback? onRightIconPressed,
  Color? rightIconColor,
  bool rightIconLoading = false,
  String? rightIconTooltip,
  PreferredSizeWidget? bottom,
}) {
  return PreferredSize(
    preferredSize: Size.fromHeight(bottom != null ? 74 : 70),
    child: Container(
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
        boxShadow: AppColors.strongShadow,
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: IconThemeData(
          color: rightIconColor ?? AppColors.textOnPrimary,
          size: 24,
        ),
        bottom: bottom,
        leading: showBackButton
            ? IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
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
                ),
              ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: appIconWidget ??
                  Icon(
                    appIcon,
                    color: AppColors.textOnPrimary,
                    size: 22,
                  ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: rightIcon != null
            ? [
                IconButton(
                  tooltip: rightIconTooltip ?? 'Guardar',
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: rightIconLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: rightIconColor ?? AppColors.primary,
                            ),
                          )
                        : Icon(
                            rightIcon,
                            color: rightIconColor ?? AppColors.primary,
                            size: 20,
                          ),
                  ),
                  onPressed: rightIconLoading ? null : onRightIconPressed,
                ),
              ]
            : null,
      ),
    ),
  );
}
