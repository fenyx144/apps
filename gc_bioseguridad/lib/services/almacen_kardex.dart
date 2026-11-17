/// Línea de kardex: stock = SI + E − S.
class AlmacenLinea {
  AlmacenLinea({
    required this.insumoId,
    required this.codigo,
    required this.nombre,
    required this.categoria,
    required this.unidad,
    required this.almacen,
    this.si = 0,
    this.e = 0,
    this.s = 0,
  });

  final int insumoId;
  final String codigo;
  final String nombre;
  final String categoria;
  final String unidad;
  final String almacen;
  double si;
  double e;
  double s;

  double get stock => si + e - s;

  AlmacenLinea copy() => AlmacenLinea(
        insumoId: insumoId,
        codigo: codigo,
        nombre: nombre,
        categoria: categoria,
        unidad: unidad,
        almacen: almacen,
        si: si,
        e: e,
        s: s,
      );

  static AlmacenLinea fromMap(Map<String, dynamic> m) {
    return AlmacenLinea(
      insumoId: int.tryParse('${m['insumo_id']}') ?? 0,
      codigo: (m['codigo'] ?? '').toString(),
      nombre: (m['nombre'] ?? '').toString(),
      categoria: (m['categoria'] ?? '').toString(),
      unidad: (m['unidad'] ?? '').toString(),
      almacen: (m['almacen'] ?? '').toString(),
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

/// Aplica operaciones aún no confirmadas sobre el kardex del servidor.
List<AlmacenLinea> aplicarAlmacen(
  List<AlmacenLinea> base,
  List<Map<String, dynamic>> ops,
) {
  final lineas = base.map((e) => e.copy()).toList();
  for (final op in ops) {
    if (op['synced'] == true) continue;
    final id = int.tryParse('${op['insumo_id']}') ?? 0;
    final cod = (op['codigo'] ?? '').toString();
    final nom = (op['nombre_insumo'] ?? op['insumo'] ?? '').toString();
    final cat = (op['categoria'] ?? '').toString();
    final und = (op['unidad'] ?? '').toString();
    final cant = _n(op['cantidad']);
    if (cant <= 0) continue;
    final oper = (op['operacion'] ?? '').toString().toUpperCase();
    if (oper == 'CONSUMO' || oper == 'ENTREGA') {
      _sumar(lineas, id, cod, nom, cat, und, 'LIMPIO', s: cant);
    } else if (oper == 'DEVOLUCION') {
      _sumar(lineas, id, cod, nom, cat, und, 'LAVADERO', e: cant);
    } else if (oper == 'LAVADO') {
      _sumar(lineas, id, cod, nom, cat, und, 'LAVADERO', s: cant);
      _sumar(lineas, id, cod, nom, cat, und, 'LIMPIO', e: cant);
    }
  }
  return lineas;
}

void _sumar(
  List<AlmacenLinea> lineas,
  int id,
  String codigo,
  String nombre,
  String categoria,
  String unidad,
  String almacen, {
  double e = 0,
  double s = 0,
}) {
  final i = lineas.indexWhere((l) {
    if (l.almacen != almacen) return false;
    if (id > 0) return l.insumoId == id;
    return l.codigo == codigo && codigo.isNotEmpty;
  });
  if (i < 0) {
    lineas.add(
      AlmacenLinea(
        insumoId: id,
        codigo: codigo,
        nombre: nombre,
        categoria: categoria,
        unidad: unidad,
        almacen: almacen,
        e: e,
        s: s,
      ),
    );
    return;
  }
  lineas[i].e += e;
  lineas[i].s += s;
}
