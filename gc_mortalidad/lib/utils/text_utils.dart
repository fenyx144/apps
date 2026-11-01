// Utilidades de texto compartidas.

/// Recorta el texto y pone la primera letra en mayúscula (letra capital).
String capitalizeText(String? value) {
  final t = value?.trim() ?? '';
  if (t.isEmpty) return t;
  return t[0].toUpperCase() + t.substring(1);
}

/// Texto a mostrar cuando no hay observaciones en resúmenes.
const String kSinObservaciones = 'Sin observaciones';

/// Edad en días: DATEDIFF(fechaReferencia, fecIngMin) + 1 (misma lógica que el backend).
int? computeEdadInDias(String? fecIngMin, [DateTime? fechaReferencia]) {
  final raw = fecIngMin?.trim() ?? '';
  if (raw.isEmpty || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return null;
  }

  final parts = raw.split('-');
  final year = int.tryParse(parts[0]);
  if (year == null || year <= 1900) return null;

  final ingreso = DateTime(
    year,
    int.parse(parts[1]),
    int.parse(parts[2]),
  );
  final ref = fechaReferencia ?? DateTime.now();
  final hoy = DateTime(ref.year, ref.month, ref.day);
  final dias = hoy.difference(ingreso).inDays + 1;
  return dias > 0 ? dias : null;
}
