import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Icono avícola (Font Awesome: feather-pointed).
class PoultryIcon extends StatelessWidget {
  final double size;
  final Color color;

  const PoultryIcon({
    super.key,
    required this.size,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return FaIcon(
      FontAwesomeIcons.featherPointed,
      size: size,
      color: color,
    );
  }
}
