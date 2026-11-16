import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/bio_empresa_api.dart';
import '../../services/catalog_service.dart';
import '../../services/storage_service.dart';
import '../../utils/constants.dart';
import '../../widgets/bio_form_fields.dart';
import '../../widgets/evidencia_select_field.dart';
import '../../widgets/granja_campania_fields.dart';
import '../../widgets/section_app_bar.dart';

int? _insumoIdParse(dynamic id) {
  if (id is int) return id;
  return int.tryParse(id?.toString() ?? '');
}

class BioConsumoScreen extends StatefulWidget {
  const BioConsumoScreen({super.key});

  @override
  State<BioConsumoScreen> createState() => _BioConsumoScreenState();
}

class _BioConsumoScreenState extends State<BioConsumoScreen> {
  final _api = BioEmpresaApi();
  final _cantidad = TextEditingController();
  final _obs = TextEditingController();
  final _otroNombre = TextEditingController();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDisponibles = const [];
  DateTime _fecha = DateTime.now();
  int? _insumoId;
  bool _insumoOtro = false;
  bool _loading = true;
  bool _guardando = false;
  List<Map<String, dynamic>> _insumos = [];

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  @override
  void dispose() {
    _cantidad.dispose();
    _obs.dispose();
    _otroNombre.dispose();
    super.dispose();
  }

  void _aplicarGranjaDeTrabajo() {
    final sel = granjaDeTrabajoSeleccion(
      context.read<StorageService>(),
      fechaYmd: _fechaYmd,
    );
    if (sel == null) return;
    setState(() {
      _granja = sel.granja;
      _granjaNombre = sel.granjaNombre;
      _campania = sel.campania;
      _campaniasDisponibles = sel.campanias;
    });
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final local = context.read<CatalogService>().insumosProveedor;
    if (local.isNotEmpty) {
      setState(() {
        _insumos = local;
        _loading = false;
      });
      _aplicarGranjaDeTrabajo();
      return;
    }
    try {
      final ctx = await _api.get('/almacen/campo-context');
      final data = ctx['data'] as Map<String, dynamic>;
      final items = (data['insumos'] as List<dynamic>?) ?? [];
      setState(() {
        _insumos = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
      await context.read<CatalogService>().mergeInsumosProveedor(_insumos);
      _aplicarGranjaDeTrabajo();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo cargar insumos. Descargue catálogos desde el menú lateral: $e',
            ),
          ),
        );
      }
    }
  }

  void _onGranjaCampania(GranjaCampaniaSeleccion sel) {
    setState(() {
      _granja = sel.granja;
      _granjaNombre = sel.granjaNombre;
      _campania = sel.campania;
      _campaniasDisponibles = sel.campanias;
    });
  }

  Future<void> _pickFecha() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (d != null) {
      setState(() => _fecha = d);
    }
  }

  String _insumoLabel() {
    if (_insumoOtro) {
      final t = _otroNombre.text.trim();
      return t.isEmpty ? 'Otro (indique nombre)' : t;
    }
    if (_insumoId == null) return '';
    for (final i in _insumos) {
      if (_insumoIdParse(i['id']) == _insumoId) {
        return '${i['nombre']} (${i['unidad']})';
      }
    }
    return '';
  }

  Future<void> _pickInsumo() async {
    final result = await showModalBottomSheet<({int? id, bool otro})>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Seleccione insumo')),
              ..._insumos.map((i) {
                final iid = _insumoIdParse(i['id']);
                if (iid == null) return const SizedBox.shrink();
                return ListTile(
                  title: Text(i['nombre']?.toString() ?? ''),
                  subtitle: Text(i['codigo']?.toString() ?? ''),
                  trailing: Text(i['unidad']?.toString() ?? ''),
                  onTap: () => Navigator.pop(ctx, (id: iid, otro: false)),
                );
              }),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Otro…'),
                onTap: () => Navigator.pop(ctx, (id: null, otro: true)),
              ),
            ],
          ),
        );
      },
    );
    if (result == null) return;
    setState(() {
      _insumoOtro = result.otro;
      _insumoId = result.id;
    });
  }

  Future<void> _guardar() async {
    final cant = int.tryParse(_cantidad.text.trim());
    if ((!_insumoOtro && _insumoId == null) || cant == null || cant < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione insumo y cantidad válida')),
      );
      return;
    }
    if (_insumoOtro && _otroNombre.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Indique el nombre del insumo (Otro)')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      final body = <String, dynamic>{
        'cantidad': cant,
        'fecha': _fechaYmd,
        'granja_cod': _granja.trim(),
        'observacion': _obs.text.trim(),
      };
      if (_insumoOtro) {
        body['observacion'] =
            'Otro: ${_otroNombre.text.trim()}. ${_obs.text.trim()}'.trim();
      } else {
        body['insumo_id'] = _insumoId;
      }
      final res = await _api.post('/almacen/consumos', body);
      if (res['ok'] != true) {
        throw Exception(res['error']?['message'] ?? 'No se guardó');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consumo registrado')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SectionAppBar(
        title: 'Registrar consumo',
        sectionIcon: Icons.output_rounded,
        showDrawerButton: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_insumos.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Sin insumos en caché. Use «Descargar» en el menú o jale para actualizar.',
                        ),
                      ),
                    BioFormSection(
                      title: 'DATOS DEL CONSUMO',
                      icon: Icons.inventory_2_outlined,
                      children: [
                        EvidenciaSelectField(
                          label: 'Insumo',
                          value: _insumoLabel(),
                          placeholder: 'Seleccione',
                          icon: Icons.category_outlined,
                          onTap: _insumos.isEmpty ? null : _pickInsumo,
                        ),
                        if (_insumoOtro) ...[
                          const SizedBox(height: 12),
                          TextField(
                            controller: _otroNombre,
                            decoration: const InputDecoration(
                              labelText: 'Nombre del insumo (Otro)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _cantidad,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(
                            labelText: 'Cantidad',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        EvidenciaSelectField(
                          label: 'Fecha',
                          value: DateFormat('dd/MM/yyyy').format(_fecha),
                          placeholder: 'Hoy',
                          icon: Icons.calendar_month_rounded,
                          onTap: _pickFecha,
                        ),
                        const SizedBox(height: 12),
                        GranjaCampaniaFields(
                          fechaYmd: _fechaYmd,
                          granja: _granja,
                          granjaNombre: _granjaNombre,
                          campania: _campania,
                          campanias: _campaniasDisponibles,
                          onSeleccion: _onGranjaCampania,
                          separacion: 12,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    BioFormSection(
                      title: 'OBSERVACIÓN',
                      icon: Icons.edit_note_rounded,
                      children: [
                        BioTextArea(
                          label: 'Detalle (opcional)',
                          controller: _obs,
                          hint: 'Motivo o lugar del consumo',
                          icon: Icons.edit_rounded,
                          maxLength: 255,
                          minLines: 2,
                          maxLines: 3,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _guardando ? null : _guardar,
                      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                      child: _guardando
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Guardar consumo'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}