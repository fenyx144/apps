/// Anomalía, agente causal y efecto según el punto donde se registra.
/// El operador no los edita: solo confirma la acción.
class AnomaliaContexto {
  const AnomaliaContexto({
    required this.anomalia,
    required this.agenteCausal,
    required this.efecto,
    required this.accion,
  });

  final String anomalia;
  final String agenteCausal;
  final String efecto;
  final String accion;

  static AnomaliaContexto punto({
    required String instalacion,
    required String bioseguridad,
  }) {
    final punto = instalacion.trim().isEmpty ? 'Garita' : instalacion.trim();
    final tipo = bioseguridad.trim().isEmpty
        ? 'Bioseguridad fisica'
        : bioseguridad.trim();
    return AnomaliaContexto(
      anomalia: _corta('Anomalía $punto', 30),
      agenteCausal: _corta('Control $punto', 200),
      efecto: _corta('Hallazgo en $punto · $tipo', 200),
      accion: '',
    );
  }

  static AnomaliaContexto articuloNoPermitido(
    String nombre, {
    String nota = '',
  }) {
    final n = nombre.trim().isEmpty ? 'artículo' : nombre.trim();
    return AnomaliaContexto(
      anomalia: 'Ingreso con artículo no permitido: $n.',
      agenteCausal: nota.trim().isNotEmpty
          ? nota.trim()
          : 'Artículo no autorizado según política de ingreso ($n).',
      efecto: 'Ingreso rechazado de $n.',
      accion: 'Retener o rechazar el artículo.',
    );
  }

  static AnomaliaContexto articuloSinDesinfeccion(String nombre) {
    final n = nombre.trim().isEmpty ? 'artículo' : nombre.trim();
    return AnomaliaContexto(
      anomalia: 'Artículo sin desinfección al ingreso: $n.',
      agenteCausal: 'Falta de desinfección de material en control de ingreso.',
      efecto: 'Material sin desinfección: $n.',
      accion: 'Aplicar desinfección o restringir el ingreso.',
    );
  }

  static AnomaliaContexto alcoholemia({
    required String dni,
    required String nombre,
    required double gradoGl,
    required double umbral,
    required String agenteDef,
    required String accionDef,
  }) {
    final g = gradoGl.toStringAsFixed(3);
    final u = umbral.toStringAsFixed(3);
    final quien = nombre.trim().isNotEmpty
        ? nombre.trim()
        : (dni.trim().isNotEmpty ? 'DNI ${dni.trim()}' : 'Persona');
    return AnomaliaContexto(
      anomalia: '$g g/L supera umbral $u g/L · $quien',
      agenteCausal: agenteDef.trim(),
      efecto: 'Alcoholemia $g g/L (umbral $u) · $quien',
      accion: accionDef.trim(),
    );
  }
}

String _corta(String s, int n) {
  final t = s.trim();
  if (t.length <= n) return t;
  return t.substring(0, n);
}

/// Texto de `rgarita.descripcion` (máx. 200): efecto y acción juntos.
String componerDetalleGarita({
  required String efecto,
  required String accion,
}) {
  final a = accion.trim();
  final e = efecto.trim();
  if (e.isEmpty) return _corta(a, 200);
  if (a.isEmpty) return _corta(e, 200);
  final full = '$e | $a';
  if (full.length <= 200) return full;
  const sep = ' | ';
  final room = 200 - sep.length - a.length;
  if (room < 12) return _corta(a, 200);
  return '${e.substring(0, room)}$sep$a';
}
