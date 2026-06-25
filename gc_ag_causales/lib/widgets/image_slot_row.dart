import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../screens/image_editor_screen.dart';
import '../utils/constants.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';

class ImageSlotRow extends StatelessWidget {
  final List<String?> paths;
  final void Function(int index, String? path) onChanged;

  const ImageSlotRow({
    super.key,
    required this.paths,
    required this.onChanged,
  });

  Future<XFile> _copyToTemp(XFile picked, int index) async {
    try {
      final bytes = await picked.readAsBytes();
      final tempDir = await getTemporaryDirectory();
      final ext = path.extension(picked.path).isEmpty
          ? '.jpg'
          : path.extension(picked.path);
      final tempPath = path.join(
        tempDir.path,
        'ag_causales_${DateTime.now().millisecondsSinceEpoch}_$index$ext',
      );
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);
      return XFile(tempPath);
    } catch (_) {
      return picked;
    }
  }

  Future<XFile?> _openEditor(BuildContext context, XFile imageFile) {
    return Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(imageFile: imageFile),
      ),
    );
  }

  Future<bool?> _askEdit(BuildContext context) {
    return showAppDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).brightness == Brightness.dark
            ? null
            : AppColors.dialogBackground,
        title: Text(
          '¿Editar imagen?',
          style: TextStyle(color: ctx.textThemePrimary),
        ),
        content: Text(
          '¿Deseas recortar, agregar texto o dibujar sobre la imagen?',
          style: TextStyle(color: ctx.textThemePrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'No, usar tal cual',
              style: TextStyle(color: ctx.textThemeMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Sí, editar'),
          ),
        ],
      ),
    );
  }

  Future<void> _processPickedImage(
    BuildContext context,
    int index,
    XFile picked,
  ) async {
    var imageFile = await _copyToTemp(picked, index);

    final shouldEdit = await _askEdit(context);
    if (!context.mounted) return;

    if (shouldEdit == true) {
      var currentFile = imageFile;
      var done = false;
      while (!done && context.mounted) {
        final result = await _openEditor(context, currentFile);
        if (!context.mounted) return;
        if (result != null) {
          onChanged(index, result.path);
          done = true;
        } else {
          final again = await _askEdit(context);
          if (!context.mounted) return;
          if (again != true) {
            done = true;
            if (again == false) {
              onChanged(index, currentFile.path);
            }
          }
        }
      }
    } else if (shouldEdit == false) {
      onChanged(index, imageFile.path);
    }
  }

  Future<void> _pickNew(BuildContext context, int index) async {
    final source = await showAppDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Seleccionar imagen',
          style: TextStyle(color: ctx.textThemePrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.iconAccent),
              title: Text('Cámara', style: TextStyle(color: ctx.textThemePrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.iconAccent),
              title: Text('Galería', style: TextStyle(color: ctx.textThemePrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null || !context.mounted) return;

    await _processPickedImage(context, index, picked);
  }

  Future<void> _onSlotTap(BuildContext context, int index) async {
    final existing = index < paths.length ? paths[index] : null;
    final hasImage = existing != null && existing.isNotEmpty;

    if (hasImage) {
      final result = await _openEditor(context, XFile(existing));
      if (result != null && context.mounted) {
        onChanged(index, result.path);
      }
    } else {
      await _pickNew(context, index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF757575)
        : const Color(0xFFBDBDBD);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (i) {
        final path = i < paths.length ? paths[i] : null;
        final hasImage = path != null && path.isNotEmpty;

        return GestureDetector(
          onTap: () => _onSlotTap(context, i),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: hasImage
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(File(path), fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () => onChanged(i, null),
                          child: Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(
                        color: AppColors.iconAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
          ),
        );
      }),
    );
  }
}
