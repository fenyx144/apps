import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gc_puesto_mercado_tienda/utils/constants.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/analisis_seleccionado.dart';
import '../services/api_service.dart';
import '../models/muestra.dart';
import '../services/storage_service.dart';

class RegistroEnvioMuestraController with ChangeNotifier {
  // === Campos globales del formulario ===
  String fechaEnvio;
  String horaEnvio;
  String codigoEnvio = 'CARGANDO...';
  String laboratorioId = '';
  String laboratorioNombre = '';
  String empresaTransporteId = '';
  String empresaTransporteNombre = '';
  String autorizadoPor = '';
  String usuarioRegistrador;
  String usuarioResponsable = '';

  // === Solicitudes dinámicas ===
  int _numeroSolicitudes = 0;
  List<Muestra> _solicitudes = [];
  Map<int, Map<String, dynamic>> _cache = {};

  // === Catálogos base ===
  final List<Map<String, dynamic>> _tiposMuestra;
  final List<Map<String, dynamic>> _laboratorios;
  final List<Map<String, dynamic>> _empresasTransporte;

  // Getters públicos
  List<Map<String, dynamic>> get tiposMuestra => _tiposMuestra;
  List<Map<String, dynamic>> get laboratorios => _laboratorios;
  List<Map<String, dynamic>> get empresasTransporte => _empresasTransporte;

  // === Configuración dinámica por solicitud (desde get_config_muestra.php) ===
  Map<int, ConfiguracionMuestra?> _configuraciones = {};
  final Map<String, List<Map<String, dynamic>>> _codigosOrigenCache = {};
  final Map<int, List<Map<String, dynamic>>> _griOpciones = {};
  bool _cargandoGri = false;

  List<Map<String, dynamic>> getGriOpciones(int index) =>
      _griOpciones[index] ?? [];
  bool get cargandoGri => _cargandoGri;

  RegistroEnvioMuestraController({
    required this.fechaEnvio,
    required this.horaEnvio,
    required this.usuarioRegistrador,
    required List<Map<String, dynamic>> tiposMuestra,
    required List<Map<String, dynamic>> laboratorios,
    required List<Map<String, dynamic>> empresasTransporte,
  }) : _tiposMuestra = tiposMuestra,
       _laboratorios = laboratorios,
       _empresasTransporte = empresasTransporte {
    generarCodigoEnvio();
  }
  // En RegistroEnvioMuestraController

  setLaboratorio(String id, String nombre) {
    laboratorioId = id;
    laboratorioNombre = nombre;
    notifyListeners();
  }

  setEmpresaTransporte(String id, String nombre) {
    empresaTransporteId = id;
    empresaTransporteNombre = nombre;
    notifyListeners();
  }

  // === Código de envío ===
  Future<void> generarCodigoEnvio() async {
    try {
      final storage = Provider.of<StorageService>(Get.context!, listen: false);
      final usuarioCodigo = storage.getUserCodeSync() ?? '';

      final res = await ApiService().reserveCodigoEnvio2(usuarioCodigo);
      print('codigoEnvio: ${res}');
      if (res['success'] == true && res['data'] != null) {
        codigoEnvio = res['data']['data']['codigo_envio'];
      } else {
        codigoEnvio = 'PENDIENTE';
      }
    } catch (e) {
      debugPrint('Error al generar código: $e');
      codigoEnvio = 'PENDIENTE';
    }
    notifyListeners();
  }

