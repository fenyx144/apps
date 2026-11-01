import 'api_service.dart';
import 'storage_service.dart';
import '../utils/galpones_resolver.dart';
import '../widgets/granja_campania_picker.dart';

/// Edad/campaña: backend si responde; catálogo local si no.
class EdadCatalogService {
  EdadCatalogService({ApiService? api}) : _api = api ?? ApiService();

  final ApiService _api;
  static const _apiTimeout = Duration(seconds: 3);

  ({
    bool activa,
    int? edad,
    int metaCount,
    int conFecIng,
    String cenco,
  }) edadDesdeCatalogo({
    required StorageService storage,
    required String granja3,
    required String campania,
    required String fechaYmd,
    required List<String> galponesSel,
    List<Map<String, dynamic>> galponesUi = const [],
  }) {
    final proyeccion = storage.getProyeccion();
    final campInfo = GranjaCampaniaPicker.edadCampaniaEnFecha(
      proyeccion: proyeccion,
      granja3: granja3,
      campania: campania,
      fechaYmd: fechaYmd,
    );
    var activa = campInfo.activa;
    if (!activa) {
      activa = _activaPorCencoEnCatalogo(storage, granja3, campania);
    }
    final cenco = GalponesResolver.normalizarCodigoCenco(
      GalponesResolver.codigoCenco6(granja3, campania),
    );
    final meta = storage.getGalponesMetaPorCenco(
      cenco,
      fallbackGalpones: galponesUi,
    );
    var conFecIng = 0;
    for (final g in meta) {
      final fi = (g['fec_ing_min'] ?? '').toString().trim();
      if (fi.isNotEmpty && fi != '0000-00-00') conFecIng++;
    }
    int? edad;
    if (activa) {
      edad = GranjaCampaniaPicker.edadPromedioGalponesEnFecha(
        galponesMeta: meta,
        galponesSel: galponesSel,
        fechaYmd: fechaYmd,
      );
    }
    return (
      activa: activa,
      edad: edad,
      metaCount: meta.length,
      conFecIng: conFecIng,
      cenco: cenco,
    );
  }

  Future<({bool activa, int? edad, bool fromCp00})?> fetchEdadOnline({
    required StorageService storage,
    required String granja3,
    required String campania,
    required String galponCsv,
    required String fechaYmd,
  }) async {
    try {
      final res = await _api
          .getCampaniaInfo(
            granja: granja3,
            campania: campania,
            galpon: galponCsv,
            fecha: fechaYmd,
          )
          .timeout(_apiTimeout);
      if (res['success'] != true || res['data'] is! Map) return null;
      final d = Map<String, dynamic>.from(res['data'] as Map);
      await storage.mergeCampaniaInfoFromApi(
        granja3: granja3,
        campania: campania,
        data: d,
      );
      final activa = d['activa'] == true;
      final edadParsed = int.tryParse(d['edad']?.toString() ?? '');
      final fuenteCp =
          d['edad_fuente']?.toString().trim() == 'cargaproduccion00';
      final fromCp00 =
          fuenteCp && edadParsed != null && edadParsed > 0 && activa;
      return (
        activa: activa,
        edad: fromCp00 ? edadParsed : null,
        fromCp00: fromCp00,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> refreshProyeccionPorFecha({
    required StorageService storage,
    required String fechaYmd,
  }) async {
    try {
      final res = await _api
          .downloadProyeccion(fecha: fechaYmd)
          .timeout(_apiTimeout);
      if (res['success'] == true && res['data'] is Map) {
        await storage.saveProyeccion(
          Map<String, dynamic>.from(res['data'] as Map),
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  static bool _activaPorCencoEnCatalogo(
    StorageService storage,
    String granja3,
    String campania,
  ) {
    final cod6 = GalponesResolver.normalizarCodigoCenco(
      GalponesResolver.codigoCenco6(granja3, campania),
    );
    if (cod6.length < 6) return false;
    return storage.getCencosListaLocal().any((c) {
      return GalponesResolver.normalizarCodigoCenco(
            (c['codigo'] ?? '').toString(),
          ) ==
          cod6;
    });
  }
}
