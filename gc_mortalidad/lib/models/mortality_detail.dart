import 'package:uuid/uuid.dart';

class MortalityDetail {
  final String id;
  final String sexo;
  final int cantidad;
  final String? causaCodigo;
  final String? causaNombre;
  final String? observacion;
  final List<String> fotos;
  /// Agrupa machos y hembras ingresados en la misma sesión del diálogo.
  final String? grupoId;
  /// Cantidad de aves por etapa del proceso de despacho
  /// (columna camelCase → cantidad). Solo aplica a mortalidad tipo Despacho.
  final Map<String, int> procesoEtapas;

  const MortalityDetail({
    required this.id,
    required this.sexo,
    required this.cantidad,
    this.causaCodigo,
    this.causaNombre,
    this.observacion,
    this.fotos = const [],
    this.grupoId,
    this.procesoEtapas = const {},
  });

  bool get isMacho => sexo == 'M';
  bool get isHembra => sexo == 'H';

  String get sexoLabel => isMacho ? 'Machos' : 'Hembras';

  /// Hay algo que persistir: aves, observación o fotos.
  bool get hasContent =>
      cantidad > 0 ||
      (observacion?.trim().isNotEmpty ?? false) ||
      fotos.isNotEmpty ||
      procesoEtapas.values.any((v) => v > 0);

  /// Suma de las cantidades de las etapas de despacho de este detalle.
  int get procesoTotal =>
      procesoEtapas.values.fold(0, (sum, v) => sum + v);

  /// Valor de una etapa concreta (0 si no está registrada).
  int procesoEtapa(String etapaId) => procesoEtapas[etapaId] ?? 0;

