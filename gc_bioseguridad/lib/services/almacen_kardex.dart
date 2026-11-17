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

  /// LIMPIO, LAVADERO o INSUMOS.
  final String frente;

  /// Ropa `1`/`2`, o id de insumo si [frente] es INSUMOS.
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

/// `null` si la operación cabe en el stock. El consumo solo mira INSUMOS.
String? rechazoAlmacen(
  List<AlmacenLinea> lineas, {
  required String operacion,
  required String item,
  required double cantidad,
}) {
  final op = operacion.toUpperCase();
  if (cantidad <= 0) return 'Sin stock';
  if (op == 'ENTREGA' && cantidad > stockAlmacen(lineas, 'LIMPIO', item) + 0.001) {
    return 'Sin stock';
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
    if (rechazoAlmacen(lineas, operacion: oper, item: item, cantidad: cant) != null) {
      continue;
    }
    if (oper == 'ENTREGA') {
      _sumar(lineas, 'LIMPIO', item, nombre, s: cant);
    } else if (oper == 'RECEPCION') {
      _sumar(lineas, 'LAVADERO', item, nombre, e: cant);
    } else if (oper == 'LAVADO') {
      _sumar(lineas, 'LAVADERO', item, nombre, s: cant);
      _sumar(lineas, 'LIMPIO', item, nombre, e: cant);
    } else if (oper == 'CONSUMO') {
      _sumar(lineas, 'INSUMOS', item, nombre, s: cant);
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
