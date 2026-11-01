/// Armado de los payloads que viajan al backend de Vacuna al Agua.
///
/// Las claves de estas funciones son un **contrato** con
/// `sanidad/flutter/vacunaagua/vacunaagua_guardar_lib.php`: si cambian ahí,
/// la subida falla con `MISSING_HORAS`, `MISSING_GALPONES` o `MISSING_VACUNA`.
/// Por eso viven fuera de las pantallas y con test propio
/// (`test/vacuna_payload_test.dart`).
library;

/// Un paso de la cadena de frío: descripción fija, hora y temperatura.
typedef FrioPaso = ({String descripcion, String hora, double temperatura});

/// Un recurso del equipo de vacunación con su estado y observación.
typedef EquipoRecurso = ({
  String recurso,
  bool operativo,
  String descripcion,
});

/// Nombres de sección del detalle paramétrico. Son el contrato con la columna
/// `seccion` de `san_fact_vacunaagua_det` (ver `VAC_SECCIONES_DET` en el PHP).
abstract final class VacSeccion {
  static const cadena = 'cadena';
  static const equipo = 'equipo';
  static const sedeo = 'sedeo';
  static const bebederos = 'bebederos';
  static const solucion = 'solucion';
  static const eficiencia = 'eficiencia';
}

/// Una fila del detalle paramétrico del backend.
///
/// `seccion` es el bloque del formato y `parametro` el renglón; el valor va en
/// la columna de su tipo: `valorNum` para cantidades, `hora` para horas, `flag`
/// para los sí/no y `valorTexto` para lo demás. `galpon` y `grupo` van vacíos
/// cuando la sección no los usa (`grupo` es el sub-encabezado: el bloque de
/// bebederos o Macho/hembra en eficiencia).
///
/// Las claves se mandan siempre, aunque el valor sea `null`: así el contrato es
/// explícito y del lado del servidor no hay que adivinar qué faltó.
Map<String, dynamic> detalleFila({
  required String seccion,
  required String parametro,
  String galpon = '',
  String grupo = '',
  double? valorNum,
  String? valorTexto,
  String? hora,
  bool? flag,
}) {
  return {
    'seccion': seccion,
    'galpon': galpon,
    'grupo': grupo,
    'parametro': parametro,
    'valor_num': valorNum,
    'valor_texto': valorTexto,
    'hora': hora,
    'flag': flag,
  };
}

/// Filas del detalle de la cadena de frío (sección 3 del formato).
List<Map<String, dynamic>> detalleCadenaFrio(List<FrioPaso> pasos) {
  return [
    for (final f in pasos)
      detalleFila(
        seccion: VacSeccion.cadena,
        parametro: f.descripcion,
        hora: f.hora,
        valorNum: f.temperatura,
      ),
  ];
}

/// Filas del detalle del equipo de vacunación (sección 4 del formato).
List<Map<String, dynamic>> detalleEquipo(List<EquipoRecurso> equipo) {
  return [
    for (final e in equipo)
      detalleFila(
        seccion: VacSeccion.equipo,
        parametro: e.recurso,
        flag: e.operativo,
        valorTexto: e.descripcion.isEmpty ? null : e.descripcion,
      ),
  ];
}

/// `registro` de una Decloración de cloro.
///
/// El backend exige `hora_inicio` y `hora_final`; el cloro viaja ya con dos
/// decimales porque la columna es `decimal(5,2)`.
Map<String, dynamic> decloracionRegistro({
  required String horaInicio,
  required String horaFinal,
  required double cloroInicio,
  required double cloroFinal,
  required String responsable,
  required String observacion,
}) {
  return {
    'hora_inicio': horaInicio,
    'hora_final': horaFinal,
    'cloro_inicio': cloroInicio.toStringAsFixed(2),
    'cloro_final': cloroFinal.toStringAsFixed(2),
    'responsable': responsable,
    'observacion': observacion,
    // Decloración aplica a toda la granja; la web/listados muestran «TODOS».
    'galpones': const ['TODOS'],
    'galpones_todos': true,
  };
}

/// `registro` de una Vacunación al agua.
///
/// El detalle lleva todas las secciones del formato (3 a 8) en la forma del
/// detalle paramétrico del backend: cadena de frío, equipo, tiempo de sedeó,
/// bebederos, solución vacunal y evaluación de eficiencia. Los galpones van
/// solo como la lista elegida: no hay campo «todos», porque el servidor puede
/// deducirlo comparando con el catálogo de la granja y campaña.
///
/// `responsable` es el **nombre del usuario** que registra (el del login, no su
/// código): la sección de vacunación no pide responsable en pantalla, pero el
/// listado lo muestra, así que se guarda explícito en vez de dejarlo vacío.
Map<String, dynamic> vacunacionRegistro({
  required List<String> galpones,
  required int? edad,
  required String vacuna,
  required String lote,
  required DateTime? expiracion,
  required String dosisFrasco,
  required String laboratorio,
  required String responsable,
  required List<Map<String, dynamic>> detalle,
}) {
  return {
    'galpones': galpones,
    'edad': edad ?? 0,
    'vacuna': vacuna,
    'lote': lote,
    'expiracion': expiracion == null
        ? ''
        : '${expiracion.year.toString().padLeft(4, '0')}-'
            '${expiracion.month.toString().padLeft(2, '0')}-'
            '${expiracion.day.toString().padLeft(2, '0')}',
    'dosis_frasco': dosisFrasco,
    'laboratorio': laboratorio,
    'responsable': responsable,
    'detalle': detalle,
  };
}
