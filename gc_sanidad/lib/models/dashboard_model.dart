class EnviosData {
  final List<String> labels;
  final List<int> data;
  EnviosData(this.labels, this.data);
  factory EnviosData.fromMap(Map<String, dynamic> json) => EnviosData(
    List<String>.from(json['labels']),
    List<int>.from(json['data']),
  );
}

class EstadoData {
  final int pendientes;
  final int completados;
  EstadoData(this.pendientes, this.completados);
  factory EstadoData.fromMap(Map<String, dynamic> json) =>
      EstadoData(json['pendientes'], json['completados']);
}

class TopAnalisisData {
  final List<String> labels;
  final List<int> data;
  TopAnalisisData(this.labels, this.data);
  factory TopAnalisisData.fromMap(Map<String, dynamic> json) =>
      TopAnalisisData(
        List<String>.from(json['labels'] ?? []),
        (json['data'] as List?)?.map((e) => e is int ? e : int.tryParse('$e') ?? 0).toList() ?? [],
      );
}

class DemoraData {
  final List<String> labels;
  final List<double> data;
  DemoraData(this.labels, this.data);
  factory DemoraData.fromMap(Map<String, dynamic> json) {
    final labels = List<String>.from(json['labels'] ?? []);
    final rawData = json['data'] as List?;

    final data =
        rawData?.map((e) {
          if (e is num) {
            return e.toDouble();
          } else if (e is String) {
            return double.parse(e);
          } else {
            return 0.0;
          }
        }).toList() ??
        [];

    return DemoraData(labels, data);
  }
}

class TopItem {
  final String name;
  final int total;
  TopItem(this.name, this.total);
}