  // === Gestión de número de solicitudes ===
  set numeroSolicitudes(int value) {
    if (value < 1) return;

    // Guardar en caché
    for (int i = 0; i < _solicitudes.length; i++) {
      _cache[i] = _solicitudes[i].toJson(i);
    }

    _numeroSolicitudes = value;
    _solicitudes = List.generate(value, (i) {
      if (_cache.containsKey(i)) {
        final cached = _cache[i]!;
        final analisisList =
            (cached['analisis_$i'] as List?)
                ?.map(
                  (item) => AnalisisSeleccionado.fromJson(
                    item as Map<String, dynamic>,
                  ),
                )
                .toList() ??
            [];

        return Muestra(
          fechaToma: cached['fechaToma_$i'],
          numeroMuestras: cached['numeroMuestras_$i'] ?? 1,
          tipoMuestraCodigo: cached['tipoMuestra_$i'],
          origenMuestra: cached['origenMuestra_$i'] ?? 'GRS',
          edad: cached['edad_$i']?.toString() ?? '',
          codigoReferencia: cached['codigoReferenciaValue_$i'] ?? '',
          analisisSeleccionados: analisisList,
          observaciones: cached['observaciones_$i'] ?? '',
          paquetesSeleccionados: List<String>.from(
            cached['paquetesSeleccionados_$i'] ?? [],
          ),
        );
      } else {
        return Muestra(fechaToma: fechaEnvio);
      }
    });
    notifyListeners();
  }

  int get numeroSolicitudes => _numeroSolicitudes;
  List<Muestra> get solicitudes => _solicitudes;

  /// Elimina una solicitud y reindexa caché, configuración y GRI.
  bool eliminarSolicitud(int index) {
    if (_solicitudes.length <= 1) return false;
    if (index < 0 || index >= _solicitudes.length) return false;

    final items = <Muestra>[];
    final newConfigs = <int, ConfiguracionMuestra?>{};
    final newGri = <int, List<Map<String, dynamic>>>{};

    for (int i = 0; i < _solicitudes.length; i++) {
      if (i == index) continue;
      final m = _solicitudes[i];
      final newIdx = items.length;
      final copy = Muestra(
        fechaToma: m.fechaToma,
        numeroMuestras: m.numeroMuestras,
        tipoMuestraCodigo: m.tipoMuestraCodigo,
        origenMuestra: m.origenMuestra,
        edad: m.edad,
        codigoReferencia: m.codigoReferencia,
        numMachos: m.numMachos,
        numHembras: m.numHembras,
        griSeleccion: m.griSeleccion,
        analisisSeleccionados: List<AnalisisSeleccionado>.from(
          m.analisisSeleccionados,
        ),
        paquetesSeleccionados: List<String>.from(m.paquetesSeleccionados),
        observaciones: m.observaciones,
      );
      copy.tipoMuestraNombre = m.tipoMuestraNombre;
      items.add(copy);
      if (_configuraciones.containsKey(i)) {
        newConfigs[newIdx] = _configuraciones[i];
      }
      if (_griOpciones.containsKey(i)) {
        newGri[newIdx] = List<Map<String, dynamic>>.from(_griOpciones[i]!);
      }
    }

    _numeroSolicitudes = items.length;
    _solicitudes = items;
    _cache.clear();
    for (int i = 0; i < items.length; i++) {
      _cache[i] = items[i].toJson(i);
    }
    _configuraciones
      ..clear()
      ..addAll(newConfigs);
    _griOpciones
      ..clear()
      ..addAll(newGri);
    notifyListeners();
    return true;
  }

  // === Métodos de actualización por solicitud ===
  void setFechaToma(int index, String value) {
    _solicitudes[index].fechaToma = value;
    notifyListeners();
  }

  void setNumeroMuestras(int index, int value) {
    if (value >= 1) _solicitudes[index].numeroMuestras = value;
    if (necesitaGri(index)) cargarGriOpciones(index);
    notifyListeners();
  }

