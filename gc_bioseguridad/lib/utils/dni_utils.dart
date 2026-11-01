/// Utilidades de DNI compartidas por Control de ingreso, el resumen y los
/// reportes locales.
///
/// El DNI se puede escribir a mano o leer con el escáner (QR o código de
/// barras). Cuando se escanea, la app consulta el nombre en el backend, así que
/// un registro maneja pares documento + nombre y no solo el número.
library;

/// Un DNI con el nombre que devolvió la consulta (vacío si no se consultó).
class DniEntrada {
  const DniEntrada({required this.dni, this.nombre = ''});

  final String dni;
  final String nombre;

  /// «12345678 · JUAN PEREZ» o solo el número si no hay nombre.
  String get etiqueta => nombre.isEmpty ? dni : '$dni · $nombre';

  Map<String, dynamic> toJson() => {'dni': dni, 'nombre': nombre};

  @override
  String toString() => etiqueta;
}

/// Interpreta el contenido leído por el escáner y extrae el DNI de 8 dígitos.
///
/// El DNI peruano trae el número en un código de barras; según el modelo el
/// contenido es solo el número, un PDF417 con el número al inicio, o una trama
/// separada por «|», «,» o espacios. Se prueban esos casos de más preciso a
/// menos para no confundir el DNI con otros números del mismo código.
abstract final class DniCodeParser {
  static final RegExp _soloOcho = RegExp(r'^\d{8}$');
  static final RegExp _separadores = RegExp(r'[|,;/\s]+');
  static final RegExp _inicio = RegExp(r'^(\d{8})\D');
  static final RegExp _ochoDigitos = RegExp(r'\d{8}');

  /// Devuelve el DNI contenido en [raw], o `null` si no se puede aislar.
  static String? parse(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return null;

    // Caso ideal: el código trae únicamente el número.
    if (_soloOcho.hasMatch(s)) return s;

    // Tramas separadas por «|», comas, punto y coma, barras o espacios.
    for (final token in s.split(_separadores)) {
      final t = token.trim();
      if (_soloOcho.hasMatch(t)) return t;
    }

    // El número pegado al inicio del contenido (PDF417 del DNI electrónico).
    final alInicio = _inicio.firstMatch(s);
    if (alInicio != null) return alInicio.group(1);

    // Último recurso: solo si el contenido tiene un único bloque de 8 dígitos.
    final bloques = _ochoDigitos
        .allMatches(s)
        .map((m) => m.group(0)!)
        .toSet();
    return bloques.length == 1 ? bloques.first : null;
  }
}

/// Convierte el campo `dnis` de un registro en entradas tipadas.
///
/// Acepta los tres formatos que existen en la app: pares `{dni, nombre}` (lo
/// que guarda el formulario), lista de números (registros anteriores al
/// escáner) y texto separado por comas (reportes que vienen del backend).
List<DniEntrada> parseDnisEntradas(dynamic raw) {
  final out = <DniEntrada>[];
  final vistos = <String>{};

  void agregar(dynamic dni, dynamic nombre) {
    final d = dni?.toString().trim() ?? '';
    if (d.isEmpty || !vistos.add(d)) return;
    out.add(DniEntrada(dni: d, nombre: nombre?.toString().trim() ?? ''));
  }

  if (raw is List) {
    for (final e in raw) {
      if (e is Map) {
        agregar(e['dni'], e['nombre']);
      } else {
        agregar(e, '');
      }
    }
    return out;
  }

  if (raw is Map) {
    agregar(raw['dni'], raw['nombre']);
    return out;
  }

  final s = raw?.toString().trim() ?? '';
  if (s.isEmpty) return out;
  for (final d in s.split(',')) {
    agregar(d, '');
  }
  return out;
}

/// Solo los números de DNI, en el orden declarado.
List<String> listaDnisNumeros(dynamic raw) =>
    parseDnisEntradas(raw).map((d) => d.dni).toList();

/// Nombre que acompaña a un DNI en el registro.
///
/// Manda el nombre que resolvió la consulta (en línea o del catálogo local) y,
/// si no hubo ninguno —sin conexión y el documento fuera del catálogo—, se usa
/// el que escribió el operador a mano. Vacío en los dos casos no es un error:
/// los DNIs son opcionales y el nombre nunca fue obligatorio.
String nombreDniEfectivo({required String resuelto, required String manual}) {
  final r = resuelto.trim();
  return r.isNotEmpty ? r : manual.trim();
}
