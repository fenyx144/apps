// widgets/solicitud_muestra_card.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/registro_envio_muestra_controller.dart';
import '../widgets/reference_code_input.dart';

import '../utils/constants.dart';

class SolicitudMuestraCard extends StatefulWidget {
  final int index;
  final VoidCallback? onEliminar;
  const SolicitudMuestraCard({
    super.key,
    required this.index,
    this.onEliminar,
  });

  @override
  State<SolicitudMuestraCard> createState() => _SolicitudMuestraCardState();
}

class _SolicitudMuestraCardState extends State<SolicitudMuestraCard> {
  TextEditingController _obsController = TextEditingController();
  TextEditingController _edadController = TextEditingController();
  final FocusNode _obsFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final controller = context.read<RegistroEnvioMuestraController>();
    final muestra = controller.solicitudes[widget.index];
    _obsController.text = muestra.observaciones;
    _edadController.text = muestra.edad;
    if (muestra.origenMuestra == 'EXTERNO' ||
        muestra.origenMuestra == 'TRASPATIO') {
      controller.cargarCodigosOrigen(muestra.origenMuestra);
    }
  }

  @override
  void dispose() {
    _obsFocusNode.dispose();
    _edadController.dispose();
    _obsController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SolicitudMuestraCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Si el índice cambió, significa que ahora representa otra solicitud
    if (oldWidget.index != widget.index) {
      // Desenfocar cualquier TextField activo
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RegistroEnvioMuestraController>();
    final muestra = controller.solicitudes[widget.index];
    final config = controller.getConfiguracion(widget.index);
    final longitudCodigo = controller.getLongitudCodigoReferencia(widget.index);
    final esExterno = controller.esOrigenExterno(widget.index);

    if (_obsController.text != muestra.observaciones) {
      _obsController.text = muestra.observaciones;
    }
    if (_edadController.text != muestra.edad) {
      _edadController.text = muestra.edad;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Solicitud #${widget.index + 1}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (controller.numeroSolicitudes > 1 && widget.onEliminar != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  tooltip: 'Eliminar solicitud',
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                  onPressed: widget.onEliminar,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildCompactDateField(context, controller, muestra),
          const SizedBox(height: 8),
          if (controller.tiposMuestra.isNotEmpty)
            _buildModalSelector(
              label: 'Tipo de Muestra *',
              selectedCodigo: muestra.tipoMuestraCodigo,
              items: controller.tiposMuestra,
              dialogTitle: 'Seleccionar Tipo de Muestra',
              searchable: true,
              onChanged: (datos) {
                controller.setTipoMuestra(
                  widget.index,
                  datos['codigo']?.toString(),
                  datos['nombre']?.toString(),
                );
              },
            ),
          const SizedBox(height: 8),
          _buildCompactDropdown(
            label: 'Origen *',
            value: muestra.origenMuestra,
            items: const [
              {'codigo': 'GRS', 'nombre': 'GRS'},
              {'codigo': 'EXTERNO', 'nombre': 'Externo'},
              {'codigo': 'TRASPATIO', 'nombre': 'Traspatio'},
            ],
            onChanged: (datos) {
              controller.setOrigenMuestra(
                widget.index,
                datos['codigo']?.toString() ?? 'GRS',
              );
            },
          ),
          const SizedBox(height: 12),
          if (!esExterno && longitudCodigo > 0)
            _buildCodigoReferenciaGrs(
              controller: controller,
              muestra: muestra,
              longitudCodigo: longitudCodigo,
            )
          else if (esExterno)
            _buildCodigoReferenciaExterno(
              controller: controller,
              muestra: muestra,
            ),
          if ((!esExterno && longitudCodigo > 0) || esExterno)
            const SizedBox(height: 12),
          if (muestra.tipoMuestraCodigo != null &&
              muestra.tipoMuestraCodigo!.isNotEmpty) ...[
            _buildCantidadSection(controller, muestra),
          ],
          if (controller.necesitaGri(widget.index)) ...[
            const SizedBox(height: 12),
            _buildGriSection(controller, muestra),
          ],
          if (config != null) ...[
            const SizedBox(height: 12),
            _buildAnalisisSection(
              controller: controller,
              index: widget.index,
              config: config,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _obsController,
            focusNode: _obsFocusNode,
            maxLines: 2,
            decoration: _compactDecoration('Observaciones'),
            onChanged: (v) {
              controller.setObservaciones(widget.index, v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDateField(
    BuildContext context,
    RegistroEnvioMuestraController controller,
    dynamic muestra,
  ) {
    final display = muestra.fechaToma?.split('-').reversed.join('-') ?? '';
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate:
              DateTime.tryParse(muestra.fechaToma ?? '') ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2030),
        );
        if (picked != null) {
          controller.setFechaToma(
            widget.index,
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}',
          );
        }
      },
      child: InputDecorator(
        decoration: _compactDecoration('F. de Toma *'),
        child: Text(display.isEmpty ? 'Seleccione' : display),
      ),
    );
  }

  Widget _buildModalSelector({
    required String label,
    required String? selectedCodigo,
    required List<Map<String, dynamic>> items,
    required String dialogTitle,
    required ValueChanged<Map<String, dynamic>> onChanged,
    bool searchable = false,
  }) {
    final nombre = _nombreFromCodigo(items, selectedCodigo);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showCatalogDialog(
        title: dialogTitle,
        items: items,
        selectedCodigo: selectedCodigo,
        searchable: searchable,
        onSelected: onChanged,
      ),
      child: InputDecorator(
        decoration: _compactDecoration(label),
        child: Text(
          nombre.isEmpty ? 'Seleccionar...' : nombre,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  String _nombreFromCodigo(
    List<Map<String, dynamic>> items,
    String? codigo,
  ) {
    if (codigo == null || codigo.isEmpty) return '';
    for (final item in items) {
      if (item['codigo']?.toString() == codigo) {
        return item['nombre']?.toString() ?? '';
      }
    }
    return '';
  }

  void _showCatalogDialog({
    required String title,
    required List<Map<String, dynamic>> items,
    required String? selectedCodigo,
    required ValueChanged<Map<String, dynamic>> onSelected,
    bool searchable = false,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        final searchController = TextEditingController();
        var filtered = List<Map<String, dynamic>>.from(items);

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text(title),
              content: SizedBox(
                width: double.maxFinite,
                height: searchable ? 320 : 240,
                child: Column(
                  children: [
                    if (searchable) ...[
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          hintText: 'Buscar...',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (query) {
                          setDialogState(() {
                            filtered = items
                                .where(
                                  (item) => (item['nombre']?.toString() ?? '')
                                      .toLowerCase()
                                      .contains(query.toLowerCase()),
                                )
                                .toList();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    Expanded(
                      child: filtered.isEmpty
                          ? const Center(child: Text('Sin resultados'))
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final item = filtered[index];
                                final codigo = item['codigo'].toString();
                                final nombre =
                                    item['nombre']?.toString() ?? codigo;
                                return ListTile(
                                  title: Text(nombre),
                                  selected: selectedCodigo == codigo,
                                  selectedTileColor:
                                      Colors.blue.withOpacity(0.1),
                                  onTap: () {
                                    onSelected(item);
                                    Navigator.pop(ctx);
                                    FocusScope.of(context).unfocus();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    FocusScope.of(context).unfocus();
                  },
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCompactDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<Map<String, dynamic>> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: (value != null && value.isNotEmpty) ? value : null,
      decoration: _compactDecoration(label),
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: e['codigo']?.toString(),
              child: Text(
                e['nombre']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          )
          .toList(),
      selectedItemBuilder: (context) => items
          .map(
            (e) => Align(
              alignment: Alignment.centerLeft,
              child: Text(
                e['nombre']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        final item = items.firstWhere(
          (e) => e['codigo']?.toString() == v,
          orElse: () => {'codigo': v, 'nombre': v},
        );
        onChanged(item);
      },
    );
  }

  Widget _buildCantidadSection(
    RegistroEnvioMuestraController controller,
    dynamic muestra,
  ) {
    return TextFormField(
      initialValue: muestra.numeroMuestras.toString(),
      keyboardType: TextInputType.number,
      decoration: _compactDecoration('N° de Muestras *'),
      onChanged: (v) {
        final num = int.tryParse(v);
        if (num != null && num >= 1) {
          controller.setNumeroMuestras(widget.index, num);
        }
      },
    );
  }

  InputDecoration _compactDecoration(String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      filled: true,
      fillColor: AppColors.cardBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF667EEA), width: 1.5),
      ),
    );
  }

  Widget _buildGriSection(
    RegistroEnvioMuestraController controller,
    dynamic muestra,
  ) {
    final opciones = controller.getGriOpciones(widget.index);
    final items = opciones
        .map(_griDropdownItem)
        .where((item) => item.value != null && item.value!.isNotEmpty)
        .toList();
    final selected = _resolveGriValue(muestra.griSeleccion, opciones);

    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: selected,
      decoration: _compactDecoration('GRI *').copyWith(
        suffixIcon: controller.cargandoGri
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      hint: Text(
        controller.cargandoGri
            ? 'Cargando GRI...'
            : (opciones.isEmpty
                ? 'Complete código referencia'
                : 'Seleccione GRI'),
      ),
      items: items,
      onChanged: items.isEmpty || controller.cargandoGri
          ? null
          : (v) => controller.setGriSeleccion(widget.index, v),
    );
  }

  DropdownMenuItem<String> _griDropdownItem(Map<String, dynamic> item) {
    return DropdownMenuItem<String>(
      value: _griOptionValue(item),
      child: Text(
        _griOptionLabel(item),
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
        maxLines: 2,
      ),
    );
  }

  String _griOptionValue(Map<String, dynamic> item) =>
      '${item['tdoc'] ?? ''}|${item['tserie'] ?? ''}|${item['tnumfac'] ?? ''}';

  String? _resolveGriValue(
    String griSeleccion,
    List<Map<String, dynamic>> opciones,
  ) {
    if (griSeleccion.isEmpty || opciones.isEmpty) return null;
    for (final item in opciones) {
      if (_griOptionValue(item) == griSeleccion) return griSeleccion;
    }
    return null;
  }

  String _griOptionLabel(Map<String, dynamic> item) {
    final label = item['label']?.toString();
    if (label != null && label.isNotEmpty) return label;
    final cod = item['codigoGri']?.toString() ??
        '${item['tserie'] ?? ''}-${item['tnumfac'] ?? ''}';
    var fec = item['tfectra']?.toString() ?? '';
    if (fec.contains('-') && fec.length >= 10) {
      final p = fec.split('-');
      if (p.length >= 3) fec = '${p[2]}/${p[1]}/${p[0]}';
    }
    final parts = <String>[];
    final m = (item['tcantidM'] as num?)?.toDouble() ?? 0;
    final h = (item['tcantidH'] as num?)?.toDouble() ?? 0;
    if (m > 0) parts.add('M: ${m == m.roundToDouble() ? m.toInt() : m}');
    if (h > 0) parts.add('H: ${h == h.roundToDouble() ? h.toInt() : h}');
    final cantStr = parts.join(', ');
    return cantStr.isNotEmpty ? '$cod | $fec | $cantStr' : '$cod | $fec';
  }

  Widget _buildCodigoReferenciaGrs({
    required RegistroEnvioMuestraController controller,
    required dynamic muestra,
    required int longitudCodigo,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Código de Referencia *',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ReferenceCodeInput(
          length: longitudCodigo,
          value: muestra.codigoReferencia,
          onChanged: (value) {
            controller.setCodigoReferencia(widget.index, value);
          },
        ),
      ],
    );
  }

  Widget _buildCodigoReferenciaExterno({
    required RegistroEnvioMuestraController controller,
    required dynamic muestra,
  }) {
    final codigos = controller.getCodigosOrigen(muestra.origenMuestra);
    final labelCodigo = muestra.origenMuestra == 'EXTERNO'
        ? 'Código Externo *'
        : 'Código Traspatio *';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: _buildModalSelector(
            label: labelCodigo,
            selectedCodigo: muestra.codigoReferencia.isEmpty
                ? null
                : muestra.codigoReferencia,
            items: codigos
                .map(
                  (item) => {
                    'codigo': item['codigo'].toString(),
                    'nombre': item['codigo'].toString(),
                  },
                )
                .toList(),
            dialogTitle: labelCodigo,
            searchable: true,
            onChanged: (datos) {
              controller.setCodigoReferencia(
                widget.index,
                datos['codigo'] ?? '',
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: _edadController,
            keyboardType: TextInputType.number,
            decoration: _compactDecoration('Edad'),
            onChanged: (v) {
              controller.setEdad(widget.index, v);
            },
          ),
        ),
      ],
    );
  }

  String _buscarCodigoPaquete(
    List<Map<String, dynamic>> paquetes,
    String nombrePaquete,
  ) {
    final paquete = paquetes.firstWhere(
      (p) => p['nombre'] == nombrePaquete,
      orElse: () => {'codigo': ''},
    );
    return paquete['codigo'].toString();
  }

  Widget _buildAnalisisSection({
    required RegistroEnvioMuestraController controller,
    required int index,
    required ConfiguracionMuestra config,
  }) {
    final Map<String, List<Map<String, dynamic>>> analisisPorPaquete = {};
    final List<Map<String, dynamic>> analisisSinPaquete = [];

    for (var a in config.analisis) {
      final paqueteCodigo = a['paquete'] as String?;
      if (paqueteCodigo != null) {
        final paqueteNombre = _buscarNombrePaquete(
          config.paquetes,
          paqueteCodigo,
        );
        analisisPorPaquete.putIfAbsent(paqueteNombre, () => []);
        analisisPorPaquete[paqueteNombre]!.add(a);
      } else {
        analisisSinPaquete.add(a);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Análisis *',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 12),
        for (var entry in analisisPorPaquete.entries)
          PaqueteAnalisisCard(
            controller: controller,
            index: index,
            nombrePaquete: entry.key,
            paqueteCodigo: _buscarCodigoPaquete(config.paquetes, entry.key),
            analisisList: entry.value,
          ),
        if (analisisSinPaquete.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text(
            'Otros análisis',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          _buildAnalisisGrid(
            controller: controller,
            index: index,
            analisisList: analisisSinPaquete,
          ),
        ],
        if (controller.solicitudes[index].analisisSeleccionados.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Seleccione al menos un análisis',
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }

  String _buscarNombrePaquete(
    List<Map<String, dynamic>> paquetes,
    String paqueteCodigo,
  ) {
    final paquete = paquetes.firstWhere(
      (p) => p['codigo'].toString() == paqueteCodigo,
      orElse: () => {'nombre': 'Paquete $paqueteCodigo'},
    );
    return paquete['nombre'] as String;
  }

  Widget _buildAnalisisGrid({
    required RegistroEnvioMuestraController controller,
    required int index,
    required List<Map<String, dynamic>> analisisList,
  }) {
    final muestra = controller.solicitudes[index];
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: analisisList.map((a) {
        final codigo = a['codigo'].toString();
        final nombre = a['nombre'] as String;
        final isSelected = muestra.analisisSeleccionados.contains(codigo);
        return _buildAnalisisItem(
          nombre: nombre,
          isSelected: isSelected,
          onTap: () => controller.toggleAnalisis(
            index,
            a['codigo'].toString(),
            a['nombre'] as String,
            '', // paqueteCodigo
            '', // paqueteNombre
            !isSelected,
          ),
          // onTap: () => controller.toggleAnalisis(index, codigo, !isSelected),
        );
      }).toList(),
    );
  }

  Widget _buildAnalisisItem({
    required String nombre,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected ? Colors.green : Colors.grey,
            width: 1.2,
          ),
          borderRadius: BorderRadius.circular(6),
          color: isSelected ? Colors.green.withOpacity(0.1) : null,
        ),
        child: Text(
          nombre,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? Colors.green : null,
            fontWeight: isSelected ? FontWeight.w600 : null,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class PaqueteAnalisisCard extends StatefulWidget {
  final RegistroEnvioMuestraController controller;
  final int index;
  final String nombrePaquete;
  final String paqueteCodigo;
  final List<Map<String, dynamic>> analisisList;

  const PaqueteAnalisisCard({
    super.key,
    required this.controller,
    required this.index,
    required this.nombrePaquete,
    required this.paqueteCodigo,
    required this.analisisList,
  });

  @override
  State<PaqueteAnalisisCard> createState() => _PaqueteAnalisisCardState();
}

class _PaqueteAnalisisCardState extends State<PaqueteAnalisisCard> {
  bool _isExpanded = true;
  Widget _buildAnalisisItem({
    required String nombre,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: isSelected ? Colors.blue : Colors.grey),
          borderRadius: BorderRadius.circular(6),
          color: isSelected ? Colors.blue.withOpacity(0.1) : null,
        ),
        child: Text(
          nombre,
          style: TextStyle(color: isSelected ? Colors.blue : null),
        ),
      ),
    );
  }

  /*@override
  Widget build(BuildContext context) {
    final muestra = widget.controller.solicitudes[widget.index];
    final List<String> codigosAnalisis = widget.analisisList
        .map((a) => a['codigo'].toString())
        .toList();

    // Estado del checkbox del paquete
    final seleccionados = codigosAnalisis
        .where((codigo) => muestra.analisisSeleccionados.contains(codigo))
        .toList();

    bool? paqueteChecked;
    if (seleccionados.length == codigosAnalisis.length &&
        codigosAnalisis.isNotEmpty) {
      paqueteChecked = true; // todos seleccionados
    } else if (seleccionados.isEmpty) {
      paqueteChecked = false; // ninguno seleccionado
    } else {
      paqueteChecked = null; // estado intermedio
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        color: Colors.green.withOpacity(0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Encabezado con checkbox + nombre + ícono de expansión
          Row(
            children: [
              Checkbox(
                value: paqueteChecked,
                tristate: true,
                activeColor: Colors.green,
                onChanged: (bool? value) {
                  if (value == true) {
                    // Seleccionar todos
                    for (final a in widget.analisisList) {
                      widget.controller.toggleAnalisis(
                        widget.index,
                        a['codigo'].toString(),
                        true,
                      );
                    }
                  } else {
                    // Deseleccionar todos
                    for (final a in widget.analisisList) {
                      widget.controller.toggleAnalisis(
                        widget.index,
                        a['codigo'].toString(),
                        false,
                      );
                    }
                  }
                },
              ),
              Expanded(
                child: Text(
                  widget.nombrePaquete,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Análisis (solo si está expandido)
          if (_isExpanded)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.analisisList.map((a) {
                final codigo = a['codigo'].toString();
                final nombre = a['nombre'] as String;
                final isSelected = muestra.analisisSeleccionados.contains(
                  codigo,
                );
                return _buildAnalisisItem(
                  nombre: nombre,
                  isSelected: isSelected,
                  onTap: () {
                    widget.controller.toggleAnalisis(
                      widget.index,
                      a['codigo'].toString(),
                      a['nombre'] as String,
                      widget.paqueteCodigo,
                      widget.nombrePaquete,
                      !isSelected,
                    );
                  },
                  /*onTap: () {
                    widget.controller.toggleAnalisis(
                      widget.index,
                      codigo,
                      !isSelected,
                    );
                  },*/
                );
              }).toList(),
            ),
        ],
      ),
    );
  }*/
  @override
  Widget build(BuildContext context) {
    final muestra = widget.controller.solicitudes[widget.index];

    bool _isAnalisisSelected(String analisisCodigo, String paqueteCodigo) {
      return muestra.analisisSeleccionados.any(
        (a) =>
            a.analisisCodigo == analisisCodigo &&
            a.paqueteCodigo == paqueteCodigo,
      );
    }

    final seleccionados = widget.analisisList.where((a) {
      return _isAnalisisSelected(a['codigo'].toString(), widget.paqueteCodigo);
    }).toList();

    bool? paqueteChecked;
    if (seleccionados.length == widget.analisisList.length &&
        widget.analisisList.isNotEmpty) {
      paqueteChecked = true;
    } else if (seleccionados.isEmpty) {
      paqueteChecked = false;
    } else {
      paqueteChecked = null;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.green, width: 1.5),
        borderRadius: BorderRadius.circular(12),
        color: Colors.green.withOpacity(0.03),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: paqueteChecked,
                tristate: true,
                activeColor: Colors.green,
                onChanged: (bool? value) {
                  for (final a in widget.analisisList) {
                    widget.controller.toggleAnalisis(
                      widget.index,
                      a['codigo'].toString(),
                      a['nombre'] as String,
                      widget.paqueteCodigo,
                      widget.nombrePaquete,
                      value == true,
                    );
                  }
                },
              ),
              Expanded(
                child: Text(
                  widget.nombrePaquete,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.grey,
                ),
                onPressed: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_isExpanded)
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: widget.analisisList.map((a) {
                final codigo = a['codigo'].toString();
                final nombre = a['nombre'] as String;
                final isSelected = _isAnalisisSelected(
                  codigo,
                  widget.paqueteCodigo,
                );

                return _buildAnalisisItem(
                  nombre: nombre,
                  isSelected: isSelected,
                  onTap: () {
                    widget.controller.toggleAnalisis(
                      widget.index,
                      codigo,
                      nombre,
                      widget.paqueteCodigo,
                      widget.nombrePaquete,
                      !isSelected,
                    );
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}
