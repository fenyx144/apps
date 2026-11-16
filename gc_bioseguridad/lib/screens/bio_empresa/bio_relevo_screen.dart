import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/bio_empresa_api.dart';
import '../../services/storage_service.dart';
import '../../utils/constants.dart';
import '../../widgets/bio_form_fields.dart';
import '../../widgets/evidencia_select_field.dart';
import '../../widgets/granja_campania_fields.dart';
import '../../widgets/section_app_bar.dart';

class BioRelevoScreen extends StatefulWidget {
  const BioRelevoScreen({super.key});

  @override
  State<BioRelevoScreen> createState() => _BioRelevoScreenState();
}

class _BioRelevoScreenState extends State<BioRelevoScreen> {
  final _api = BioEmpresaApi();
  final _salida = TextEditingController();
  final _entrada = TextEditingController();
  final _obs = TextEditingController();
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  List<String> _campaniasDisponibles = const [];
  String _turno = 'DIA';
  final DateTime _fecha = DateTime.now();
  bool _loading = true;
  bool _guardando = false;
  final Map<int, TextEditingController> _contados = {};
  final Map<int, num> _stockSistema = {};
  List<dynamic> _stock = [];

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);
  String get _turnoLabel => _turno == 'NOCHE' ? 'Noche' : 'Día';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargarStock());
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

  @override
  void dispose() {
    _salida.dispose();
    _entrada.dispose();
    _obs.dispose();
    for (final c in _contados.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarStock() async {
    setState(() => _loading = true);
    try {
      final ctx = await _api.get('/almacen/campo-context');
      final items = (ctx['data']?['stock'] as List<dynamic>?) ?? [];
      for (final c in _contados.values) {
        c.dispose();
      }
      _contados.clear();
      _stockSistema.clear();
      for (final raw in items) {
        final m = raw as Map<String, dynamic>;
        final iid = m['insumo_id'] as int;
        final stock = (m['stock'] as num?) ?? 0;
        _stockSistema[iid] = stock;
        _contados[iid] = TextEditingController(text: stock.round().toString());
      }
      setState(() {
        _stock = items;
        _loading = false;
      });
      _aplicarGranjaDeTrabajo();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar stock: $e')),
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

  Future<void> _pickTurno() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Día'),
              onTap: () => Navigator.pop(ctx, 'DIA'),
            ),
            ListTile(
              title: const Text('Noche'),
              onTap: () => Navigator.pop(ctx, 'NOCHE'),
            ),
          ],
        ),
      ),
    );
    if (v != null) setState(() => _turno = v);
  }

  Future<void> _guardar() async {
    if (_granja.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleccione la granja')),
      );
      return;
    }
    setState(() => _guardando = true);
    try {
      final items = <Map<String, dynamic>>[];
      for (final raw in _stock) {
        final m = raw as Map<String, dynamic>;
        final iid = m['insumo_id'] as int;
        final ctrl = _contados[iid];
        final sys = (_stockSistema[iid] ?? 0).toDouble();
        final cnt = (int.tryParse(ctrl?.text.trim() ?? '') ?? sys.round()).toDouble();
        items.add({
          'insumo_id': iid,
          'cantidad_sistema': sys,
          'cantidad_contada': cnt,
        });
      }
      final res = await _api.post('/almacen/relevos', {
        'fecha': _fechaYmd,
        'turno_cod': _turno,
        'granja_cod': _granja.trim(),
        'responsable_salida': _salida.text.trim(),
        'responsable_entrada': _entrada.text.trim(),
        'observacion': _obs.text.trim(),
        'items': items,
      });
      if (res['ok'] != true) {
        throw Exception(res['error']?['message'] ?? 'No se guardó');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relevo registrado')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SectionAppBar(
        title: 'Relevo de turno',
        sectionIcon: Icons.swap_horiz_rounded,
        showDrawerButton: false,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BioFormSection(
                    title: 'DATOS DEL RELEVO',
                    icon: Icons.fact_check_outlined,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: BioReadOnlyField(
                              label: 'Fecha',
                              value: DateFormat('dd/MM/yyyy').format(_fecha),
                              icon: Icons.calendar_month_rounded,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: EvidenciaSelectField(
                              label: 'Turno',
                              value: _turnoLabel,
                              placeholder: 'Seleccione',
                              icon: Icons.wb_twilight_rounded,
                              onTap: _pickTurno,
                            ),
                          ),
                        ],
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
                    title: 'RESPONSABLES',
                    icon: Icons.groups_outlined,
                    children: [
                      BioTextArea(
                        label: 'Responsable que entrega',
                        controller: _salida,
                        hint: 'Nombre del titular del turno saliente',
                        icon: Icons.person_outline_rounded,
                        maxLength: 120,
                        minLines: 1,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      BioTextArea(
                        label: 'Responsable que recibe',
                        controller: _entrada,
                        hint: 'Nombre del titular del turno entrante',
                        icon: Icons.person_outline_rounded,
                        maxLength: 120,
                        minLines: 1,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      BioTextArea(
                        label: 'Observaciones',
                        controller: _obs,
                        hint: 'Novedades del relevo (opcional)',
                        icon: Icons.edit_note_rounded,
                        maxLength: 255,
                        minLines: 2,
                        maxLines: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  BioFormSection(
                    title: 'CONTEO DE INSUMOS',
                    icon: Icons.inventory_2_outlined,
                    children: [
                      ..._stock.map((raw) {
                        final m = raw as Map<String, dynamic>;
                        final iid = m['insumo_id'] as int;
                        final nombre = '${m['insumo_nombre']} (${m['unidad']})';
                        final sys = (_stockSistema[iid] ?? 0).round();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: _contados[iid],
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(
                              labelText: nombre,
                              helperText: 'Stock según sistema: $sys ${m['unidad']}',
                              helperMaxLines: 2,
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        );
                      }),
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
                        : const Text('Guardar relevo'),
                  ),
                ],
              ),
            ),
    );
  }
}
