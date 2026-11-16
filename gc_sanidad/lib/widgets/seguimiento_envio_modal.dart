// lib/widgets/seguimiento_envio_modal.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/constants.dart';

class SeguimientoEnvioModal extends StatefulWidget {
  final Map<String, dynamic> envio;
  final List<dynamic> historial;

  const SeguimientoEnvioModal({
    super.key,
    required this.envio,
    required this.historial,
  });

  @override
  State<SeguimientoEnvioModal> createState() => _SeguimientoEnvioModalState();
}

class _SeguimientoEnvioModalState extends State<SeguimientoEnvioModal> {
  (String, Color, Color) _getEstadoStyle(String estado) {
    final lower = estado.toLowerCase();
    if (lower.contains('pendiente')) {
      return ('Pendiente', Colors.yellow.shade100, Colors.yellow.shade800);
    } else if (lower.contains('finalizado') || lower.contains('emitido')) {
      return ('Finalizado', Colors.green.shade100, Colors.green.shade800);
    } else {
      return ('En Proceso', Colors.blue.shade100, Colors.blue.shade800);
    }
  }

  List<List<Map<String, dynamic>>> _agruparHistorialPorPaso() {
    final pasos = List.generate(4, (_) => <Map<String, dynamic>>[]);

    for (var evento in widget.historial) {
      int paso = 0;
      final ubicacion = (evento['ubicacion'] as String?)?.trim() ?? '';
      final accion = (evento['accion'] as String?)?.toLowerCase() ?? '';

      if (ubicacion == 'GRS') {
        paso = 0;
      } else if (ubicacion == 'Transporte') {
        paso = 1;
      } else if (ubicacion == 'Laboratorio') {
        if (accion.contains('registro_resultados_cualitativos') ||
            accion.contains('registro_resultados_cuantitativos')) {
          paso = 3;
        } else {
          paso = 2;
        }
      }

      if (paso >= 0 && paso < 4) {
        pasos[paso].add(evento);
      }
    }
    return pasos;
  }

