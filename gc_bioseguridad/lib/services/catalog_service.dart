import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../widgets/ingreso_alcoholemia_section.dart';
import 'api_service.dart';

/// Metadatos de una métrica del tablero de cerco eléctrico.
class CercoMetrica {
  const CercoMetrica({
    required this.nombre,
    required this.std,
    required this.bloque,
    this.permiteObs = false,
    String? ok,
    String? falla,
  })  : _ok = ok,
        _falla = falla;

  final String nombre;
  final String std;

  /// Bloque del reporte al que pertenece. Es también el título de la tabla y
  /// viene del catálogo del servidor, para que la app no conozca de antemano
  /// qué bloques existen ni qué métrica va en cada uno.
  final String bloque;

  /// Si la fila pide observación siempre además de la falla (valores medidos:
  /// voltaje y nivel de batería).
  final bool permiteObs;

  final String? _ok;
  final String? _falla;

  /// Respuestas de la fila. En el formato físico casi todo se contesta CT
  /// (controlado: está como debe) o FALLA; las tres alertas del tablero, No o
  /// SI, porque ahí la pregunta es si la alerta está presente.
  /// Vienen del catálogo para poder corregirlas sin publicar la app; el respaldo
  /// repite la misma regla para un catálogo viejo o sin descargar.
  String get ok => _ok ?? ((esAlerta || _esSiNo) ? 'No' : 'CT');

  /// La respuesta que marca la falla: «FALLA» o, en las filas de sí/no, «SI».
  String get falla => _falla ?? ((esAlerta || _esSiNo) ? 'SI' : 'FALLA');

  /// Las tres últimas filas del tablero no preguntan si el componente está
  /// controlado sino si la alerta está presente: «SI» es lo malo.
  bool get esAlerta => _alertasTablero.contains(nombre.trim());

  /// Filas que se contestan sí/no en vez de CT/FALLA. Es el respaldo para un
  /// catálogo viejo (sin `ok`/`falla`): el servidor manda las mismas en
  /// `bio_cerco_respuestas()`. Se compara por nombre exacto.
  bool get _esSiNo => _respuestasSiNo.contains(nombre.trim());

  static const Set<String> _alertasTablero = {
    'Cerco Bloqueado/sin energía',
    'Cerco Apagado/No se active',
    'La sirena está sonando alerta',
  };

  /// Mismas filas que resuelve el servidor con «No»/«SI» (verificación del
  /// cerco y del perímetro). El tablero conserva CT/FALLA salvo las alertas.
  static const Set<String> _respuestasSiNo = {
    'Argolla Pegada',
    'Argolla caída',
    'Puente pegado',
    'Puente caído (línea abierta)',
    'Línea enterrada (humedad)',
    'Línea con bolsa (basura)',
    'Templador/aislador suelto',
    'Aislador suelto intermedio',
    'Puerta Vehicular abierta',
    'Puerta Vehicular desactivada',
    'Puerta del personal abierta',
    'Puerta pozo séptico abierta',
    'Pozo séptico desactivado',
  };
}

class CatalogService with ChangeNotifier {
  static const String _prefsKey = 'catalogos';

  Map<String, dynamic> _catalogos = {};
  Map<String, dynamic> _bio = {};
  bool _isLoading = false;
  bool _bioLoading = false;

  /// Catálogo que no llegó en la última descarga (nombre corto).
  String? falloBio;
  Future<bool>? _bioEnCurso;

  Map<String, dynamic> get catalogos => _catalogos;
  Map<String, dynamic> get bio => _bio;
  bool get isLoading => _isLoading || _bioLoading;
  bool get hasBioData => _bio.isNotEmpty;

