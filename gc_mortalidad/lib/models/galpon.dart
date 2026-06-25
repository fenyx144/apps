class Galpon {
  final String tcencos;
  final String tcodint;
  final String? fecIngMin;
  final String edad;

  Galpon({
    required this.tcencos,
    required this.tcodint,
    this.fecIngMin,
    this.edad = '0',
  });

  factory Galpon.fromJson(Map<String, dynamic> json) {
    return Galpon(
      tcencos: json['tcencos']?.toString() ?? '',
      tcodint: json['tcodint']?.toString() ?? '',
      fecIngMin: json['fec_ing_min']?.toString(),
      edad: json['edad']?.toString() ?? '0',
    );
  }
}
