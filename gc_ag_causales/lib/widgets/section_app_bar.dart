import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/screen_status_bar.dart';

/// AppBar de sección: menú + icono + título (+ acciones opcionales).
class SectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SectionAppBar({
    super.key,
    required this.title,
    required this.sectionIcon,
    this.actions,
    this.preferredHeight = 70,
    this.navigationBarColor,
  });

  final String title;
  final IconData sectionIcon;
  final List<Widget>? actions;
  final double preferredHeight;
  final Color? navigationBarColor;

  @override
  Size get preferredSize => Size.fromHeight(preferredHeight);

  @override
  Widget build(BuildContext context) {
    return ScreenStatusBar(
      color: AppColors.primary,
      iconBrightness: Brightness.light,
      navigationBarColor: navigationBarColor,
      child: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.headerGradient,
          boxShadow: AppColors.strongShadow,
        ),
        child: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          actions: actions,
          leading: Builder(
            builder: (context) => IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.menu_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Icon(sectionIcon, color: Colors.white, size: 24),
              ),
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
      ),
    );
  }
}

/// Botón guardar (disquete celeste en círculo blanco) para el AppBar.
class AppBarSaveButton extends StatelessWidget {
  const AppBarSaveButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        onPressed: onPressed,
        icon: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.save_outlined,
            color: AppColors.iconAccent,
            size: 22,
          ),
        ),
      ),
    );
  }
}
