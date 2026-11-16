class Galpon {
  final String tcencos;
  final String tcodint;
  final String? fecIngMin; // Fecha de ingreso mínima por galpón (YYYY-MM-DD)

  Galpon({required this.tcencos, required this.tcodint, this.fecIngMin});

  factory Galpon.fromJson(Map<String, dynamic> json) {
    return Galpon(
      tcencos: json['tcencos']?.toString() ?? '',
      tcodint: json['tcodint']?.toString() ?? '',
      fecIngMin: json['fec_ing_min']?.toString(),
    );
  }
}
