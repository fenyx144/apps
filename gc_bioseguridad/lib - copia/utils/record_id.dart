/// UUID generado en la app al guardar (offline). Viaja como `id` al subir; el
/// servidor persiste ingreso/salida/anomalías con esa misma clave.
class EvidenciaRecordId {
  EvidenciaRecordId._();

  static const _legacyKeys = ['id', 'tuuid', 'serverId'];

  static String of(Map<String, dynamic> record) {
    for (final key in _legacyKeys) {
      final value = record[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  /// Normaliza registros guardados antes del cambio id=UUID.
  static Map<String, dynamic> normalize(Map<String, dynamic> record) {
    final id = of(record);
    final out = Map<String, dynamic>.from(record);
    if (id.isNotEmpty) {
      out['id'] = id;
    }
    out.remove('tuuid');
    out.remove('serverId');
    return out;
  }

  static bool hadLegacyFields(Map<String, dynamic> record) {
    return record.containsKey('tuuid') || record.containsKey('serverId');
  }
}
