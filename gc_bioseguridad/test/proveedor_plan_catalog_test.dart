import 'package:bioseguridad/services/proveedor_plan_catalog_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/widgets/proveedor_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('catálogo guardado se busca offline', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    await storage.saveProveedoresPlanCatalogJson(
      '''
      {"items":[{"ruc":"20111111111","razonsocial":"PLAN SAC"}]}
      ''',
    );
    final svc = ProveedorPlanCatalogService(storage);
    final hits = svc.buscar('PLAN');
    expect(hits.length, 1);
    expect(hits.first.catalogoPlanificacion, isTrue);
    expect(hits.first.ruc, '20111111111');
  });

  test('fusionar prioriza historial y deduplica RUC', () {
    const historial = [
      ProveedorCcteItem(
        ruc: '20111111111',
        razonsocial: 'PLAN SAC',
        enDispositivo: true,
      ),
    ];
    const catalogo = [
      ProveedorCcteItem(
        ruc: '20111111111',
        razonsocial: 'PLAN SAC OFICIAL',
        catalogoPlanificacion: true,
      ),
    ];
    final merged = fusionarBusquedaLocal(historial, catalogo);
    expect(merged.length, 1);
    expect(merged.first.enDispositivo, isTrue);
  });
}
