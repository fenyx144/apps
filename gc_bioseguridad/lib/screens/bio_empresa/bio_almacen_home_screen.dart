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
import '../../widgets/app_drawer.dart';
import '../../widgets/evidencia_select_field.dart';
import '../../widgets/granja_campania_fields.dart';
import '../../widgets/section_app_bar.dart';

const _verde = Color(0xFF1F7A4D);
const _verdeSuave = Color(0xFFE8F6EE);
const _verdeBorde = Color(0xFF8FCBAA);

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
                leading: const Icon(Icons.agriculture_outlined, color: _verde),
                title: Text(_etiquetaGranja(storage, g, fecha)),
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

  String _etiquetaGranja(StorageService storage, String codigo, String fecha) {
    final sel = granjaSeleccionDe(storage, codigo, fechaYmd: fecha);
    final nombre = (sel?.granjaNombre ?? '').trim();
    if (nombre.isEmpty || nombre == codigo) return codigo;
    return '$codigo · $nombre';
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
    final elegido = await showDialog<AlmacenDialogoResult>(
      context: context,
      builder: (ctx) => AlmacenMovimientoDialog(
        titulo: _titulo(operacion),
        etiquetaItem: operacion == 'CONSUMO' ? 'Insumo' : 'Ropa',
        items: items,
        inicial: int.tryParse('${insumo['id'] ?? insumo['codigo']}'),
        pideTrabajador: pideTrabajador,
        trabajadores: trabajadores,
        dniInicial: dni,
        nombreInicial: nombre,
      ),
    );
    final n = elegido?.cantidad;
    if (elegido == null || !mounted) return;
    if (n == null || n < 1) return;
    if (pideTrabajador && elegido.dni.replaceAll(RegExp(r'\D'), '').length < 6) {
      return;
    }
    insumo = elegido.item;
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
      'dni': elegido.dni.replaceAll(RegExp(r'\D'), ''),
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

  List<AlmacenLinea> get _ropaLineas => _lineas.where((l) {
        if (l.frente == 'INSUMOS') return false;
        final proceso = l.item == '2';
        final tiene = l.si != 0 || l.e != 0 || l.s != 0;
        return proceso || tiene;
      }).toList();

  List<AlmacenLinea> get _insumoLineas =>
      _lineas.where((l) => l.frente == 'INSUMOS').toList();

  @override
  Widget build(BuildContext context) {
    final storage = context.read<StorageService>();
    final fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final granjaTxt = _granja.isEmpty
        ? ''
        : _etiquetaGranja(storage, _granja, fecha);
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: 'Almacén',
        sectionIcon: Icons.inventory_2_outlined,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _verde))
          : RefreshIndicator(
              color: _verde,
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  EvidenciaSelectField(
                    label: 'Granja',
                    value: granjaTxt,
                    placeholder: 'Granja',
                    icon: Icons.agriculture_outlined,
                    onTap: _elegirGranja,
                  ),
                  const SizedBox(height: 14),
                  _tarjeta(
                    icono: Icons.checkroom_outlined,
                    titulo: 'Ropa',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tabla(_ropaLineas),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _boton('Entrega', 'ENTREGA', Icons.output_rounded),
                            _boton('Recepción', 'RECEPCION', Icons.keyboard_return_rounded),
                            _boton('Lavado', 'LAVADO', Icons.local_laundry_service_outlined),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _tarjeta(
                    icono: Icons.science_outlined,
                    titulo: 'Insumos',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _tabla(_insumoLineas),
                        const SizedBox(height: 10),
                        _boton('Consumo', 'CONSUMO', Icons.remove_circle_outline),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tarjeta({
    required IconData icono,
    required String titulo,
    required Widget child,
  }) {
    return Card(
      color: _verdeSuave,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _verdeBorde),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icono, color: _verde, size: 22),
                const SizedBox(width: 8),
                Text(
                  titulo,
                  style: const TextStyle(
                    color: _verde,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  Widget _tabla(List<AlmacenLinea> lineas) {
    final grupos = <String, List<AlmacenLinea>>{};
    for (final l in lineas) {
      grupos.putIfAbsent(l.nombre.isEmpty ? l.item : l.nombre, () => []).add(l);
    }
    if (grupos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in grupos.entries) ...[
          Text(
            entry.key,
            style: const TextStyle(fontWeight: FontWeight.w700, color: _verde),
          ),
          const SizedBox(height: 4),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(1.5),
              1: FlexColumnWidth(),
              2: FlexColumnWidth(),
              3: FlexColumnWidth(),
              4: FlexColumnWidth(),
            },
            children: [
              const TableRow(
                children: [
                  Text(''),
                  Text('SI', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('E', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('S', style: TextStyle(fontWeight: FontWeight.w700)),
                  Text('Stock', style: TextStyle(fontWeight: FontWeight.w700)),
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
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _boton(String texto, String op, IconData icono) {
    return FilledButton.icon(
      onPressed: _granja.isEmpty ? null : () => _operacion(op),
      style: FilledButton.styleFrom(
        backgroundColor: _verde,
        visualDensity: VisualDensity.compact,
      ),
      icon: Icon(icono, size: 18),
      label: Text(texto),
    );
  }
}

class AlmacenDialogoResult {
  const AlmacenDialogoResult({
    required this.item,
    required this.cantidad,
    required this.dni,
  });

  final Map<String, dynamic> item;
  final int cantidad;
  final String dni;
}

/// Formulario de un movimiento. El contenido hace scroll y respeta el teclado.
class AlmacenMovimientoDialog extends StatefulWidget {
  const AlmacenMovimientoDialog({
    super.key,
    required this.titulo,
    required this.etiquetaItem,
    required this.items,
    required this.inicial,
    required this.pideTrabajador,
    required this.trabajadores,
    required this.dniInicial,
    required this.nombreInicial,
  });

  final String titulo;
  final String etiquetaItem;
  final List<Map<String, dynamic>> items;
  final int? inicial;
  final bool pideTrabajador;
  final List<({String dni, String nombre})> trabajadores;
  final String dniInicial;
  final String nombreInicial;

  @override
  State<AlmacenMovimientoDialog> createState() => _AlmacenMovimientoDialogState();
}

class _AlmacenMovimientoDialogState extends State<AlmacenMovimientoDialog> {
  late Map<String, dynamic> _item;
  late final TextEditingController _cant;
  late final TextEditingController _dni;
  late String _nombre;

  @override
  void initState() {
    super.initState();
    _item = widget.items.first;
    for (final e in widget.items) {
      if (int.tryParse('${e['id'] ?? e['codigo']}') == widget.inicial) {
        _item = e;
      }
    }
    _cant = TextEditingController(text: '1');
    _dni = TextEditingController(text: widget.dniInicial);
    _nombre = widget.nombreInicial;
  }

  @override
  void dispose() {
    _cant.dispose();
    _dni.dispose();
    super.dispose();
  }

  int? _clave(Map<String, dynamic> m) =>
      int.tryParse('${m['id'] ?? m['codigo']}');

  void _guardar() {
    final n = int.tryParse(_cant.text.trim());
    if (n == null || n < 1) return;
    Navigator.of(context).pop(
      AlmacenDialogoResult(item: _item, cantidad: n, dni: _dni.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final etiqueta = _dni.text.trim().isEmpty
        ? ''
        : (_nombre.isEmpty ? _dni.text : '${_dni.text} · $_nombre');
    return AlertDialog(
      scrollable: true,
      title: Text(widget.titulo),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _clave(_item),
              decoration: InputDecoration(
                labelText: widget.etiquetaItem,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final i in widget.items)
                  DropdownMenuItem(
                    value: _clave(i),
                    child: Text(
                      (i['nombre'] ?? '').toString(),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                for (final e in widget.items) {
                  if (_clave(e) == v) setState(() => _item = e);
                }
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _cant,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.pideTrabajador) ...[
              const SizedBox(height: 8),
              EvidenciaSelectField(
                label: 'Trabajador',
                value: etiqueta,
                placeholder: 'DNI',
                icon: Icons.person_outline,
                onTap: widget.trabajadores.isEmpty
                    ? null
                    : () async {
                        final e = await showModalBottomSheet<
                            ({String dni, String nombre})>(
                          context: context,
                          builder: (sheet) => SafeArea(
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final t in widget.trabajadores)
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
                        if (e == null) return;
                        setState(() {
                          _dni.text = e.dni;
                          _nombre = e.nombre;
                        });
                      },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _dni,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'DNI',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  for (final t in widget.trabajadores) {
                    if (t.dni == v) _nombre = t.nombre;
                  }
                },
              ),
            ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _guardar,
          style: FilledButton.styleFrom(backgroundColor: _verde),
          child: const Text('Guardar'),
        ),
      ],
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
