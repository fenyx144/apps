/// Línea de `bio_almacen_mov`: stock = SI + E − S por frente e ítem.
class AlmacenLinea {
  AlmacenLinea({
    required this.frente,
    required this.item,
    required this.nombre,
    this.unidad = '',
    this.si = 0,
    this.e = 0,
    this.s = 0,
  });

  /// LIMPIO, LAVADERO, IMPLEMENTOS o INSUMOS.
  final String frente;

  /// Ropa `1`/`2`, o id de insumo si el frente no es ropa.
  final String item;
  final String nombre;
  final String unidad;
  double si;
  double e;
  double s;

  double get stock => si + e - s;

  AlmacenLinea copy() => AlmacenLinea(
        frente: frente,
        item: item,
        nombre: nombre,
        unidad: unidad,
        si: si,
        e: e,
        s: s,
      );

  static AlmacenLinea fromMap(Map<String, dynamic> m) {
    return AlmacenLinea(
      frente: (m['frente'] ?? m['almacen'] ?? '').toString(),
      item: (m['item'] ?? m['insumo_id'] ?? '').toString(),
      nombre: (m['nombre'] ?? '').toString(),
      unidad: (m['unidad'] ?? '').toString(),
      si: _n(m['si']),
      e: _n(m['e']),
      s: _n(m['s']),
    );
  }
}

double _n(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

double stockAlmacen(List<AlmacenLinea> lineas, String frente, String item) {
  for (final l in lineas) {
    if (l.frente == frente && l.item == item) return l.stock;
  }
  return 0;
}

/// `null` si la operación cabe en el stock.
String? rechazoAlmacen(
  List<AlmacenLinea> lineas, {
  required String operacion,
  required String item,
  required double cantidad,
  String categoria = '',
}) {
  final op = operacion.toUpperCase();
  final cat = categoria.toUpperCase();
  if (op == 'RELEVO') {
    if (stockAlmacen(lineas, 'LIMPIO', '2') + 0.001 < 1) return 'Sin stock';
    return null;
  }
  if (cantidad <= 0) return 'Sin stock';
  if (op == 'ENTREGA') {
    final frente = cat == 'IMPLEMENTO' ? 'IMPLEMENTOS' : 'LIMPIO';
    if (cantidad > stockAlmacen(lineas, frente, item) + 0.001) return 'Sin stock';
  }
  if (op == 'LAVADO' && cantidad > stockAlmacen(lineas, 'LAVADERO', item) + 0.001) {
    return 'Sin stock';
  }
  if (op == 'CONSUMO' && cantidad > stockAlmacen(lineas, 'INSUMOS', item) + 0.001) {
    return 'Sin stock';
  }
  return null;
}

/// Aplica la cola local. CONSUMO no toca LIMPIO ni LAVADERO.
List<AlmacenLinea> aplicarAlmacen(
  List<AlmacenLinea> base,
  List<Map<String, dynamic>> ops,
) {
  final lineas = base.map((e) => e.copy()).toList();
  for (final op in ops) {
    if (op['synced'] == true) continue;
    final oper = (op['operacion'] ?? '').toString().toUpperCase();
    final cant = _n(op['cantidad']);
    if (cant <= 0) continue;
    final item = (op['item'] ?? op['insumo_id'] ?? op['ropa_tipo'] ?? '2').toString();
    final nombre = (op['nombre_insumo'] ?? op['nombre'] ?? '').toString();
    final cat = (op['categoria'] ?? '').toString();
    if (rechazoAlmacen(lineas, operacion: oper, item: item, cantidad: cant, categoria: cat) !=
        null) {
      continue;
    }
    if (oper == 'ENTREGA') {
      final frente = cat.toUpperCase() == 'IMPLEMENTO' ? 'IMPLEMENTOS' : 'LIMPIO';
      _sumar(lineas, frente, item, nombre, s: cant);
    } else if (oper == 'DEVOLUCION' || oper == 'RECEPCION') {
      final frente = cat.toUpperCase() == 'IMPLEMENTO' ? 'IMPLEMENTOS' : 'LAVADERO';
      _sumar(lineas, frente, item, nombre, e: cant);
    } else if (oper == 'LAVADO') {
      _sumar(lineas, 'LAVADERO', item, nombre, s: cant);
      _sumar(lineas, 'LIMPIO', item, nombre, e: cant);
    } else if (oper == 'CONSUMO') {
      _sumar(lineas, 'INSUMOS', item, nombre, s: cant);
    } else if (oper == 'ENVIO' || oper == 'SI') {
      final frente = _frenteCategoria(cat, item);
      _sumar(
        lineas,
        frente,
        item,
        nombre,
        si: oper == 'SI' ? cant : 0,
        e: oper == 'ENVIO' ? cant : 0,
      );
    } else if (oper == 'RELEVO') {
      _sumar(lineas, 'LAVADERO', '2', 'Ropa para el proceso', e: 1);
      _sumar(lineas, 'LIMPIO', '2', 'Ropa para el proceso', s: 1);
      final imps = lineas.where((l) => l.frente == 'IMPLEMENTOS' && l.stock + 0.001 >= 1).toList();
      for (final l in imps) {
        _sumar(lineas, 'IMPLEMENTOS', l.item, l.nombre, s: 1);
        _sumar(lineas, 'IMPLEMENTOS', l.item, l.nombre, e: 1);
      }
    } else if (oper == 'SI_UNIFORME' || oper == 'CARGA_UNIFORME') {
      final frente = (op['frente'] ?? 'LIMPIO').toString();
      _sumar(lineas, frente == 'LAVADERO' ? 'LAVADERO' : 'LIMPIO', item, nombre,
          si: oper == 'SI_UNIFORME' ? cant : 0, e: oper == 'CARGA_UNIFORME' ? cant : 0);
    } else if (oper == 'SI_INSUMO') {
      _sumar(lineas, 'INSUMOS', item, nombre, si: cant);
    } else if (oper == 'CARGA_INSUMO') {
      _sumar(lineas, 'INSUMOS', item, nombre, e: cant);
    }
  }
  return lineas;
}

String _frenteCategoria(String categoria, String item) {
  final cat = categoria.toUpperCase();
  if (cat == 'IMPLEMENTO') return 'IMPLEMENTOS';
  if (cat == 'INSUMO') return 'INSUMOS';
  if (cat == 'UNIFORME' || item == '1' || item == '2') return 'LIMPIO';
  return 'INSUMOS';
}

void _sumar(
  List<AlmacenLinea> lineas,
  String frente,
  String item,
  String nombre, {
  double si = 0,
  double e = 0,
  double s = 0,
}) {
  final i = lineas.indexWhere((l) => l.frente == frente && l.item == item);
  if (i < 0) {
    lineas.add(AlmacenLinea(frente: frente, item: item, nombre: nombre, si: si, e: e, s: s));
    return;
  }
  lineas[i].si += si;
  lineas[i].e += e;
  lineas[i].s += s;
}
