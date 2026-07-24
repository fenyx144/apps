import 'dart:io';
import 'package:flutter/material.dart';
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
          builder: (ctx) => AlertDialog(
            title: const Text('¿Cerrar editor?'),
            content: const Text(
              'Los cambios no guardados se perderán. ¿Descartar cambios y salir?',
            ),
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
          ),
        );
        if (shouldClose == true && mounted) {
          Navigator.of(context).pop(null);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: ProImageEditor.file(
          File(widget.imageFile.path),
          callbacks: ProImageEditorCallbacks(
            onImageEditingComplete: (bytes) async {
              if (!mounted) return;
              try {
                final dir = await getApplicationDocumentsDirectory();
                final imagesDir = Directory('${dir.path}/sc_images');
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
            i18n: I18n(
              cancel: 'Cancelar',
              done: 'Guardar',
              remove: 'Eliminar',
              doneLoadingMsg: 'Guardando cambios...',
              paintEditor: I18nPaintEditor(
                bottomNavigationBarText: 'Dibujar',
                back: 'Atrás',
                done: 'Listo',
                undo: 'Deshacer',
                redo: 'Rehacer',
                freestyle: 'Lápiz',
                arrow: 'Flecha',
                line: 'Línea',
                rectangle: 'Rectángulo',
                circle: 'Círculo',
                dashLine: 'Línea punteada',
                eraser: 'Borrador',
                changeOpacity: 'Cambiar opacidad',
                smallScreenMoreTooltip: 'Más',
                lineWidth: 'Tamaño de línea',
              ),
              textEditor: I18nTextEditor(
                bottomNavigationBarText: 'Texto',
                back: 'Atrás',
                done: 'Listo',
                inputHintText: 'Escribe tu texto',
                textAlign: 'Alineación',
                backgroundMode: 'Modo fondo',
                fontScale: 'Tamaño de fuente',
              ),
              cropRotateEditor: I18nCropRotateEditor(
                bottomNavigationBarText: 'Recortar',
                back: 'Atrás',
                done: 'Listo',
                rotate: 'Rotar',
                ratio: 'Proporción',
                flip: 'Voltear',
                cancel: 'Cancelar',
                reset: 'Restablecer',
                undo: 'Deshacer',
                redo: 'Rehacer',
              ),
              filterEditor: I18nFilterEditor(
                bottomNavigationBarText: 'Filtros',
                back: 'Atrás',
                done: 'Listo',
                filters: I18nFilters(none: 'Sin filtro'),
              ),
              blurEditor: I18nBlurEditor(
                bottomNavigationBarText: 'Desenfocar',
                back: 'Atrás',
                done: 'Listo',
              ),
              emojiEditor: I18nEmojiEditor(
                bottomNavigationBarText: 'Emoji',
              ),
              stickerEditor: I18nStickerEditor(
                bottomNavigationBarText: 'Stickers',
              ),
              various: I18nVarious(
                loadingDialogMsg: 'Cargando...',
                closeEditorWarningTitle: '¿Cerrar editor?',
                closeEditorWarningMessage: 'Los cambios no guardados se perderán',
                closeEditorWarningConfirmBtn: 'Cerrar',
                closeEditorWarningCancelBtn: 'Cancelar',
              ),
            ),
            paintEditor: PaintEditorConfigs(
              enabled: true,
              showOpacityAdjustmentButton: false,
              showToggleFillButton: false,
              tools: const [
                PaintMode.moveAndZoom,
                PaintMode.freeStyle,
                PaintMode.arrow,
                PaintMode.line,
                PaintMode.rect,
                PaintMode.circle,
                PaintMode.eraser,
              ],
            ),
            textEditor: const TextEditorConfigs(enabled: true),
            cropRotateEditor: const CropRotateEditorConfigs(enabled: true),
            tuneEditor: const TuneEditorConfigs(enabled: false),
            filterEditor: const FilterEditorConfigs(enabled: false),
            blurEditor: const BlurEditorConfigs(enabled: false),
            emojiEditor: const EmojiEditorConfigs(enabled: false),
            stickerEditor: const StickerEditorConfigs(enabled: false),
          ),
        ),
      ),
    );
  }
}
