import 'analisis_seleccionado.dart';

class Muestra {
  String? fechaToma;
  int numeroMuestras;
  String? tipoMuestraCodigo;
  String? tipoMuestraNombre;
  String origenMuestra;
  String edad;
  String codigoReferencia;
  int? numMachos;
  int? numHembras;
  String griSeleccion;
  //List<String> analisisSeleccionados;
  List<AnalisisSeleccionado> analisisSeleccionados;
  List<String> paquetesSeleccionados;
  String observaciones;

  Muestra({
    this.fechaToma,
    this.numeroMuestras = 1,
    this.tipoMuestraCodigo,
    this.origenMuestra = 'GRS',
    this.edad = '',
    this.codigoReferencia = '',
    this.numMachos,
    this.numHembras,
    this.griSeleccion = '',
    this.analisisSeleccionados = const [],
    this.paquetesSeleccionados = const [],
    this.observaciones = '',
  });

  Map<String, dynamic> toJson(int index) {
    return {
      'fechaToma_$index': fechaToma,
      'numeroMuestras_$index': numeroMuestras,
      'tipoMuestra_$index': tipoMuestraCodigo,
      'origenMuestra_$index': origenMuestra,
      'edad_$index': edad,
      'codigoReferenciaValue_$index': codigoReferencia,
      if (numMachos != null) 'numMachos_$index': numMachos,
      if (numHembras != null) 'numHembras_$index': numHembras,
      if (griSeleccion.isNotEmpty) 'gri_seleccion_$index': griSeleccion,
      //'analisis_$index': analisisSeleccionados,
      'analisis_$index': analisisSeleccionados.map((a) => a.toJson()).toList(),
      'observaciones_$index': observaciones,
      'paquetesSeleccionados_$index': paquetesSeleccionados,
    };
  }
}