import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/toast_helper.dart';
import '../services/storage_service.dart';

class OrderDetailModal extends StatefulWidget {
  final String codEnvio;
  final String fecEnvio;
  final String horaEnvio;
  final String nomLab;
  final String nomEmpTrans;
  final String estado;
  final int totalAnalisis;

  const OrderDetailModal({
    super.key,
    required this.codEnvio,
    required this.fecEnvio,
    required this.horaEnvio,
    required this.nomLab,
    required this.nomEmpTrans,
    required this.estado,
    required this.totalAnalisis,
  });

  @override
  State<OrderDetailModal> createState() => _OrderDetailModalState();
}

class _OrderDetailModalState extends State<OrderDetailModal> {
  String? _tipoReceptor;
  String _observaciones = '';
  // ignore: prefer_final_fields
  List<XFile> _selectedImages = [];
  bool _isLoading = false;

  // === Métodos de imagen ===
  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      try {
        debugPrint('Foto tomada, path original: ${pickedFile.path}');

        // Verificar que el archivo original existe
        final originalFile = File(pickedFile.path);
        if (!await originalFile.exists()) {
          debugPrint('Error: El archivo original no existe');
          if (mounted) {
            showErrorToast(context, 'Error: El archivo de la foto no se encontró');
          }
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final String fileName = 'camera_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final newPath = '${tempDir.path}/$fileName';

        debugPrint('Comprimiendo imagen a: $newPath');

        // Comprimir la imagen de la cámara (igual que la galería)
        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          pickedFile.path,
          newPath,
          quality: 85,
        );

        if (compressedFile != null) {
          final compressedFileObj = File(compressedFile.path);
          if (await compressedFileObj.exists()) {
            final fileSize = await compressedFileObj.length();
            debugPrint('Imagen comprimida exitosamente: ${compressedFile.path} (${fileSize} bytes)');

            setState(() {
              _selectedImages.add(XFile(compressedFile.path, name: fileName));
            });
            debugPrint('Total de imágenes seleccionadas: ${_selectedImages.length}');
          } else {
            debugPrint('Error: El archivo comprimido no existe después de la compresión');
            if (mounted) {
              showErrorToast(context, 'Error al procesar la foto.');
            }
          }
        } else {
          debugPrint('Error: La compresión retornó null');
          if (mounted) {
            showErrorToast(context, 'Error al procesar la foto.');
          }
        }
      } catch (e, stackTrace) {
        debugPrint('Error al procesar foto de cámara: $e');
        debugPrint('Stack trace: $stackTrace');
        if (mounted) {
          showErrorToast(context, 'Error al procesar la foto: ${e.toString()}');
        }
      }
    }
  }

Future<void> _pickImageFromGallery() async {
  final picker = ImagePicker();
  final pickedFiles = await picker.pickMultiImage(
    imageQuality: 85, // Compresión ligera
  );
  if (pickedFiles.isNotEmpty) {
    final tempDir = await getTemporaryDirectory();
    final List<XFile> validImages = [];

    for (var file in pickedFiles) {
      try {
        // Asegurar extensión válida
        String ext = '.jpg';
        if (file.name.toLowerCase().endsWith('.png')) {
          ext = '.png';
        } else if (file.name.toLowerCase().endsWith('.jpeg')) {
          ext = '.jpeg';
        }
        final String fileName = 'gallery_${DateTime.now().millisecondsSinceEpoch}_${validImages.length}$ext';
        final newPath = '${tempDir.path}/$fileName';

        final compressedFile = await FlutterImageCompress.compressAndGetFile(
          file.path,
          newPath,
          quality: 85,
        );

        if (compressedFile != null) {
          validImages.add(XFile(compressedFile.path, name: fileName));
        }
      } catch (e) {
        // Opcional: notificar error por archivo específico
        continue;
      }
    }

    if (validImages.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(validImages);
      });
    }
  }
}

