import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../screens/image_editor_screen.dart';
import '../utils/constants.dart';
import '../utils/toast_helper.dart';

class ImageSlotRow extends StatelessWidget {
  final List<String?> paths;
  final void Function(int index, String? path) onChanged;

  const ImageSlotRow({
    super.key,
    required this.paths,
    required this.onChanged,
  });

  Future<XFile> _copyToAppDir(XFile picked, int index) async {
    final bytes = await picked.readAsBytes();
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/sc_images');
    if (!imagesDir.existsSync()) {
      imagesDir.createSync(recursive: true);
    }
    final ext = path.extension(picked.path).isEmpty
        ? '.jpg'
        : path.extension(picked.path);
    final destPath = path.join(
      imagesDir.path,
      'sc_${DateTime.now().millisecondsSinceEpoch}_$index$ext',
    );
    await File(destPath).writeAsBytes(bytes);
    return XFile(destPath);
  }

  Future<bool> _requestGranted(Permission permission) async {
    final status = await permission.request();
    return status.isGranted || status.isLimited;
  }

  Future<void> _pickNew(BuildContext context, int index) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF2D2D4A) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.primary,
                ),
                title: const Text('Galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    if (source == ImageSource.camera) {
      if (!await _requestGranted(Permission.camera)) {
        if (context.mounted) {
          showErrorToast(context, 'Se necesita permiso de cámara.');
        }
        return;
      }
    } else {
      var granted = await _requestGranted(Permission.photos);
      if (!granted) {
        granted = await _requestGranted(Permission.storage);
      }
      if (!granted) {
        if (context.mounted) {
          showErrorToast(context, 'Se necesita permiso para acceder a la galería.');
        }
        return;
      }
    }

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !context.mounted) return;

    final saved = await _copyToAppDir(picked, index);
    if (!context.mounted) return;
    onChanged(index, saved.path);
  }

  Future<void> _editImage(BuildContext context, int index, String existing) async {
    final result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(imageFile: XFile(existing)),
      ),
    );
    if (result != null && context.mounted) {
      onChanged(index, result.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(3, (i) {
          final path = i < paths.length ? paths[i] : null;
          return _DashedPhotoSlot(
            imagePath: path,
            onAdd: () => _pickNew(context, i),
            onTapImage: path != null && path.isNotEmpty
                ? () => _editImage(context, i, path)
                : null,
            onDeleteImage: path != null && path.isNotEmpty
                ? () => onChanged(i, null)
                : null,
          );
        }),
      ),
    );
  }
}

class _DashedPhotoSlot extends StatelessWidget {
  final String? imagePath;
  final VoidCallback onAdd;
  final VoidCallback? onTapImage;
  final VoidCallback? onDeleteImage;

  static const double size = 96;

  const _DashedPhotoSlot({
    this.imagePath,
    required this.onAdd,
    this.onTapImage,
    this.onDeleteImage,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasImage = imagePath != null && imagePath!.isNotEmpty;

    return GestureDetector(
      onTap: hasImage ? onTapImage : onAdd,
      child: SizedBox(
        width: size,
        height: size,
        child: hasImage
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(1),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(size * 0.15),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(File(imagePath!), fit: BoxFit.cover),
                          Container(
                            color: Colors.black.withValues(alpha: 0.12),
                            child: const Center(
                              child: Icon(
                                Icons.edit_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (onDeleteImage != null)
                    Positioned(
                      top: -8,
                      right: -8,
                      child: GestureDetector(
                        onTap: onDeleteImage,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              )
            : CustomPaint(
                painter: _DashedBorderPainter(
                  color: AppColors.primary.withValues(alpha: 0.45),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(size * 0.15),
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : AppColors.primary.withValues(alpha: 0.04),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.add_a_photo_outlined,
                          color: AppColors.primary,
                          size: size * 0.3,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Agregar',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
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

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final radius = size.shortestSide * 0.15;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      Radius.circular(radius),
    );

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final len = (distance + dashWidth < metric.length)
            ? dashWidth
            : metric.length - distance;
        canvas.drawPath(metric.extractPath(distance, distance + len), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
