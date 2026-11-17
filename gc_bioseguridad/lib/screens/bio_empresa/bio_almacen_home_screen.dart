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
  List<String> _acciones = [];
  List<Map<String, dynamic>> _granjas = [];
  List<Map<String, dynamic>> _insumos = [];
  List<Map<String, dynamic>> _implementos = [];
  List<Map<String, dynamic>> _ropa = [];
  List<Map<String, dynamic>> _personal = [];
  List<AlmacenLinea> _lineas = [];

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
    final implementos = _lista(cache['implementos']);
    final uniformes = _lista(cache['uniformes']);
    final base = _lineasDe(cache, uniformes, implementos, insumos);
    final acciones = _listaTexto(cache['acciones']);
    final granjas = _lista(cache['granjas']);
    if (!mounted) return;
    var granjaEfectiva = granja;
    var nombre = _granja == sel?.granja ? (sel?.granjaNombre ?? _granjaNombre) : _granjaNombre;
    if (granjas.isNotEmpty && !granjas.any((g) => '${g['codigo']}' == granjaEfectiva)) {
      granjaEfectiva = '${granjas.first['codigo']}';
      nombre = '${granjas.first['nombre'] ?? ''}';
    } else if (granjas.isNotEmpty) {
      final g = granjas.firstWhere((e) => '${e['codigo']}' == granjaEfectiva);
      final n = '${g['nombre'] ?? ''}'.trim();
      if (n.isNotEmpty) nombre = n;
    }
    setState(() {
      _granja = granjaEfectiva;
      _granjaNombre = nombre;
      _acciones = acciones;
      _granjas = granjas;
      _insumos = insumos.isNotEmpty ? insumos : local;
      _implementos = implementos;
      _ropa = _lista(cache['ropa_tipos']);
      _personal = _lista(cache['personal']);
      _lineas = aplicarAlmacen(base, cola.pendientesDe(granjaEfectiva));
      _loading = false;
    });
    if (granjaEfectiva != granja && granjaEfectiva.isNotEmpty) {
      await _cargar();
    }
  }

  List<String> _listaTexto(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  List<AlmacenLinea> _lineasDe(
    Map<String, dynamic> cache,
    List<Map<String, dynamic>> uniformes,
    List<Map<String, dynamic>> implementos,
    List<Map<String, dynamic>> insumos,
  ) {
    final out = <AlmacenLinea>[];
    for (final u in uniformes) {
      out.add(AlmacenLinea(
        frente: (u['frente'] ?? '').toString(),
        item: (u['item'] ?? u['ropa_tipo'] ?? '').toString(),
        nombre: (u['ropa_nombre'] ?? u['nombre'] ?? '').toString(),
        si: _num(u['stock']),
      ));
    }
    for (final i in implementos) {
      out.add(AlmacenLinea(
        frente: 'IMPLEMENTOS',
        item: (i['item'] ?? i['insumo_id'] ?? '').toString(),
        nombre: (i['nombre'] ?? '').toString(),
        unidad: (i['unidad'] ?? '').toString(),
        si: _num(i['stock']),
      ));
    }
    for (final i in insumos) {
      out.add(AlmacenLinea(
        frente: 'INSUMOS',
        item: (i['item'] ?? i['insumo_id'] ?? '').toString(),
        nombre: (i['nombre'] ?? '').toString(),
        unidad: (i['unidad'] ?? '').toString(),
        si: _num(i['stock']),
      ));
    }
    if (out.isEmpty) {
      return _lista(cache['kardex']).map(AlmacenLinea.fromMap).toList();
    }
    return out;
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
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

  List<({String dni, String nombre, int id})> _trabajadores() {
    final map = <String, ({String dni, String nombre, int id})>{};
    for (final p in _personal) {
      final dni = (p['dni'] ?? '').toString();
      if (dni.isEmpty) continue;
      map[dni] = (
        dni: dni,
        nombre: (p['nombre'] ?? '').toString(),
        id: int.tryParse('${p['id']}') ?? 0,
      );
    }
    final storage = context.read<StorageService>();
    for (final g in IngresoPresenciaService.gruposConPersonalDentro(
      storage,
      granja: _granja,
    )) {
      for (final p in g.dentro) {
        if (p.dni.isEmpty) continue;
        map.putIfAbsent(p.dni, () => (dni: p.dni, nombre: p.nombre, id: 0));
      }
    }
    final lista = map.values.toList();
    lista.sort((a, b) => a.dni.compareTo(b.dni));
    return lista;
  }

  Future<void> _elegirGranja() async {
    final storage = context.read<StorageService>();
    final fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final opciones = _granjas.isNotEmpty
        ? _granjas.map((g) => '${g['codigo']}').where((c) => c.isNotEmpty).toList()
        : storage.getGranjasTrabajo();
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
    for (final g in _granjas) {
      if ('${g['codigo']}' != codigo) continue;
      final nombre = '${g['nombre'] ?? ''}'.trim();
      if (nombre.isEmpty || nombre == codigo) return codigo;
      return '$codigo · $nombre';
    }
    final sel = granjaSeleccionDe(storage, codigo, fechaYmd: fecha);
    final nombre = (sel?.granjaNombre ?? '').trim();
    if (nombre.isEmpty || nombre == codigo) return codigo;
    return '$codigo · $nombre';
  }

  Future<void> _operacion(String operacion) async {
    if (_granja.isEmpty || !_acciones.contains(operacion)) return;
    final relevo = operacion == 'RELEVO';
    final pideTrabajador = operacion == 'ENTREGA' || operacion == 'DEVOLUCION';
    final items = _itemsDe(operacion);
    if (!relevo && items.isEmpty) return;
    final trabajadores = _trabajadores();
    var insumo = items.isEmpty ? <String, dynamic>{} : items.first;
    if (operacion == 'LAVADO' || operacion == 'ENTREGA' || operacion == 'DEVOLUCION') {
      for (final e in items) {
        if ('${e['codigo'] ?? e['item']}' == '2' && '${e['categoria']}' == 'UNIFORME') {
          insumo = e;
        }
      }
    }
    final unico = trabajadores.length == 1 ? trabajadores.first : null;
    final elegido = await showDialog<AlmacenDialogoResult>(
      context: context,
      builder: (ctx) => AlmacenMovimientoDialog(
        titulo: _titulo(operacion),
        etiquetaItem: _etiquetaItem(operacion),
        items: items,
        inicial: int.tryParse('${insumo['id'] ?? insumo['codigo']}'),
        pideTrabajador: pideTrabajador,
        pideEntrante: relevo,
        pideCantidad: !relevo,
        eligeItem: !relevo,
        trabajadores: trabajadores,
        dniInicial: unico?.dni ?? '',
        nombreInicial: unico?.nombre ?? '',
      ),
    );
    if (elegido == null || !mounted) return;
    final n = relevo ? 1 : elegido.cantidad;
    if (n < 1) return;
    if (pideTrabajador && elegido.dni.trim().length < 6) return;
    if (relevo && (elegido.dni.trim().length < 6 || elegido.dniEntra.trim().length < 6)) {
      return;
    }
    if (relevo && elegido.dni.trim() == elegido.dniEntra.trim()) return;
    insumo = elegido.item;
    final categoria = '${insumo['categoria'] ?? _categoriaDe(operacion)}';
    final item = categoria == 'UNIFORME'
        ? '${insumo['codigo'] ?? insumo['item'] ?? 2}'
        : '${insumo['id'] ?? insumo['insumo_id'] ?? insumo['item']}';
    if (rechazoAlmacen(
          _lineas,
          operacion: operacion,
          item: item,
          cantidad: n.toDouble(),
          categoria: categoria,
        ) !=
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
      'categoria': categoria,
      'item': item,
      'insumo_id': categoria == 'UNIFORME' ? 0 : insumo['id'] ?? insumo['insumo_id'],
      'ropa_tipo': categoria == 'UNIFORME' ? item : 0,
      'nombre_insumo': insumo['nombre'] ?? '',
      'cantidad': n,
      'dni': elegido.dni.trim(),
      'personal_id': elegido.personalId,
      'dni_sale': relevo ? elegido.dni.trim() : '',
      'personal_id_sale': relevo ? elegido.personalId : 0,
      'dni_entra': relevo ? elegido.dniEntra.trim() : '',
      'personal_id_entra': relevo ? elegido.personalIdEntra : 0,
      'origen': 'app',
    });
    await cola.sincronizar();
    await _cargar();
  }

  List<Map<String, dynamic>> _itemsDe(String operacion) {
    final ropa = [
      for (final r in _ropaTipos)
        {
          'codigo': r['codigo'],
          'nombre': r['nombre'],
          'categoria': 'UNIFORME',
        },
    ];
    final imps = [
      for (final i in _implementos)
        {...i, 'categoria': 'IMPLEMENTO', 'id': i['insumo_id'] ?? i['id'] ?? i['item']},
    ];
    final ins = [
      for (final i in _insumos)
        {...i, 'categoria': 'INSUMO', 'id': i['insumo_id'] ?? i['id'] ?? i['item']},
    ];
    switch (operacion) {
      case 'CONSUMO':
        return ins;
      case 'LAVADO':
      case 'RELEVO':
        return ropa;
      case 'ENTREGA':
      case 'DEVOLUCION':
        return [...ropa, ...imps];
      default:
        return [...ropa, ...imps, ...ins];
    }
  }

  String _categoriaDe(String operacion) {
    if (operacion == 'CONSUMO') return 'INSUMO';
    if (operacion == 'LAVADO' || operacion == 'RELEVO') return 'UNIFORME';
    return '';
  }

  String _etiquetaItem(String op) {
    if (op == 'CONSUMO') return 'Insumo';
    if (op == 'LAVADO') return 'Uniforme';
    return 'Ítem';
  }

  String _titulo(String op) {
    switch (op) {
      case 'ENVIO':
        return 'Envío';
      case 'SI':
        return 'Saldo inicial';
      case 'CONSUMO':
        return 'Consumo';
      case 'ENTREGA':
        return 'Entrega';
      case 'DEVOLUCION':
        return 'Devolución';
      case 'RELEVO':
        return 'Relevo';
      default:
        return 'Lavado';
    }
  }

  String _fmt(double n) {
    if (n == n.roundToDouble()) return n.toInt().toString();
    return n.toStringAsFixed(2);
  }

  double _stock(String frente, String item) => stockAlmacen(_lineas, frente, item);

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
                    titulo: 'Uniformes',
                    child: _stockUniformes(),
                  ),
                  const SizedBox(height: 12),
                  _tarjeta(
                    icono: Icons.construction_outlined,
                    titulo: 'Implementos',
                    child: _stockItems('IMPLEMENTOS'),
                  ),
                  const SizedBox(height: 12),
                  _tarjeta(
                    icono: Icons.science_outlined,
                    titulo: 'Insumos',
                    child: _stockItems('INSUMOS'),
                  ),
                  const SizedBox(height: 16),
                  for (final op in _acciones) ...[
                    _boton(_titulo(op), op, _icono(op)),
                    const SizedBox(height: 8),
                  ],
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
      color: Colors.white,
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

  Widget _stockUniformes() {
    final nombres = <String, String>{'1': 'Ropa de transito', '2': 'Ropa para el proceso'};
    for (final r in _ropaTipos) {
      nombres['${r['codigo']}'] = '${r['nombre']}';
    }
    final items = <String>{'2'};
    for (final l in _lineas) {
      if (l.frente == 'LIMPIO' || l.frente == 'LAVADERO') items.add(l.item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          Text(
            nombres[item] ?? item,
            style: const TextStyle(fontWeight: FontWeight.w700, color: _verde),
          ),
          _lineaStock('Limpio', _stock('LIMPIO', item)),
          _lineaStock('Lavadero', _stock('LAVADERO', item)),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _stockItems(String frente) {
    final lineas = _lineas.where((l) => l.frente == frente).toList();
    if (lineas.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final l in lineas) _lineaStock(l.nombre.isEmpty ? l.item : l.nombre, l.stock),
      ],
    );
  }

  Widget _lineaStock(String nombre, double stock) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(nombre)),
          Text(_fmt(stock), style: const TextStyle(fontWeight: FontWeight.w800, color: _verde)),
        ],
      ),
    );
  }

  IconData _icono(String op) {
    switch (op) {
      case 'ENVIO':
        return Icons.local_shipping_outlined;
      case 'SI':
        return Icons.playlist_add_rounded;
      case 'CONSUMO':
        return Icons.remove_circle_outline;
      case 'ENTREGA':
        return Icons.output_rounded;
      case 'DEVOLUCION':
        return Icons.keyboard_return_rounded;
      case 'RELEVO':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.local_laundry_service_outlined;
    }
  }

  Widget _boton(String texto, String op, IconData icono) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: _granja.isEmpty ? null : () => _operacion(op),
        style: FilledButton.styleFrom(
          backgroundColor: _verde,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        icon: Icon(icono, size: 22),
        label: Text(texto),
      ),
    );
  }
}