  Future<void> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_prefsKey);
      _catalogos = (data != null && data.isNotEmpty)
          ? Map<String, dynamic>.from(jsonDecode(data) as Map)
          : {};

      final bioRaw = prefs.getString(AppConstants.keyCatalogosBio);
      _bio = (bioRaw != null && bioRaw.isNotEmpty)
          ? Map<String, dynamic>.from(jsonDecode(bioRaw) as Map)
          : {};
      notifyListeners();
    } catch (e) {
      debugPrint('CatalogService: error al cargar catálogos: $e');
      _catalogos = {};
      _bio = {};
      notifyListeners();
    }
  }

  void clearMemory() {
    _catalogos = {};
    _bio = {};
    notifyListeners();
  }

  Future<bool> downloadCatalogos({List<String>? tablas}) async {
    if (_isLoading) return false;
    if (_catalogos.isEmpty) {
      await loadFromPrefs();
    }
    _isLoading = true;
    notifyListeners();
    try {
      final result = await ApiService().downloadCatalogos(tablas: tablas);
      if (result['success'] == true) {
        final raw = result['data'];
        if (raw is Map<String, dynamic>) {
          if (tablas != null && tablas.isNotEmpty) {
            for (final t in tablas) {
              if (raw.containsKey(t)) {
                _catalogos[t] = raw[t];
              }
            }
          } else {
            _catalogos = Map<String, dynamic>.from(raw);
          }
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_catalogos));
        notifyListeners();
        return _hasTablasDescargadas(tablas);
      }
      debugPrint(
        'CatalogService.downloadCatalogos falló: ${result['message'] ?? 'sin mensaje'}',
      );
    } catch (e) {
      debugPrint('CatalogService: error al descargar catálogos: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return false;
  }

  /// Descarga los catálogos propios de bioseguridad.
  /// Si ya hay una descarga en curso (p. ej. la silenciosa del dashboard) se
  /// espera su resultado. Antes compartía `_isLoading` con usuarios/conempre y
  /// en ese caso salía sin descargar nada, dejando el catálogo viejo.
  Future<bool> downloadCatalogosBioseguridad() {
    return _bioEnCurso ??= _descargarBio().whenComplete(() => _bioEnCurso = null);
  }

  Future<bool> _descargarBio() async {
    _bioLoading = true;
    notifyListeners();
    try {
      final result = await ApiService().downloadCatalogosBioseguridad();
      if (result['success'] == true && result['data'] is Map) {
        falloBio = null;
        final fetched = Map<String, dynamic>.from(result['data'] as Map);
        // Rastro para verificar desde `flutter run` que el STD descargado es el
        // que quedó guardado (p. ej. «Verificación del voltaje=>11»).
        final metricas = fetched['metricas_cerco'];
        if (metricas is List) {
          debugPrint(
            'CatalogService: metricas_cerco recibidas: '
            '${metricas.map((m) => m is Map ? '${m['metrica']}=${m['std']}' : m).join(' | ')}',
          );
        }
        // Se reemplaza el catálogo completo (no se fusiona con el anterior):
        // así desaparece cualquier valor que el servidor ya no envía.
        final faltantes = validarCatalogoBio(fetched);
        if (faltantes != null) {
          final merged = Map<String, dynamic>.from(_bio);
          fetched.forEach((k, v) {
            if (v is List && v.isNotEmpty) merged[k] = v;
            if (v is Map && v.isNotEmpty) merged[k] = v;
          });
          _bio = merged;
          falloBio = 'bioseguridad: $faltantes';
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(AppConstants.keyCatalogosBio, jsonEncode(_bio));
          notifyListeners();
          return false;
        }
        _bio = fetched;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(AppConstants.keyCatalogosBio, jsonEncode(_bio));
        debugPrint('CatalogService: catálogo bio reemplazado · $resumenBio');
        notifyListeners();
        return referencias.isNotEmpty || tiposFomites.isNotEmpty;
      }
      final msg = (result['message'] ?? '').toString().trim();
      falloBio = msg.isEmpty ? 'bioseguridad' : 'bioseguridad $msg';
      debugPrint(
        'CatalogService.downloadCatalogosBioseguridad falló: '
        '${result['message'] ?? 'sin mensaje'}',
      );
    } catch (e) {
      falloBio = 'bioseguridad';
      debugPrint('CatalogService: error al descargar catálogos bio: $e');
    } finally {
      _bioLoading = false;
      notifyListeners();
    }
    return false;
  }

  bool _hasTablasDescargadas(List<String>? tablas) {
    if (tablas == null || tablas.isEmpty) {
      return _catalogos.isNotEmpty;
    }
    for (final t in tablas) {
      final data = _catalogos[t];
      if (data is List && data.isNotEmpty) return true;
    }
    return false;
  }

  // ── Accesos tipados a los catálogos de bioseguridad ─────────────────────

  // Los catálogos ya no tienen copia en código: o vienen de la descarga, o la
  // lista queda vacía y el formulario pide descargarlos. La copia era una
  // segunda fuente de verdad que se desincronizaba del servidor sin avisar
  // (bastaba agregar un área en el backend y olvidar la copia de la app).

  /// Nombres de los tres bloques del reporte de cerco. El servidor los envía
  /// en `bloque`; acá solo quedan como valor por defecto si un catálogo viejo
  /// no lo trae.
  static const String bloqueTablero = 'Verificación del tablero';
  static const String bloqueCerco = 'Verificación del cerco';
  static const String bloquePerimetro = 'Verificación del perímetro';

  /// Forma del tablero de cerco: qué bloque le toca a cada métrica, si pide
  /// observación y con qué se contesta.
  /// No es la lista de filas —esas salen del catálogo descargado— sino el
  /// esqueleto con el que se interpreta: un equipo que conserva un catálogo
  /// cacheado por una versión anterior (sin `bloque`, `obs`, `ok` ni `falla`)
  /// hereda de acá esos cuatro datos por nombre de métrica, así el tablero
  /// sigue agrupado y con el par de respuestas correcto hasta la próxima
  /// descarga. Es la única parte que queda en código, porque es la forma del
  /// reporte y no un catálogo que se mantenga en el servidor.
  static const List<CercoMetrica> _estructuraCerco = [
    // --- Verificación del tablero -----------------------------------------
    CercoMetrica(
      nombre: 'Verificación del voltaje',
      std: '>11',
      bloque: bloqueTablero,
      permiteObs: true,
    ),
    CercoMetrica(
      nombre: 'Cerco Operativo',
      std: 'Luz encendida',
      bloque: bloqueTablero,
    ),
    CercoMetrica(
      nombre: 'Voltaje Operativo',
      std: 'Luz encendida',
      bloque: bloqueTablero,
    ),
    CercoMetrica(
      nombre: 'Sirena Operativo',
      std: 'Luz encendida',
      bloque: bloqueTablero,
    ),
    CercoMetrica(
      nombre: 'Nivel de Batería',
      std: '',
      bloque: bloqueTablero,
      permiteObs: true,
    ),
    CercoMetrica(
      nombre: 'Cerco Bloqueado/sin energía',
      std: '',
      bloque: bloqueTablero,
    ),
    CercoMetrica(
      nombre: 'Cerco Apagado/No se active',
      std: '',
      bloque: bloqueTablero,
    ),
    CercoMetrica(
      nombre: 'La sirena está sonando alerta',
      std: '',
      bloque: bloqueTablero,
    ),
    // --- Verificación del cerco -------------------------------------------
    CercoMetrica(
      nombre: 'Verificación de voltaje',
      std: '',
      bloque: bloqueCerco,
    ),
    // «Cable Conectado» va segundo, como en el servidor: es el chequeo básico
    // del tramo y se lee antes que el resto de los componentes.
    CercoMetrica(
      nombre: 'Cable Conectado',
      std: 'Conectado',
      bloque: bloqueCerco,
    ),
    CercoMetrica(
      nombre: 'Argolla Pegada',
      std: 'No pegada',
      bloque: bloqueCerco,
    ),
    CercoMetrica(nombre: 'Argolla caída', std: 'Completo', bloque: bloqueCerco),
    CercoMetrica(nombre: 'Puente pegado', std: 'No Pegado', bloque: bloqueCerco),
    CercoMetrica(
      nombre: 'Puente caído (línea abierta)',
      std: 'Completo',
      bloque: bloqueCerco,
    ),
    CercoMetrica(
      nombre: 'Línea enterrada (humedad)',
      std: '',
      bloque: bloqueCerco,
    ),
    CercoMetrica(
      nombre: 'Línea con bolsa (basura)',
      std: 'Sin basura',
      bloque: bloqueCerco,
    ),
    CercoMetrica(
      nombre: 'Templador/aislador suelto',
      std: 'Conectado',
      bloque: bloqueCerco,
    ),
    CercoMetrica(
      nombre: 'Aislador suelto intermedio',
      std: 'Conectado',
      bloque: bloqueCerco,
    ),
    // --- Verificación del perímetro ---------------------------------------
    CercoMetrica(
      nombre: 'Puerta Vehicular abierta',
      std: 'Cerrado',
      bloque: bloquePerimetro,
    ),
    CercoMetrica(
      nombre: 'Puerta Vehicular desactivada',
      std: 'Cerrada',
      bloque: bloquePerimetro,
    ),
    CercoMetrica(
      nombre: 'Puerta del personal abierta',
      std: 'Cerrado',
      bloque: bloquePerimetro,
    ),
    CercoMetrica(
      nombre: 'Puerta pozo séptico abierta',
      std: 'Cerrado',
      bloque: bloquePerimetro,
    ),
    CercoMetrica(
      nombre: 'Pozo séptico desactivado',
      std: 'Cerrado',
      bloque: bloquePerimetro,
    ),
  ];

  /// Lista de catálogo tal como la guardó la descarga.
  /// Sin descarga (o con una tabla que el servidor todavía no envía) devuelve
  /// una lista vacía: el formulario que la use tiene que avisar que falta
  /// descargar, en vez de ofrecer opciones inventadas acá.
  List<Map<String, String>> _listaCatalogo(String key) {
    final raw = _bio[key];
    if (raw is! List || raw.isEmpty) return const [];
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final codigo = (item['codigo'] ?? '').toString().trim();
      final descripcion = (item['descripcion'] ?? '').toString().trim();
      if (descripcion.isEmpty && codigo.isEmpty) continue;
      out.add({
        'codigo': codigo,
        'descripcion': descripcion.isEmpty ? codigo : descripcion,
      });
    }
    return out;
  }

  /// `true` mientras no se haya descargado el catálogo de bioseguridad.
  /// Los formularios lo usan para avisar que hay que descargar antes de llenar,
  /// en lugar de mostrar selectores vacíos sin explicación.
  bool get sinDescargar => _bio.isEmpty;

  /// Tablas que los formularios necesitan sí o sí del servidor.
  static const List<String> _tablasBioCriticas = [
    'referencias',
    'tipos',
    'procesos',
    'instalaciones',
  ];

  /// Devuelve qué tablas vienen vacías o ausentes en [data], o `null` si el
  /// catálogo llega completo.
  /// Los catálogos no tienen copia en código: si el servidor responde a medias
  /// y eso se guarda igual, los selectores quedan vacíos y el equipo ve el
  /// aviso de «descargue» sin entender por qué. En ese caso conviene conservar
  /// lo anterior y contarlo como descarga fallida.
  static String? validarCatalogoBio(Map<String, dynamic> data) {
    final faltan = <String>[];
    for (final t in _tablasBioCriticas) {
      final valor = data[t];
      if (valor is! List || valor.isEmpty) faltan.add(t);
    }
    return faltan.isEmpty ? null : faltan.join(', ');
  }

  /// Rastro para `flutter run`: qué quedó guardado en cada catálogo después de
  /// la descarga y, en particular, los procesos de fómites que va a ofrecer el
  /// formulario. Sirve para confirmar que se reemplazaron las opciones viejas.
  String get resumenBio {
    String cuenta(String key) {
      final valor = _bio[key];
      return valor is List ? '${valor.length}' : '-';
    }

    return 'referencias=${cuenta('referencias')} tipos=${cuenta('tipos')} '
        'procesos=${cuenta('procesos')} '
        '[${_listaCatalogo('procesos').map((p) => p['descripcion']).join('/')}] '
        'instalaciones=${cuenta('instalaciones')} '
        'anomalias=${cuenta('anomalias')} '
        'areas=${cuenta('areas')} proveedores=${cuenta('proveedores')}';
  }

  List<Map<String, String>> get referencias => _listaCatalogo('referencias');

  /// Tipos de evidencia de un fómite (Avistamiento, Huella, Muerte...).
  /// «Intrusión» se retiró de la app: el catálogo en la base se conserva porque
  /// los registros históricos lo usan, y el endpoint de catálogos ya no lo
  /// envía. Se filtra también acá para que desaparezca aunque el equipo siga
  /// con un catálogo cacheado de antes de la actualización.
  List<Map<String, String>> get tiposFomites => _listaCatalogo('tipos')
      .where((t) => !_esTipoRetirado(t['descripcion']))
      .toList();

  static bool _esTipoRetirado(String? descripcion) {
    final d = (descripcion ?? '').trim().toLowerCase();
    return d == 'intrusion' || d == 'intrusión';
  }

  /// Procesos de fómites. «Despacho» se retiró: el endpoint ya no lo envía y
  /// se filtra también acá por si el equipo conserva un catálogo anterior.
  /// Además se corrige «Descanzo» «Descanso» al mostrar. La palabra venía con
  /// z en `procesofomites` (la tabla del servidor, que alimenta el selector) y
  /// así quedó en 39 registros históricos. Mientras esa base no corra la
  /// migración, o mientras el equipo siga con un catálogo descargado antes, el
  /// selector mostraba la errata; acá se muestra bien y se guarda «Descanso»,
  /// que es lo que ya usa el resto de la base.
  List<Map<String, String>> get procesosFomites => _listaCatalogo('procesos')
      .map(_corregirProceso)
      .where((p) => !_esProcesoRetirado(p['descripcion']))
      .toList();

  /// Devuelve el proceso con la errata del catálogo corregida (`descanzo`).
  static Map<String, String> _corregirProceso(Map<String, String> proceso) {
    final descripcion = (proceso['descripcion'] ?? '').trim();
    if (descripcion.toLowerCase() != 'descanzo') return proceso;
    return {...proceso, 'descripcion': 'Descanso'};
  }

  static bool _esProcesoRetirado(String? descripcion) =>
      (descripcion ?? '').trim().toLowerCase() == 'despacho';

  List<Map<String, String>> get anomalias => _listaCatalogo('anomalias');

  /// Instalaciones del catálogo (Garita, Tranquera, Pozo séptico...).
  List<Map<String, String>> get instalaciones =>
      _listaCatalogo('instalaciones');

  /// Tipos de bioseguridad (física, química, biológica).
  List<Map<String, String>> get bioseguridades =>
      _listaCatalogo('bioseguridades');

  /// Áreas de GRS (`TiposVisitante.area`).
  List<Map<String, String>> get areas => _listaCatalogo('areas');

  /// Proveedores y servicios externos (`TiposVisitante.proveedor`).
  List<Map<String, String>> get proveedores => _listaCatalogo('proveedores');

  /// «Otro» es una fila más del catálogo, como los recursos de vacuna al agua:
  /// al elegirla la app pide el texto a mano. Se compara sin distinguir
  /// mayúsculas ni tildes para que un catálogo editado a mano («otro», «Otro»)
  /// siga funcionando.
  static bool esOtro(String descripcion) {
    final d = descripcion.trim().toLowerCase();
    return d == 'otro' || d == 'otros';
  }

  /// Nombre del usuario del sistema cuyo DNI coincide con [dni].
  /// `usuario.libtri` guarda el DNI (así lo usa el módulo de roles), y el
  /// catálogo de usuarios ya viene descargado para el login offline. Es la
  /// segunda barrera cuando la consulta en línea del documento no responde:
  /// el personal de la granja se resuelve sin conexión.
  /// Devuelve cadena vacía si el DNI no está entre los usuarios descargados.
  String nombrePorDni(String dni) {
    final buscado = dni.replaceAll(RegExp(r'\D'), '');
    if (buscado.isEmpty) return '';
    final usuarios = _catalogos['usuarios'];
    if (usuarios is! List) return '';
    for (final u in usuarios) {
      if (u is! Map) continue;
      final libtri = (u['libtri'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      if (libtri.isEmpty || libtri != buscado) continue;
      final nombre = (u['nombre'] ?? '').toString().trim();
      if (nombre.isNotEmpty) return nombre;
    }
    return '';
  }

  List<String> get depredadores {
    final raw = _bio['depredadores'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Filas del tablero de cerco tal como las envió el servidor.
  /// Vacío si no hay descarga: el tablero no se arma con una lista inventada en
  /// la app, y la pantalla ya avisa que hay que descargar los catálogos.
  List<CercoMetrica> get metricasCerco {
    final raw = _bio['metricas_cerco'];
    if (raw is! List || raw.isEmpty) return const [];
    final out = <CercoMetrica>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final nombre = (item['metrica'] ?? '').toString().trim();
      if (nombre.isEmpty) continue;
      // `bloque`, `obs`, `ok` y `falla` los manda el servidor. Si el equipo
      // conserva un catálogo cacheado por una versión anterior (sin esos
      // campos) se heredan del esqueleto por nombre, para no perder la
      // agrupación ni la observación hasta la próxima descarga.
      final def = _estructuraDe(nombre);
      final bloque = (item['bloque'] ?? '').toString().trim();
      out.add(CercoMetrica(
        nombre: nombre,
        std: (item['std'] ?? '').toString().trim(),
        bloque: bloque.isNotEmpty ? bloque : (def?.bloque ?? bloqueTablero),
        permiteObs: _boolCatalogo(item['obs']) ?? def?.permiteObs ?? false,
        // Sin el dato se hereda del esqueleto por nombre, que aplica la misma
        // regla (CT/FALLA, o No/SI en las alertas del tablero).
        ok: _textoCatalogo(item['ok']) ?? def?.ok,
        falla: _textoCatalogo(item['falla']) ?? def?.falla,
      ));
    }
    return out;
  }

  /// Fila del esqueleto del cerco con ese nombre exacto.
  static CercoMetrica? _estructuraDe(String nombre) {
    for (final m in _estructuraCerco) {
      if (m.nombre == nombre) return m;
    }
    return null;
  }

  /// Lee un texto de catálogo, o `null` si viene vacío o ausente.
  static String? _textoCatalogo(dynamic valor) {
    final s = (valor ?? '').toString().trim();
    return s.isEmpty ? null : s;
  }

  /// Lee un booleano de catálogo que puede venir como bool, 1/0 o texto.
  static bool? _boolCatalogo(dynamic valor) {
    if (valor is bool) return valor;
    if (valor == null) return null;
    final s = valor.toString().trim().toLowerCase();
    if (s == '1' || s == 'true' || s == 'si' || s == 'sí') return true;
    if (s == '0' || s == 'false' || s == 'no') return false;
    return null;
  }

  /// Filtros numerados de la garita. Vacío sin descarga.
  List<int> get filtros {
    final raw = _bio['filtros'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw.map((e) => int.tryParse(e.toString())).whereType<int>().toList();
  }

  /// Turnos del catálogo (Día/Noche). Vacío sin descarga: el formulario avisa
  /// que hay que descargar en vez de ofrecer un turno que el servidor no envió.
  List<String> get turnos {
    final raw = _bio['turnos'];
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Descripción legible de un código de catálogo (p. ej. referencia `3` Garita).
  String descripcionDe(List<Map<String, String>> catalogo, String codigo) {
    for (final item in catalogo) {
      if (item['codigo'] == codigo) return item['descripcion'] ?? codigo;
    }
    return codigo;
  }

  /// Parámetros de alcoholemia (umbral, textos AGC) del catálogo bio.
  AlcoholemiaCatalogMeta get alcoholemiaMeta {
    final raw = _bio['alcoholemia'];
    if (raw is! Map) return AlcoholemiaCatalogMeta.fallback;
    final u = raw['umbral_g_l'];
    return AlcoholemiaCatalogMeta(
      umbralGl: u is num ? u.toDouble() : double.tryParse('$u') ?? 0,
      agenteCausalDef: raw['agente_causal_def']?.toString() ??
          AlcoholemiaCatalogMeta.fallback.agenteCausalDef,
      accionDef: raw['accion_def']?.toString() ??
          AlcoholemiaCatalogMeta.fallback.accionDef,
    );
  }

  List<ArticuloIngresoCatalogo> get articulosIngreso {
    final raw = _bio['articulos_ingreso'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => ArticuloIngresoCatalogo.fromMap(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Insumos del proveedor (descarga nube / campo-context).
  List<Map<String, dynamic>> get insumosProveedor {
    final raw = _bio['insumos_proveedor'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> mergeInsumosProveedor(List<Map<String, dynamic>> items) async {
    _bio['insumos_proveedor'] = items;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyCatalogosBio, jsonEncode(_bio));
    notifyListeners();
  }
}

class ArticuloIngresoCatalogo {
  ArticuloIngresoCatalogo({
    required this.codigo,
    required this.descripcion,
    required this.permite,
    this.regla = '',
    this.nota = '',
  });

  final String codigo;
  final String descripcion;
  final bool? permite;

  final String regla;
  final String nota;

  factory ArticuloIngresoCatalogo.fromMap(Map<String, dynamic> m) {
    final p = m['permite'];
    final regla = (m['regla']?.toString() ?? '').toUpperCase();
    bool? permite;
    if (p == null && regla.isNotEmpty) {
      if (regla == 'PERMITIDO') {
        permite = true;
      } else if (regla == 'PROHIBIDO') {
        permite = false;
      }
    } else if (p != null) {
      permite = p == true;
    }
    return ArticuloIngresoCatalogo(
      codigo: m['codigo']?.toString() ?? '',
      descripcion: m['descripcion']?.toString() ?? '',
      permite: permite,
      regla: regla,
      nota: m['nota']?.toString() ?? '',
    );
  }
}