  Future<void> setTipoMuestra(
    int index,
    String? tipoCodigo,
    String? tipoNombre,
  ) async {
    _solicitudes[index].tipoMuestraCodigo = tipoCodigo;
    _solicitudes[index].tipoMuestraNombre = tipoNombre;
    _solicitudes[index].codigoReferencia = '';
    _solicitudes[index].edad = '';
    _solicitudes[index].numMachos = null;
    _solicitudes[index].numHembras = null;
    _solicitudes[index].numeroMuestras = 1;
    _solicitudes[index].analisisSeleccionados = [];
    _configuraciones[index] = null;
    _solicitudes[index].griSeleccion = '';
    _griOpciones.remove(index);

    if (tipoCodigo != null) {
      final result = await ApiService().getConfiguracionMuestra(tipoCodigo);
      print('result controller: ${result.toString()}.');
      if (result['success'] == true) {
        final outerData = result['data'] as Map<String, dynamic>;
        final innerData = outerData['data'] as Map<String, dynamic>;

        final tipoMuestra = innerData['tipo_muestra'] as Map<String, dynamic>;
        final paquetes =
            (innerData['paquetes'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
        final analisis =
            (innerData['analisis'] as List?)?.cast<Map<String, dynamic>>() ??
            [];
        debugPrint('tipoMuestra: ${tipoMuestra.toString()}.');
        debugPrint('paquetes: ${paquetes.toString()}.');
        debugPrint('analisis: ${analisis.toString()}.');
        _configuraciones[index] = ConfiguracionMuestra(
          tipoMuestra: tipoMuestra,
          paquetes: paquetes,
          analisis: analisis,
        );
      }
    }
    notifyListeners();
    if (necesitaGri(index)) cargarGriOpciones(index);
  }

  void setCodigoReferencia(int index, String value) {
    _solicitudes[index].codigoReferencia = value;
    if (necesitaGri(index)) cargarGriOpciones(index);
    notifyListeners();
  }

  Future<void> setOrigenMuestra(int index, String origen) async {
    _solicitudes[index].origenMuestra = origen;
    _solicitudes[index].codigoReferencia = '';
    _solicitudes[index].edad = '';
    _solicitudes[index].griSeleccion = '';
    _griOpciones.remove(index);

    if (origen == 'EXTERNO' || origen == 'TRASPATIO') {
      await cargarCodigosOrigen(origen);
    }
    if (necesitaGri(index)) {
      await cargarGriOpciones(index);
    }
    notifyListeners();
  }

  void setEdad(int index, String value) {
    final soloNumeros = value.replaceAll(RegExp(r'[^0-9]'), '');
    _solicitudes[index].edad = soloNumeros.length > 3
        ? soloNumeros.substring(0, 3)
        : soloNumeros;
    notifyListeners();
  }

  Future<void> cargarCodigosOrigen(String tipo) async {
    if (_codigosOrigenCache.containsKey(tipo)) return;

    final result = await ApiService().getOrigenAves(tipo);
    if (result['success'] == true) {
      final rows = (result['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _codigosOrigenCache[tipo] = rows;
    } else {
      _codigosOrigenCache[tipo] = [];
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> getCodigosOrigen(String tipo) {
    return _codigosOrigenCache[tipo] ?? [];
  }

  bool esOrigenExterno(int index) {
    final origen = _solicitudes[index].origenMuestra;
    return origen == 'EXTERNO' || origen == 'TRASPATIO';
  }

  bool esTipoAves(int index) {
    final n = (_solicitudes[index].tipoMuestraNombre ?? '').toLowerCase();
    return RegExp(r'aves\s+(vivas?|muertas?)').hasMatch(n);
  }

  bool tipoUsaGri(int index) {
    final cod = _solicitudes[index].tipoMuestraCodigo;
    if (cod == null || cod.isEmpty) return false;
    for (final t in _tiposMuestra) {
      if ('${t['codigo']}' == cod) {
        return int.tryParse('${t['gri']}') == 1;
      }
    }
    return false;
  }

  bool necesitaGri(int index) => !esOrigenExterno(index) && tipoUsaGri(index);

  Map<String, String>? _zonaDesdeCodRef(String codRef) {
    final digits = codRef.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return null;
    return {
      'granja': digits.substring(0, 3),
      'campania': digits.substring(3, 6),
      'galpon': digits.substring(6, 8),
    };
  }

  Future<void> cargarGriOpciones(int index) async {
    if (!necesitaGri(index)) {
      _griOpciones.remove(index);
      _solicitudes[index].griSeleccion = '';
      notifyListeners();
      return;
    }
    final zona = _zonaDesdeCodRef(_solicitudes[index].codigoReferencia);
    if (zona == null) {
      _griOpciones[index] = [];
      notifyListeners();
      return;
    }
    double? cantidad;
    if (_solicitudes[index].numeroMuestras <= 0) {
      _griOpciones[index] = [];
      notifyListeners();
      return;
    }
    cantidad = _solicitudes[index].numeroMuestras.toDouble();
    _cargandoGri = true;
    notifyListeners();
    final res = await ApiService().buscarGriDisponibles(
      granja: zona['granja']!,
      campania: zona['campania']!,
      galpon: zona['galpon']!,
      cantidad: cantidad,
    );
    _cargandoGri = false;
    if (res['success'] == true) {
      _griOpciones[index] =
          (res['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    } else {
      _griOpciones[index] = [];
    }
    final seleccion = _solicitudes[index].griSeleccion;
    if (seleccion.isNotEmpty) {
      final opciones = _griOpciones[index] ?? [];
      final valida = opciones.any(
        (item) => _griValorOpcion(item) == seleccion,
      );
      if (!valida) {
        _solicitudes[index].griSeleccion = '';
      }
    }
    notifyListeners();
  }

  String _griValorOpcion(Map<String, dynamic> item) =>
      '${item['tdoc'] ?? ''}|${item['tserie'] ?? ''}|${item['tnumfac'] ?? ''}';

  void setGriSeleccion(int index, String? value) {
    _solicitudes[index].griSeleccion = value ?? '';
    notifyListeners();
  }

  void setNumMachos(int index, int? value) {
    _solicitudes[index].numMachos = value;
    if (necesitaGri(index)) cargarGriOpciones(index);
    notifyListeners();
  }

  void setNumHembras(int index, int? value) {
    _solicitudes[index].numHembras = value;
    if (necesitaGri(index)) cargarGriOpciones(index);
    notifyListeners();
  }

  String getCodigoReferenciaFinal(int index) {
    final muestra = _solicitudes[index];
    if (esOrigenExterno(index) && muestra.edad.trim().isNotEmpty) {
      final edadPad = muestra.edad.trim().padLeft(2, '0');
      return '${muestra.codigoReferencia}-$edadPad';
    }
    return muestra.codigoReferencia;
  }

  String getEtiquetaOrigen(String origen) {
    switch (origen) {
      case 'EXTERNO':
        return 'Externo';
      case 'TRASPATIO':
        return 'Traspatio';
      default:
        return 'GRS';
    }
  }

  String getGriEtiqueta(int index) {
    final seleccion = _solicitudes[index].griSeleccion.trim();
    if (seleccion.isEmpty) return '';

    for (final item in _griOpciones[index] ?? []) {
      if (_griValorOpcion(item) == seleccion) {
        final label = item['label']?.toString();
        if (label != null && label.isNotEmpty) return label;
        final cod = item['codigoGri']?.toString();
        if (cod != null && cod.isNotEmpty) return cod;
      }
    }

    final parts = seleccion.split('|');
    if (parts.length >= 3) {
      return '${parts[1]}-${parts[2]}';
    }
    return seleccion;
  }

  void toggleAnalisis(
    int index,
    String analisisCodigo,
    String analisisNombre,
    String paqueteCodigo,
    String paqueteNombre,
    bool checked,
  ) {
    final muestra = _solicitudes[index];
    final nuevoAnalisis = AnalisisSeleccionado(
      id: Uuid().v4(),
      analisisCodigo: analisisCodigo,
      analisisNombre: analisisNombre,
      paqueteCodigo: paqueteCodigo,
      paqueteNombre: paqueteNombre,
    );

    if (checked) {
      if (!muestra.analisisSeleccionados.contains(nuevoAnalisis)) {
        muestra.analisisSeleccionados.add(nuevoAnalisis);
      }
    } else {
      muestra.analisisSeleccionados.removeWhere(
        (a) => a.analisisCodigo == analisisCodigo,
      );
    }

    notifyListeners();
  }

  void setObservaciones(int index, String value) {
    _solicitudes[index].observaciones = value;
    notifyListeners();
  }

  // === Acceso a configuración ===
  ConfiguracionMuestra? getConfiguracion(int index) => _configuraciones[index];
  int getLongitudCodigoReferencia(int index) {
    final config = _configuraciones[index];
    if (config == null) return 0;

    final valor = config.tipoMuestra['lonCod']; // ['longitud_codigo'];
    if (valor == null) return 0;

    // Manejar tanto String como num
    if (valor is num) {
      return valor.toInt();
    } else if (valor is String) {
      return int.tryParse(valor) ?? 0;
    }

    return 0;
  }

  String? obtenerErrorSolicitud(int index) {
    final solicitud = solicitudes[index];

    if (solicitud.fechaToma == null || solicitud.fechaToma!.isEmpty) {
      return 'Fecha de toma es obligatoria.';
    }

    if (solicitud.tipoMuestraCodigo == null ||
        solicitud.tipoMuestraCodigo!.isEmpty) {
      return 'Debe seleccionar un tipo de muestra.';
    }

    if (solicitud.analisisSeleccionados.isEmpty) {
      return 'Debe seleccionar al menos un análisis.';
    }

    if (solicitud.numeroMuestras < 1) {
      return 'N° de muestras es obligatorio.';
    }

    if (esOrigenExterno(index)) {
      if (solicitud.codigoReferencia.trim().isEmpty) {
        return 'Debe seleccionar el código de origen.';
      }
    } else {
      final longitudEsperada = getLongitudCodigoReferencia(index);
      if (longitudEsperada > 0 &&
          solicitud.codigoReferencia.length != longitudEsperada) {
        return 'Código de referencia debe tener $longitudEsperada dígitos.';
      }
      if (necesitaGri(index)) {
        if (solicitud.griSeleccion.trim().isEmpty) {
          return 'Debe seleccionar una GRI.';
        }
      }
    }

    // Puedes agregar más validaciones aquí según tus reglas

    return null; // válido
  }

  // === Validación ===
  bool isValidarSolicitud(int index) => obtenerErrorSolicitud(index) == null;

  bool get esValido {
    if (_numeroSolicitudes == 0) return false;
    if (laboratorioId.isEmpty) return false;
    if (empresaTransporteId.isEmpty) return false;
    if (autorizadoPor.isEmpty) return false;
    if (usuarioResponsable.isEmpty) return false;
    return _solicitudes.asMap().entries.every((e) => isValidarSolicitud(e.key));
  }

  Future<bool> guardar() async {
    final _storageService = Provider.of<StorageService>(
      Get.context!,
      listen: false,
    );
    final String userCode = _storageService.getUserCodeSync() ?? 'app_movil';
    final Map<String, dynamic> data = toMap();
    data['synced'] = false;
    await _storageService.saveForm(AppStrings.formType1, data);
    return true;
    /*data['usuarioTransferencia'] = userCode;
    data['fechaHoraTransferencia'] = _formatDateTime(DateTime.now());
    final payload = {
      AppStrings.formType1: [data],
    };
    try {
      final result = await ApiService().uploadMultiple(payload);
      if (result['success'] == true) {
        data['synced'] = true;
        data['codigoEnvio'] =
            result['detalle']['envios_muestras']['codigosGenerados'][0]['codigoEnvio'];
        await _storageService.saveForm(AppStrings.formType1, data);
        generarCodigoEnvio();
        return true;
      } else {
        data['synced'] = false;
        await _storageService.saveForm(AppStrings.formType1, data);
        return false;
      }
    } catch (e) {
      data['synced'] = false;
      await _storageService.saveForm(AppStrings.formType1, data);
      return false;
    }*/
  }

  Map<String, dynamic> toMap() {
    final _storageService = Provider.of<StorageService>(
      Get.context!,
      listen: false,
    );
    final String userCode = _storageService.getUserCodeSync() ?? 'app_movil';
    final String userName = _storageService.getUserName() ?? 'app_movil';
    final Map<String, dynamic> data = {
      'codigoEnvio': codigoEnvio,
      'fechaEnvio': fechaEnvio,
      'horaEnvio': horaEnvio,
      'laboratorioCodigo': laboratorioId,
      'laboratorioNombre': laboratorioNombre,
      'empresaTransporteCodigo': empresaTransporteId,
      'empresaTransporteNombre': empresaTransporteNombre,
      'usuarioRegistrador': userCode,
      'usuarioResponsable': usuarioResponsable,
      'autorizadoPor': autorizadoPor,
      'numeroSolicitudes': numeroSolicitudes,
      'id': Uuid().v4(),
      'fechaHoraRegistro': _formatDateTime(DateTime.now()),
      'synced': false,
      'usuarioNombre': userName,
    };

    for (int i = 0; i < numeroSolicitudes; i++) {
      final m = solicitudes[i];
      data['fechaToma_$i'] = m.fechaToma;
      data['tipoMuestraCodigo_$i'] = m.tipoMuestraCodigo;
      data['tipoMuestraNombre_$i'] = m.tipoMuestraNombre;
      data['origenMuestra_$i'] = m.origenMuestra;
      data['edad_$i'] = m.edad;
      data['codigoReferenciaValue_$i'] = m.codigoReferencia;
      data['numeroMuestras_$i'] = m.numeroMuestras;
      if (m.griSeleccion.isNotEmpty) data['gri_seleccion_$i'] = m.griSeleccion;
      data['observaciones_$i'] = m.observaciones;
      data['analisisCompletos_$i'] = m.analisisSeleccionados
          .map((a) => a.toJson())
          .toList();
    }

    return data;
  }

  /// Campos para vista previa PDF (mismo formato que la web).
  Map<String, String> buildPreviewFormFields() {
    final fields = <String, String>{
      'fechaEnvio': fechaEnvio,
      'horaEnvio': horaEnvio,
      'codigoEnvio': codigoEnvio,
      'laboratorio_nombre': laboratorioNombre,
      'empresa_transporte_nombre': empresaTransporteNombre,
      'usuario_responsable': usuarioResponsable,
      'autorizado_por': autorizadoPor,
      'numeroSolicitudes': numeroSolicitudes.toString(),
      'tipos_muestra': jsonEncode(
        _tiposMuestra.map((t) => t['nombre']?.toString() ?? '').toList(),
      ),
    };

    for (int i = 0; i < numeroSolicitudes; i++) {
      final m = solicitudes[i];
      fields['fechaToma_$i'] = m.fechaToma ?? '';
      fields['tipoMuestra_$i'] = m.tipoMuestraCodigo ?? '';
      fields['tipoMuestraNombre_$i'] = m.tipoMuestraNombre ?? '';
      fields['origenMuestra_$i'] = m.origenMuestra;
      fields['codigoReferenciaValue_$i'] = m.codigoReferencia;
      fields['edad_$i'] = m.edad;
      fields['numeroMuestras_$i'] = m.numeroMuestras.toString();
      fields['observaciones_$i'] = m.observaciones;
      if (m.griSeleccion.isNotEmpty) {
        fields['gri_seleccion_$i'] = m.griSeleccion;
      }
      final analisisPreview = m.analisisSeleccionados
          .map(
            (a) => {
              'codigo': a.analisisCodigo,
              'nombre': a.analisisNombre,
              'paquete_nombre': a.paqueteNombre,
            },
          )
          .toList();
      fields['analisis_completos_$i'] = jsonEncode(analisisPreview);
    }

    return fields;
  }

  void reset({
    required String fechaEnvio,
    required String horaEnvio,
    required String usuarioRegistrador,
  }) {
    // Reiniciar campos generales
    this.fechaEnvio = fechaEnvio;
    this.horaEnvio = horaEnvio;
    this.usuarioRegistrador = usuarioRegistrador;
    laboratorioId = '';
    laboratorioNombre = '';
    empresaTransporteId = '';
    empresaTransporteNombre = '';
    usuarioResponsable = '';
    autorizadoPor = '';

    // Reiniciar número de solicitudes a 0
    _numeroSolicitudes = 0;

    // Limpiar completamente listas y mapas internos
    _solicitudes.clear();
    _cache.clear();
    _configuraciones.clear();
    _codigosOrigenCache.clear();

    // Notificar a los widgets
    notifyListeners();
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}

// === Modelo interno para configuración ===
class ConfiguracionMuestra {
  final Map<String, dynamic> tipoMuestra;
  final List<Map<String, dynamic>> paquetes;
  final List<Map<String, dynamic>> analisis;

  ConfiguracionMuestra({
    required this.tipoMuestra,
    required this.paquetes,
    required this.analisis,
  });
}
