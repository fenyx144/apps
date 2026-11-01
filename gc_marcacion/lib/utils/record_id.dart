/// Identificador UUID de evidencia (mismo valor que `san_evidencias.id` en el servidor).
class EvidenciaRecordId {
  EvidenciaRecordId._();

  static final RegExp _uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static const _legacyKeys = ['id', 'tuuid', 'serverId'];

  /// Valida formato UUID v4 (el que genera `package:uuid`).
  static bool isUuidV4(String? raw) {
    final id = raw?.trim() ?? '';
    return id.isNotEmpty && _uuidV4.hasMatch(id);
  }

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