class AlmacenDialogoResult {
  const AlmacenDialogoResult({
    required this.item,
    required this.cantidad,
    required this.dni,
    this.personalId = 0,
    this.dniEntra = '',
    this.personalIdEntra = 0,
  });

  final Map<String, dynamic> item;
  final int cantidad;
  final String dni;
  final int personalId;
  final String dniEntra;
  final int personalIdEntra;
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
    this.pideEntrante = false,
    this.pideCantidad = true,
    this.eligeItem = true,
  });

  final String titulo;
  final String etiquetaItem;
  final List<Map<String, dynamic>> items;
  final int? inicial;
  final bool pideTrabajador;
  final bool pideEntrante;
  final bool pideCantidad;
  final bool eligeItem;
  final List<({String dni, String nombre, int id})> trabajadores;
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
  int _personalId = 0;
  String _dniEntra = '';
  String _nombreEntra = '';
  int _personalIdEntra = 0;

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
    if (widget.trabajadores.length == 1) {
      _personalId = widget.trabajadores.first.id;
    }
  }

  @override
  void dispose() {
    _cant.dispose();
    _dni.dispose();
    super.dispose();
  }

  int? _clave(Map<String, dynamic> m) =>
      int.tryParse('${m['id'] ?? m['codigo']}');

  Future<({String dni, String nombre, int id})?> _elegirPersona() {
    return showModalBottomSheet<({String dni, String nombre, int id})>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final t in widget.trabajadores)
              ListTile(
                title: Text(t.nombre.isEmpty ? t.dni : '${t.dni} · ${t.nombre}'),
                onTap: () => Navigator.pop(sheet, t),
              ),
          ],
        ),
      ),
    );
  }

  void _guardar() {
    final n = int.tryParse(_cant.text.trim());
    if (n == null || n < 1) return;
    Navigator.of(context).pop(
      AlmacenDialogoResult(
        item: _item,
        cantidad: n,
        dni: _dni.text,
        personalId: _personalId,
        dniEntra: _dniEntra,
        personalIdEntra: _personalIdEntra,
      ),
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
            if (widget.eligeItem)
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
            if (widget.eligeItem) const SizedBox(height: 8),
            if (widget.pideCantidad)
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
            if (widget.pideTrabajador || widget.pideEntrante) ...[
              const SizedBox(height: 8),
              EvidenciaSelectField(
                label: widget.pideEntrante ? 'Saliente' : 'Trabajador',
                value: etiqueta,
                placeholder: 'DNI',
                icon: Icons.person_outline,
                iconColor: _verde,
                onTap: widget.trabajadores.isEmpty
                    ? null
                    : () async {
                        final e = await _elegirPersona();
                        if (e == null) return;
                        setState(() {
                          _dni.text = e.dni;
                          _nombre = e.nombre;
                          _personalId = e.id;
                        });
                      },
              ),
              if (widget.pideEntrante) ...[
                const SizedBox(height: 8),
                EvidenciaSelectField(
                  label: 'Entrante',
                  value: _dniEntra.isEmpty
                      ? ''
                      : (_nombreEntra.isEmpty ? _dniEntra : '$_dniEntra · $_nombreEntra'),
                  placeholder: 'DNI',
                  icon: Icons.person_outline,
                  iconColor: _verde,
                  onTap: widget.trabajadores.isEmpty
                      ? null
                      : () async {
                          final e = await _elegirPersona();
                          if (e == null) return;
                          setState(() {
                            _dniEntra = e.dni;
                            _nombreEntra = e.nombre;
                            _personalIdEntra = e.id;
                          });
                        },
                ),
              ],
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
                    if (t.dni == v) {
                      _nombre = t.nombre;
                      _personalId = t.id;
                    }
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
