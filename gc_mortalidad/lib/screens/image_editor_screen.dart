import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditorScreen extends StatefulWidget {
  final XFile imageFile;

  const ImageEditorScreen({super.key, required this.imageFile});

  @override
  State<ImageEditorScreen> createState() => _ImageEditorScreenState();
}

class _ImageEditorScreenState extends State<ImageEditorScreen> {
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldClose = await showDialog<bool>(
          context: context,
          builder: (ctx) {
            final isDark = Theme.of(ctx).brightness == Brightness.dark;
            return AlertDialog(
            backgroundColor: isDark ? AppColors.darkCard : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('¿Cerrar editor?'),
            content: const Text('Los cambios no guardados se perderán.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Descartar'),
              ),
            ],
          );
          },
        );
        if (shouldClose == true && mounted) {
          Navigator.of(context).pop(null);
        }
      },
      child: Scaffold(
        body: ProImageEditor.file(
          File(widget.imageFile.path),
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {
              if (!mounted) return;
              try {
                final dir = await getApplicationDocumentsDirectory();
                final imagesDir = Directory('${dir.path}/mortalidad_images');
                if (!imagesDir.existsSync()) {
                  imagesDir.createSync(recursive: true);
                }
                final path =
                    '${imagesDir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.jpg';
                final file = File(path);
                await file.writeAsBytes(bytes);
                if (!mounted) return;
                Navigator.of(context).pop(XFile(path));
              } catch (_) {
                if (mounted) Navigator.of(context).pop(null);
              }
            },
          ),
          configs: ProImageEditorConfigs(
            i18n: const I18n(
              cancel: 'Cancelar',
              done: 'Guardar',
              remove: 'Eliminar',
              doneLoadingMsg: 'Guardando cambios...',
            ),
          ),
        ),
      ),
    );
  }
}
