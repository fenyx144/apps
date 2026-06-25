class OrigenAves {
  final String codigo;

  const OrigenAves({required this.codigo});

  factory OrigenAves.fromJson(Map<String, dynamic> json) {
    return OrigenAves(codigo: (json['codigo'] ?? '').toString().trim());
  }

  Map<String, dynamic> toJson() => {'codigo': codigo};
}