Future<void> _removeImage(int index) async {
  setState(() {
    _selectedImages.removeAt(index);
  });
}

  // === Envío ===
  Future<void> _recepcionarOrden() async {
    if (_tipoReceptor == null || _tipoReceptor!.isEmpty) {
      showErrorToast(context, 'Seleccione quién realiza la recepción');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uri = Uri.parse(
        '${AppConstants.baseUrl}/modules/tracking/escaneo/recepcionar_orden.php',
      );
      final request = http.MultipartRequest('POST', uri);
      final storageService = Provider.of<StorageService>(context, listen: false);
      final userName = storageService.getUserName() ?? 'app_movil';
      request.fields['codEnvio'] = widget.codEnvio;
      request.fields['obs'] = _observaciones;
      request.fields['tipoReceptor'] = _tipoReceptor!;
      request.fields['usuario'] = userName;

      // Validar y agregar imágenes
      debugPrint('Preparando ${_selectedImages.length} imágenes para enviar');

      for (var image in _selectedImages) {
        final file = File(image.path);

        debugPrint('Verificando imagen: ${image.name} - Path: ${image.path}');

        // Verificar que el archivo existe y tiene tamaño válido
        if (await file.exists()) {
          final fileSize = await file.length();
          debugPrint('Archivo existe, tamaño: $fileSize bytes');

          if (fileSize == 0) {
            debugPrint('ADVERTENCIA: Archivo vacío: ${image.path}');
            continue;
          }

          try {

            final multipartFile = await http.MultipartFile.fromPath(
              'evidencias[]',
              image.path,
              filename: image.name,
            );
            request.files.add(multipartFile);
            debugPrint('✓ Imagen agregada al request: ${image.name} (${fileSize} bytes)');
          } catch (e, stackTrace) {
            debugPrint('✗ Error al agregar imagen ${image.name}: $e');
            debugPrint('Stack trace: $stackTrace');
            if (mounted) {
              showErrorToast(context, 'Error al procesar imagen: ${image.name}');
            }
          }
        } else {
          debugPrint('✗ Archivo NO existe: ${image.path}');
          if (mounted) {
            showErrorToast(context, 'La imagen ${image.name} no se encontró');
          }
        }
      }

      debugPrint('Total de imágenes a enviar: ${request.files.length}');
      debugPrint('Campos del request: ${request.fields}');

      // Verificar que hay imágenes antes de enviar
      if (request.files.isEmpty && _selectedImages.isNotEmpty) {
        if (mounted) {
          showErrorToast(context, 'Error: No se pudieron cargar las imágenes');
        }
        setState(() => _isLoading = false);
        return;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.body}');
      final data = jsonDecode(response.body);
      if (data['ok'] == true) {
        final Map<String, dynamic> localData = {
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
          'codEnvio': widget.codEnvio,
          'fecEnvio': widget.fecEnvio,
          'horaEnvio': widget.horaEnvio,
          'nomLab': widget.nomLab,
          'tipoReceptor': _tipoReceptor,
          'observaciones': _observaciones,
          'fechaHoraRegistro': DateTime.now().toString(),
          'synced': true, // Ya se envió al servidor
        };
        await storageService.saveForm(AppStrings.formTypeTracking, localData);
        if (mounted) {

          showSuccessToast(context, 'Orden recepcionada correctamente');
          Navigator.of(context).pop(true);
        }
      } else {
        if (mounted) {
          showErrorToast(context, data['mensaje']);
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Error al recepcionar la orden.}');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // === Build ===
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FD),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            onTap: () => FocusScope.of(
              context,
            ).unfocus(), // cierra teclado al tocar fuera
            onVerticalDragEnd: (details) {
              // Cerrar el modal si se desliza hacia abajo con suficiente velocidad
              if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
                Navigator.of(context).pop(false);
              }
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                // Detectar cuando el scroll está en la parte superior (pixels <= 0) y se intenta deslizar hacia abajo
                if (notification is ScrollUpdateNotification) {
                  final metrics = notification.metrics;
                  if (metrics.pixels <= 0 &&
                      notification.scrollDelta != null &&
                      notification.scrollDelta! > 0) {
                    // Si está en la parte superior y se desliza hacia abajo, cerrar
                    Navigator.of(context).pop(false);
                    return true;
                  }
                }
                return false;
              },
              child: SingleChildScrollView(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 12,
                bottom: MediaQuery.of(context).viewInsets.bottom > 0
                    ? 16 // espacio fijo cuando el teclado está activo
                    : 16 + 16, // espacio normal + margen inferior
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // === Handle / Grippy (arrastrable) ===
                      GestureDetector(
                        onVerticalDragEnd: (details) {
                          // Cerrar el modal si se desliza el handle hacia abajo
                          if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
                            Navigator.of(context).pop(false);
                          }
                        },
                        child: Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // === Título ===
                      const Text(
                        'Detalle de la orden de envío',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.codEnvio,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // === Información de la orden ===
                      Wrap(
                        spacing: 24,
                        runSpacing: 10,
                        children: [
                          _buildInfoItem('Fecha de envío:', widget.fecEnvio),
                          _buildInfoItem('Hora de envío:', widget.horaEnvio),
                          _buildInfoItem('Laboratorio:', widget.nomLab),
                          _buildInfoItem(
                            'Análisis registrados:',
                            widget.totalAnalisis.toString(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // === Selector de receptor ===
                      const Text(
                        '¿Quién está realizando la recepción?',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _tipoReceptor,
                        onChanged: (value) =>
                            setState(() => _tipoReceptor = value),
                        decoration: _inputDecoration,
                        items: const [
                          DropdownMenuItem(
                            value: '',
                            child: Text('Seleccione una opción'),
                          ),
                          DropdownMenuItem(
                            value: 'Transporte',
                            child: Text('Transportista'),
                          ),
                          DropdownMenuItem(
                            value: 'Laboratorio',
                            child: Text('Laboratorio'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // === Evidencia fotográfica ===
                      const Text(
                        'Evidencia fotográfica (opcional)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_selectedImages.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: List.generate(_selectedImages.length, (
                              index,
                            ) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.file(
                                      File(_selectedImages[index].path),
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: -6,
                                    right: -6,
                                    child: GestureDetector(
                                      onTap: () => _removeImage(index),
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
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
                              );
                            }),
                          ),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _takePhoto,
                              icon: const Icon(Icons.camera_alt, size: 18),
                              label: const Text('Tomar foto'),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFFD0D7E3),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickImageFromGallery,
                              icon: const Icon(Icons.image, size: 18),
                              label: const Text('Desde galería'),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0xFFD0D7E3),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // === Observaciones ===
                      const Text(
                        'Observaciones',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        maxLines: 3,
                        onChanged: (value) => _observaciones = value,
                        decoration: _inputDecoration.copyWith(
                          hintText: 'Ingrese alguna observación (opcional)',
                        ),
                      ),
                      const SizedBox(height: 24),

                      // === Botones de acción ===
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F9FD),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context, false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade200,
                                  foregroundColor: Colors.black,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: const Text('Cancelar'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _isLoading
                                    ? null
                                    : _recepcionarOrden,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF667EEA),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                child: _isLoading
                                    ? const CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      )
                                    : const Text('Recepcionar'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  // === Estilo común para inputs ===
  InputDecoration get _inputDecoration => InputDecoration(
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD0D7E3), width: 1),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFD0D7E3), width: 1),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF667EEA), width: 2),
    ),
  );

  // === Item de información ===
  Widget _buildInfoItem(String label, String value) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48 - 24) / 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Colors.black,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}
