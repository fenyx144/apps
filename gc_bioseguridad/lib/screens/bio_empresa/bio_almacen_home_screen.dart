import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../services/almacen_cola.dart';
import '../../services/almacen_kardex.dart';
import '../../services/catalog_service.dart';
import '../../services/ingreso_presencia_service.dart';
import '../../services/storage_service.dart';
import '../../utils/constants.dart';
import '../../widgets/app_drawer.dart';
import '../../widgets/evidencia_select_field.dart';
import '../../widgets/granja_campania_fields.dart';
import '../../widgets/section_app_bar.dart';

class BioAlmacenHomeScreen extends StatefulWidget {
  const BioAlmacenHomeScreen({super.key});

  @override
  State<BioAlmacenHomeScreen> createState() => _BioAlmacenHomeScreenState();
}

class _BioAlmacenHomeScreenState extends State<BioAlmacenHomeScreen> {
  String _granja = '';
  String _granjaNombre = '';
  bool _loading = true;
  List<Map<String, dynamic>> _insumos = [];
  List<Map<String, dynamic>> _ropa = [];
  List<AlmacenLinea> _lineas = [];
  List<Map<String, dynamic>> _prestamos = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final storage = context.read<StorageService>();
    final sel = granjaDeTrabajoSeleccion(
      storage,
      fechaYmd: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );
    final granja = _granja.isNotEmpty ? _granja : (sel?.granja ?? '');
    final cola = AlmacenCola(storage);
    final local = context.read<CatalogService>().insumosProveedor;
    if (mounted) setState(() => _loading = true);
    final net = granja.isEmpty ? null : await cola.descargar(granja);
    final cache = net ?? (granja.isEmpty ? <String, dynamic>{} : cola.cacheDe(granja));
    final insumos = _lista(cache['insumos']);
    final kardex = _lista(cache['kardex']).map(AlmacenLinea.fromMap).toList();
    if (!mounted) return;
    setState(() {
      _granja = granja;
      _granjaNombre = _granja == sel?.granja
          ? (sel?.granjaNombre ?? _granjaNombre)
          : _granjaNombre;
      _insumos = insumos.isNotEmpty ? insumos : local;
      _ropa = _lista(cache['ropa_tipos']);
      _lineas = aplicarAlmacen(kardex, cola.pendientesDe(granja));
      _prestamos = _lista(cache['prestamos']);
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _lista(dynamic raw) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  List<Map<String, dynamic>> get _ropaTipos {
    if (_ropa.isNotEmpty) return _ropa;
    return [
      {'codigo': 1, 'nombre': 'Ropa de transito'},
      {'codigo': 2, 'nombre': 'Ropa para el proceso'},
    ];
  }

  List<({String dni, String nombre})> _trabajadores() {
    final map = <String, String>{};
    final storage = context.read<StorageService>();
    for (final g in IngresoPresenciaService.gruposConPersonalDentro(
      storage,
      granja: _granja,
    )) {
      for (final p in g.dentro) {
        if (p.dni.isNotEmpty) map[p.dni] = p.nombre;
      }
    }
    for (final p in _prestamos) {
      final dni = (p['dni'] ?? '').toString();
      if (dni.isEmpty) continue;
      map.putIfAbsent(dni, () => (p['nombre'] ?? '').toString());
    }
    final lista = map.entries.map((e) => (dni: e.key, nombre: e.value)).toList();
    lista.sort((a, b) => a.dni.compareTo(b.dni));
    return lista;
  }

  Future<void> _elegirGranja() async {
    final storage = context.read<StorageService>();
    final fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final opciones = storage.getGranjasTrabajo();
    if (opciones.isEmpty) return;
    final elegida = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final g in opciones)
              ListTile(
                title: Text(g),
                onTap: () => Navigator.pop(ctx, g),
              ),
          ],
        ),
      ),
    );
    if (elegida == null || !mounted) return;
    final sel = granjaSeleccionDe(storage, elegida, fechaYmd: fecha);
    setState(() {
      _granja = elegida;
      _granjaNombre = sel?.granjaNombre ?? '';
    });
    await _cargar();
  }

  Future<void> _operacion(String operacion) async {
    if (_granja.isEmpty) return;
    final pideTrabajador = operacion == 'ENTREGA' || operacion == 'RECEPCION';
    final items = operacion == 'CONSUMO' ? _insumos : _ropaTipos;
    if (items.isEmpty) return;
    final trabajadores = _trabajadores();
    var insumo = items.first;
    if (operacion != 'CONSUMO') {
      for (final e in items) {
        if ('${e['codigo']}' == '2') insumo = e;
      }
    }
    var dni = trabajadores.length == 1 ? trabajadores.first.dni : '';
    var nombre = trabajadores.length == 1 ? trabajadores.first.nombre : '';
    final cantCtrl = TextEditingController(text: '1');
    final dniCtrl = TextEditingController(text: dni);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final etiqueta = dni.isEmpty
                ? ''
                : (nombre.isEmpty ? dni : '$dni · $nombre');
            return AlertDialog(
              title: Text(_titulo(operacion)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: int.tryParse('${insumo['id'] ?? insumo['codigo']}'),
                    decoration: InputDecoration(
                      labelText: operacion == 'CONSUMO' ? 'Insumo' : 'Ropa',
                    ),
                    items: [
                      for (final i in items)
                        DropdownMenuItem(
                          value: int.tryParse('${i['id'] ?? i['codigo']}'),
                          child: Text((i['nombre'] ?? '').toString()),
                        ),
                    ],
                    onChanged: (v) {
                      Map<String, dynamic>? sel;
                      for (final e in items) {
                        if (int.tryParse('${e['id'] ?? e['codigo']}') == v) sel = e;
                      }
                      if (sel != null) setLocal(() => insumo = sel!);
                    },
                  ),
                  TextField(
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                    controller: cantCtrl,
                  ),
                  if (pideTrabajador) ...[
                    const SizedBox(height: 8),
                    EvidenciaSelectField(
                      label: 'Trabajador',
                      value: etiqueta,
                      placeholder: 'DNI',
                      icon: Icons.person_outline,
                      onTap: trabajadores.isEmpty
                          ? null
                          : () async {
                              final e = await showModalBottomSheet<
                                  ({String dni, String nombre})>(
                                context: ctx,
                                builder: (sheet) => SafeArea(
                                  child: ListView(
                                    shrinkWrap: true,
                                    children: [
                                      for (final t in trabajadores)
                                        ListTile(
                                          title: Text(
                                            t.nombre.isEmpty
                                                ? t.dni
                                                : '${t.dni} · ${t.nombre}',
                                          ),
                                          onTap: () => Navigator.pop(sheet, t),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                              if (e != null) {
                                setLocal(() {
                                  dni = e.dni;
                                  nombre = e.nombre;
                                });
                              }
                            },
                    ),
                    TextField(
                      decoration: const InputDecoration(labelText: 'DNI'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      controller: dniCtrl,
                      onChanged: (v) {
                        dni = v;
                        for (final t in trabajadores) {
                          if (t.dni == v) nombre = t.nombre;
                        }
                      },
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cerrar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
    final n = int.tryParse(cantCtrl.text.trim());
    cantCtrl.dispose();
    dniCtrl.dispose();
    if (ok != true || !mounted) return;
    if (n == null || n < 1) return;
    if (pideTrabajador && dni.replaceAll(RegExp(r'\D'), '').length < 6) return;
    final item = operacion == 'CONSUMO'
        ? '${insumo['id']}'
        : '${insumo['codigo'] ?? insumo['id'] ?? 2}';
    if (rechazoAlmacen(_lineas, operacion: operacion, item: item, cantidad: n.toDouble()) !=
        null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sin stock')));
      return;
    }
    final storage = context.read<StorageService>();
    final cola = AlmacenCola(storage);
    await cola.encolar({
      'uuid': const Uuid().v4(),
      'granja_cod': _granja,
      'granja': _granja,
      'fecha': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      'operacion': operacion,
      'item': item,
      'insumo_id': operacion == 'CONSUMO' ? insumo['id'] : 0,
      'ropa_tipo': operacion == 'CONSUMO' ? 0 : item,
      'nombre_insumo': insumo['nombre'] ?? '',
      'cantidad': n,
      'dni': dni.replaceAll(RegExp(r'\D'), ''),
      'origen': 'app',
    });
    await cola.sincronizar();
    await _cargar();
  }

  String _titulo(String op) {
    switch (op) {
      case 'CONSUMO':
        return 'Consumo';
      case 'ENTREGA':
        return 'Entrega';
      case 'RECEPCION':
        return 'Recepción';
      default:
        return 'Lavado';
    }
  }

  String _fmt(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  String _alm(String a) {
    if (a == 'LAVADERO') return 'Lavadero';
    if (a == 'INSUMOS') return 'Insumos';
    return 'Limpio';
  }

  @override
  Widget build(BuildContext context) {
    final porInsumo = <String, List<AlmacenLinea>>{};
    for (final l in _lineas) {
      final esRopa = l.frente != 'INSUMOS' && l.item == '2';
      final tiene = l.si != 0 || l.e != 0 || l.s != 0;
      if (!esRopa && !tiene) continue;
      porInsumo.putIfAbsent(l.nombre.isEmpty ? l.item : l.nombre, () => []).add(l);
    }
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: 'Almacén',
        sectionIcon: Icons.inventory_2_outlined,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  EvidenciaSelectField(
                    label: 'Granja',
                    value: _granjaNombre.isEmpty ? _granja : '$_granja · $_granjaNombre',
                    placeholder: 'Granja',
                    icon: Icons.agriculture_outlined,
                    onTap: _elegirGranja,
                  ),
                  const SizedBox(height: 12),
                  for (final entry in porInsumo.entries) ...[
                    Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.4),
                        1: FlexColumnWidth(),
                        2: FlexColumnWidth(),
                        3: FlexColumnWidth(),
                        4: FlexColumnWidth(),
                      },
                      children: [
                        const TableRow(
                          children: [
                            Text(''),
                            Text('SI'),
                            Text('E'),
                            Text('S'),
                            Text('Stock'),
                          ],
                        ),
                        for (final l in entry.value)
                          TableRow(
                            children: [
                              Text(_alm(l.frente)),
                              Text(_fmt(l.si)),
                              Text(_fmt(l.e)),
                              Text(_fmt(l.s)),
                              Text(_fmt(l.stock)),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _boton('Consumo', 'CONSUMO'),
                      _boton('Entrega', 'ENTREGA'),
                      _boton('Recepción', 'RECEPCION'),
                      _boton('Lavado', 'LAVADO'),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _boton(String texto, String op) {
    return FilledButton(
      onPressed: _granja.isEmpty ? null : () => _operacion(op),
      style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
      child: Text(texto),
    );
  }
}

// Recepción de entregas GRS → tercero. GRS ya no envía insumos ni indumentaria.
// Se deja el flujo anterior comentado, sin borrarlo.
//
// class _RecepcionGrs {
//   List<dynamic> entregas = [];
//   Future<void> cargar(BioEmpresaApi api) async {
//     final ctx = await api.get('/almacen/campo-context');
//     final data = ctx['data'] as Map<String, dynamic>;
//     entregas = data['entregas_pendientes'] as List<dynamic>? ?? [];
//   }
//   Widget lista() {
//     return Column(
//       children: [
//         Text('Entregas pendientes (${entregas.length})'),
//         if (entregas.isEmpty)
//           const Text('No hay entregas pendientes de recepción.'),
//         ...entregas.take(20).map((e) {
//           final m = e as Map<String, dynamic>;
//           return ListTile(
//             leading: const Icon(Icons.local_shipping_outlined),
//             title: Text('Entrega #${m['id']} · ${m['fecha']}'),
//             subtitle: Text((m['observacion'] ?? '').toString()),
//           );
//         }),
//       ],
//     );
//   }
// }
