import 'package:flutter/material.dart';

void showToast(
  BuildContext context,
  String message, {
  Color backgroundColor = const Color(0xFF323232),
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context);

  final overlayEntry = OverlayEntry(
    builder: (context) => _AnimatedToast(
      message: message,
      icon: icon,
      backgroundColor: backgroundColor,
      duration: duration,
    ),
  );

  overlay.insert(overlayEntry);
  Future.delayed(duration + const Duration(milliseconds: 300), () {
    overlayEntry.remove();
  });
}

class _AnimatedToast extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color backgroundColor;
  final Duration duration;

  const _AnimatedToast({
    required this.message,
    this.icon,
    required this.backgroundColor,
    required this.duration,
  });

  @override
  State<_AnimatedToast> createState() => _AnimatedToastState();
}

class _AnimatedToastState extends State<_AnimatedToast>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _opacityAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();

    Future.delayed(widget.duration, () async {
      if (mounted) {
        await _controller.reverse();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final navBarHeight = MediaQuery.paddingOf(context).bottom;

    // Ajusta posición: si hay teclado, sube el toast; sino considera la barra de navegación
    final bottomOffset = keyboardHeight > 0 ? keyboardHeight + 40 : navBarHeight + 40;

    return Positioned(
      bottom: bottomOffset,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _offsetAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: widget.backgroundColor.withOpacity(0.9),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, color: Colors.white, size: 20),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showSuccessToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFF4CAF50),
      icon: Icons.check_circle_outline,
    );

void showErrorToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFFF44336),
      icon: Icons.error_outline,
    );

void showInfoToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFF2196F3),
      icon: Icons.info_outline,
    );

void showWarningToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFFFFC107),
      icon: Icons.warning_amber_rounded,
    );
