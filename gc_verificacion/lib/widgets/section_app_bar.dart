import 'package:flutter/material.dart';

import '../utils/constants.dart';
import 'screen_status_bar.dart';

class SectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SectionAppBar({
    super.key,
    required this.title,
    required this.sectionIcon,
    this.actions,
    this.showDrawerButton = true,
    this.preferredHeight = 70,
  });

  final String title;
  final IconData sectionIcon;
  final List<Widget>? actions;
  final bool showDrawerButton;
  final double preferredHeight;

  @override
  Size get preferredSize => Size.fromHeight(preferredHeight);

  Widget _botonIzquierdo(BuildContext context) {
    final decoracion = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.2),
        width: 1.5,
      ),
    );

    if (!showDrawerButton) {
      return IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: decoracion,
          child: const Icon(Icons.arrow_back_rounded,
              color: Colors.white, size: 22),
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      );
    }

    return Builder(
      builder: (context) => IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: decoracion,
          child:
              const Icon(Icons.menu_rounded, color: Colors.white, size: 22),
        ),
        onPressed: () => Scaffold.of(context).openDrawer(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScreenStatusBar(
      color: AppColors.primary,
      iconBrightness: Brightness.light,
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.headerGradient,
          boxShadow: AppColors.mediumShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
              actions: actions,
              leading: _botonIzquierdo(context),
              title: Row(
                children: [
                  Icon(sectionIcon, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