  List<String> _parseEvidencias(String? evidencia) {
    if (evidencia == null || evidencia.trim().isEmpty) return [];
    return evidencia
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Widget _buildEvento(BuildContext context, Map<String, dynamic> evento) {
    String accion = evento['accion'] ?? 'Acción registrada';
    if (accion == 'ENVIO_REGISTRADO')
      accion = 'Envío Registrado';
    else if (accion == 'Recepción de muestra')
      accion = 'Recepción por transportista';
    else if (accion == 'Recepción de muestra por laboratorio')
      accion = 'Recepcionado por laboratorio';
    else if (accion.toLowerCase().contains('registro_resultados_cualitativos'))
      accion = 'Resultados cualitativos registrados';
    else if (accion.toLowerCase().contains('registro_resultados_cuantitativos'))
      accion = 'Resultados cuantitativos registrados';

    final evidencias = _parseEvidencias(evento['evidencia']);
    print(evidencias);
    final tieneEvidencia = evidencias.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD0D7E3)),
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tieneEvidencia)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: List.generate(evidencias.length, (i) {
                return GestureDetector(
                  onTap: () => _mostrarCarrusel(context, evidencias, i),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: const Color(0xFF667EEA),
                        width: 1,
                      ),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: '${AppConstants.baseUrl}/${evidencias[i]}',
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.broken_image,
                        size: 20,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                );
              }),
            ),
          const SizedBox(height: 6),
          Text(
            accion,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
              fontSize: 13,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis, // Cambiado de fade a ellipsis
          ),
          if ((evento['comentario'] as String?)?.isNotEmpty == true)
            Text(
              evento['comentario']!,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis, // Cambiado de fade a ellipsis
            ),
          Text(
            '${evento['fechaHoraRegistro']} · ${evento['ubicacion'] ?? '—'} · ${evento['usuario'] ?? '—'}',
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis, // Cambiado de fade a ellipsis
          ),
        ],
      ),
    );
  }

  void _mostrarCarrusel(
  BuildContext context,
  List<String> rutas,
  int indiceInicial,
) {
  final imagenes = rutas.map((r) => '${AppConstants.baseUrl}/$r').toList();
  showDialog(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Carrusel de imágenes
          SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: PageView.builder(
              itemCount: imagenes.length,
              controller: PageController(initialPage: indiceInicial),
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.all(16),
                  child: InteractiveViewer(
                    child: CachedNetworkImage(
                      imageUrl: imagenes[index],
                      fit: BoxFit.contain,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.error, size: 60, color: Colors.red),
                    ),
                  ),
                );
              },
            ),
          ),

          // Botón de cerrar (X) en la esquina superior derecha
          Positioned(
            top: 40,
            right: 20,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(), // Cierra el diálogo
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    final (estadoTexto, bgColor, textColor) = _getEstadoStyle(widget.envio['estado']);
    final pasosHistorial = _agruparHistorialPorPaso();

    return GestureDetector(
      onVerticalDragEnd: (details) {
        // Cerrar el modal si se desliza hacia abajo con suficiente velocidad
        if (details.primaryVelocity != null && details.primaryVelocity! > 300) {
          Navigator.of(context).pop();
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
              Navigator.of(context).pop();
              return true;
            }
          }
          return false;
        },
        child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF5F9FD),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // === Handle (arrastrable) ===
            GestureDetector(
              onVerticalDragEnd: (details) {
                // Cerrar el modal si se desliza el handle hacia abajo
                if (details.primaryVelocity != null && details.primaryVelocity! > 200) {
                  Navigator.of(context).pop();
                }
              },
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
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
            ),

          // === Título + Estado ===
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Seguimiento del envío',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    estadoTexto,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // === Contenido scrollable ===
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.envio['codEnvio'],
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 20),

                  // === Resumen ===
                  Wrap(
                    spacing: 20,
                    runSpacing: 16,
                    children: [
                      _buildResumenItem(
                        context,
                        Icons.description,
                        'Código',
                        widget.envio['codEnvio'],
                      ),
                      _buildResumenItem(
                        context,
                        Icons.calendar_today,
                        'Fecha',
                        '${widget.envio['fecEnvio']} ${widget.envio['horaEnvio']}',
                      ),
                      _buildResumenItem(
                        context,
                        Icons.science,
                        'Laboratorio',
                        widget.envio['nomLab'],
                      ),
                      _buildResumenItem(
                        context,
                        Icons.local_shipping,
                        'Transporte',
                        widget.envio['nomEmpTrans'],
                      ),
                      _buildResumenItem(
                        context,
                        Icons.vaccines,
                        'Análisis',
                        '${widget.envio['totalAnalisis']}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // === Progreso ===
                  const Text(
                    'Seguimiento',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 12),

                  ...List.generate(4, (i) {
                    final pasoNombres = [
                      'GRS',
                      'Transporte',
                      'Laboratorio',
                      'Finalizado',
                    ];
                    final pasoDescripciones = [
                      'Solicitud creada',
                      'Recibido por transportista',
                      'Muestra recibida',
                      'Resultados emitidos',
                    ];
                    return _buildPasoItem(
                      context,
                      i,
                      pasoNombres[i],
                      pasoDescripciones[i],
                      pasosHistorial[i],
                    );
                  }),
                ],
              ),
            ),
          ),

          // === Pie del modal (como en OrderDetailModal) ===
          Container(
            padding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 12,
            ),
            color: const Color(0xFFF5F9FD),
            child: Center(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFD0D7E3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                ),
                child: const Text('Cerrar', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ],
        ),
        ),
      ),
    );
  }

  Widget _buildResumenItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return SizedBox(
      width: (MediaQuery.of(context).size.width - 48 - 20) / 2,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF667EEA),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis, // Cambiado de fade a ellipsis
                ),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis, // Cambiado de fade a ellipsis
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

 Widget _buildPasoItem(
  BuildContext context,
  int index,
  String titulo,
  String descripcion,
  List<Map<String, dynamic>> eventos,
) {
  final isActive = eventos.isNotEmpty;
  final colorFondo = isActive
      ? const Color(0xFF667EEA)
      : Colors.grey.shade200;
  final colorIcono = isActive ? Colors.white : Colors.grey.shade600;

  IconData icono;
  switch (index) {
    case 0:
      icono = Icons.description;
      break;
    case 1:
      icono = Icons.local_shipping;
      break;
    case 2:
      icono = Icons.science;
      break;
    case 3:
      icono = Icons.check_circle;
      break;
    default:
      icono = Icons.info;
  }

  return Column(
    children: [
      // Contenedor centrado para el icono y textos
      Center(
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: colorFondo,
              child: Icon(icono, color: colorIcono, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            Text(
              descripcion,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (eventos.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: eventos.map((e) => _buildEvento(context, e)).toList(),
        ),
    ],
  );
}
}
