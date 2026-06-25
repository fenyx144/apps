import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// Icono de registro de mortalidad (clipboard + lista).
class MortalityRegisterIcon extends StatelessWidget {
  final double size;
  final Color color;

  const MortalityRegisterIcon({
    super.key,
    required this.size,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return FaIcon(
      FontAwesomeIcons.clipboardList,
      size: size,
      color: color,
    );
  }
}
