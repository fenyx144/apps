import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/constants.dart';

/// Miniatura de una foto de evidencia (local o remota).
class PhotoThumb extends StatelessWidget {
  final String path;
  final double size;
  final double radius;
  final Color? borderColor;

  const PhotoThumb({
    super.key,
    required this.path,
    this.size = 48,
    this.radius = 8,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUrl = path.startsWith('http://') || path.startsWith('https://');

    Widget image;
    if (isUrl) {
      image = Image.network(
        path,
        width: size,
        height: size,
        fit: BoxFit.cover,
        headers: {'Authorization': 'Bearer ${AppConstants.apiToken}'},
        errorBuilder: (_, __, ___) => _empty(isDark),
      );
    } else {
      final file = File(path);
      image = file.existsSync()
          ? Image.file(file, width: size, height: size, fit: BoxFit.cover)
          : _empty(isDark);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: borderColor != null
              ? Border.all(color: borderColor!.withValues(alpha: 0.4))
              : null,
        ),
        child: image,
      ),
    );
  }

  Widget _empty(bool isDark) {
    return Container(
      width: size,
      height: size,
      color: isDark ? const Color(0xFF334155) : Colors.grey.shade200,
      child: Icon(
        Icons.broken_image_outlined,
        size: size * 0.42,
        color: Colors.grey.shade500,
      ),
    );
  }
}

/// Franja horizontal de miniaturas de fotos.
class PhotoStrip extends StatelessWidget {
  final List<String> fotos;
  final double size;
  final double spacing;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  const PhotoStrip({
    super.key,
    required this.fotos,
    this.size = 52,
    this.spacing = 8,
    this.borderColor,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (fotos.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: size,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: fotos.length,
        separatorBuilder: (_, __) => SizedBox(width: spacing),
        itemBuilder: (context, index) => PhotoThumb(
          path: fotos[index],
          size: size,
          borderColor: borderColor,
        ),
      ),
    );
  }
}
