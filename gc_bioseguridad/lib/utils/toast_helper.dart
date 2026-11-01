import 'package:flutter/material.dart';

void showToast(
  BuildContext context,
  String message, {
  Color backgroundColor = const Color(0xFF323232),
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
}) {
  if (!context.mounted) return;
  final overlay = Navigator.of(context, rootNavigator: true).overlay;
  if (overlay == null) return;

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      reverseDuration: const Duration(milliseconds: 300),
    );
    _controller.forward();
    Future.delayed(widget.duration, () async {
      if (mounted) await _controller.reverse();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomOffset = 40.0 + MediaQuery.of(context).padding.bottom;
    return Positioned(
      bottom: bottomOffset,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _controller,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: widget.backgroundColor.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Text(
                    widget.message,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
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

void showSuccessToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFF00C853),
      icon: Icons.check_circle_outline,
    );

void showErrorToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFFE53935),
      icon: Icons.error_outline,
    );

void showInfoToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFF64B5F6),
      icon: Icons.info_outline,
    );

void showWarningToast(BuildContext context, String msg) => showToast(
      context,
      msg,
      backgroundColor: const Color(0xFFFFB300),
      icon: Icons.warning_amber_rounded,
    );
