/// Anomalía y agente causal según el punto donde se registra.
/// El operador no los edita: solo confirma la acción.
class AnomaliaContexto {
  const AnomaliaContexto({
    required this.anomalia,
    required this.agenteCausal,
    required this.accion,
  });

  final String anomalia;
  final String agenteCausal;
  final String accion;

  static AnomaliaContexto punto({required String instalacion}) {
    final punto = instalacion.trim().isEmpty ? 'Garita' : instalacion.trim();
    return AnomaliaContexto(
      anomalia: _corta('Anomalía $punto', 30),
      agenteCausal: _corta('Control $punto', 200),
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
      accion: 'Retener o rechazar el artículo.',
    );
  }

  static AnomaliaContexto articuloSinDesinfeccion(String nombre) {
    final n = nombre.trim().isEmpty ? 'artículo' : nombre.trim();
    return AnomaliaContexto(
      anomalia: 'Artículo sin desinfección al ingreso: $n.',
      agenteCausal: 'Falta de desinfección de material en control de ingreso.',
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
      accion: accionDef.trim(),
    );
  }
}

String _corta(String s, int n) {
  final t = s.trim();
  if (t.length <= n) return t;
  return t.substring(0, n);
}