  MortalityDetail copyWith({
    String? id,
    String? sexo,
    int? cantidad,
    String? causaCodigo,
    String? causaNombre,
    String? observacion,
    List<String>? fotos,
    String? grupoId,
    Map<String, int>? procesoEtapas,
  }) {
    return MortalityDetail(
      id: id ?? this.id,
      sexo: sexo ?? this.sexo,
      cantidad: cantidad ?? this.cantidad,
      causaCodigo: causaCodigo ?? this.causaCodigo,
      causaNombre: causaNombre ?? this.causaNombre,
      observacion: observacion ?? this.observacion,
      fotos: fotos ?? this.fotos,
      grupoId: grupoId ?? this.grupoId,
      procesoEtapas: procesoEtapas ?? this.procesoEtapas,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sexo': sexo,
        'cantidad': cantidad,
        'causa_codigo': causaCodigo ?? '',
        'causa_nombre': causaNombre ?? '',
        'observacion': observacion ?? '',
        'grupo_id': grupoId ?? '',
        'proceso_etapas': procesoEtapas.isEmpty
            ? null
            : procesoEtapas.map((k, v) => MapEntry(k, v)),
        'fotos': fotos.map((p) => {'path': p}).toList(),
      };

  factory MortalityDetail.fromJson(Map<String, dynamic> json) {
    final fotosRaw = json['fotos'];
    final paths = <String>[];
    if (fotosRaw is List) {
      for (final f in fotosRaw) {
        if (f is Map && f['path'] != null) {
          paths.add(f['path'].toString());
        } else if (f is String && f.isNotEmpty) {
          paths.add(f);
        }
      }
    }
    final obs = json['observacion']?.toString().trim();
    final grupoRaw = json['grupo_id']?.toString().trim();

    // Etapas de despacho desde el sub-mapa 'proceso_etapas' (claves camelCase).
    final procesoEtapas = <String, int>{};
    final peRaw = json['proceso_etapas'];
    if (peRaw is Map) {
      peRaw.forEach((k, v) {
        final parsed = int.tryParse(v?.toString() ?? '');
        if (parsed != null && parsed > 0) {
          procesoEtapas[k.toString()] = parsed;
        }
      });
    }

    return MortalityDetail(
      id: json['id']?.toString() ?? const Uuid().v4(),
      sexo: json['sexo']?.toString() ?? 'M',
      cantidad: int.tryParse(json['cantidad']?.toString() ?? '0') ?? 0,
      causaCodigo: json['causa_codigo']?.toString(),
      causaNombre: json['causa_nombre']?.toString(),
      observacion: obs != null && obs.isNotEmpty ? obs : null,
      fotos: paths,
      grupoId: grupoRaw != null && grupoRaw.isNotEmpty ? grupoRaw : null,
      procesoEtapas: procesoEtapas,
    );
  }

  static List<MortalityDetail> listFromRecord(Map<String, dynamic> record) {
    final raw = record['detalles'];
    if (raw is List && raw.isNotEmpty) {
      return raw
          .whereType<Map>()
          .map((e) => MortalityDetail.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final details = <MortalityDetail>[];
    final fotosRaw = record['fotos'];
    final globalFotos = <String>[];
    if (fotosRaw is List) {
      for (final f in fotosRaw) {
        if (f is Map && f['path'] != null) {
          globalFotos.add(f['path'].toString());
        }
      }
    }

    final cantM = int.tryParse(record['cant_machos']?.toString() ?? '0') ?? 0;
    final cantH = int.tryParse(record['cant_hembras']?.toString() ?? '0') ?? 0;

    final legacyGrupoId = const Uuid().v4();
    if (cantM > 0) {
      details.add(MortalityDetail(
        id: const Uuid().v4(),
        sexo: 'M',
        cantidad: cantM,
        causaCodigo: record['causa_machos']?.toString(),
        causaNombre: record['causa_machos_nombre']?.toString(),
        fotos: globalFotos,
        grupoId: cantH > 0 ? legacyGrupoId : null,
      ));
    }
    if (cantH > 0) {
      details.add(MortalityDetail(
        id: const Uuid().v4(),
        sexo: 'H',
        cantidad: cantH,
        causaCodigo: record['causa_hembras']?.toString(),
        causaNombre: record['causa_hembras_nombre']?.toString(),
        fotos: cantM > 0 ? [] : globalFotos,
        grupoId: cantM > 0 ? legacyGrupoId : null,
      ));
    }
    return details;
  }

  static int totalMachos(List<MortalityDetail> details) =>
      details.where((d) => d.isMacho).fold(0, (s, d) => s + d.cantidad);

  static int totalHembras(List<MortalityDetail> details) =>
      details.where((d) => d.isHembra).fold(0, (s, d) => s + d.cantidad);

  static List<String> allPhotoPaths(List<MortalityDetail> details) {
    final paths = <String>[];
    for (final d in details) {
      paths.addAll(d.fotos);
    }
    return paths;
  }
}

/// Par machos/hembras registrados en una misma sesión del diálogo.
class MortalityDetailGroup {
  final String grupoId;
  final MortalityDetail? macho;
  final MortalityDetail? hembra;

  const MortalityDetailGroup({
    required this.grupoId,
    this.macho,
    this.hembra,
  });

  int get totalCantidad => (macho?.cantidad ?? 0) + (hembra?.cantidad ?? 0);

  Iterable<MortalityDetail> get items sync* {
    if (macho != null) yield macho!;
    if (hembra != null) yield hembra!;
  }

  static List<MortalityDetailGroup> fromList(List<MortalityDetail> detalles) {
    final buckets = <String, List<MortalityDetail>>{};
    final order = <String>[];

    for (final d in detalles) {
      final gid = d.grupoId ?? d.id;
      if (!buckets.containsKey(gid)) {
        buckets[gid] = [];
        order.add(gid);
      }
      buckets[gid]!.add(d);
    }

    MortalityDetail? pick(String sexo, List<MortalityDetail> items) {
      for (final d in items) {
        if (d.sexo == sexo) return d;
      }
      return null;
    }

    return order.map((gid) {
      final items = buckets[gid]!;
      return MortalityDetailGroup(
        grupoId: gid,
        macho: pick('M', items),
        hembra: pick('H', items),
      );
    }).toList();
  }
}
