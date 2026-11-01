import 'package:bioseguridad/services/proveedor_historial_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/widgets/proveedor_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('deduplica por RUC y fusiona nombre sin RUC duplicado', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final svc = ProveedorHistorialService(storage);

    await svc.registrar(
      const ProveedorSeleccion(ruc: '', nombre: 'ACME SAC'),
      fuente: 'manual',
    );
    await svc.registrar(
      const ProveedorSeleccion(ruc: '20123456789', nombre: 'ACME SAC'),
      fuente: 'plan',
    );

    final hits = svc.buscar('ACME');
    expect(hits.length, 1);
    expect(hits.first.ruc, '20123456789');
    expect(hits.first.enDispositivo, isTrue);
  });

  test('sin RUC distinto nombre queda como entradas separadas', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final svc = ProveedorHistorialService(storage);

    await svc.registrar(
      const ProveedorSeleccion(ruc: '', nombre: 'TRANSPORTES A'),
      fuente: 'ingreso',
    );
    await svc.registrar(
      const ProveedorSeleccion(ruc: '', nombre: 'TRANSPORTES B'),
      fuente: 'ingreso',
    );

    expect(svc.buscar('TRANS').length, 2);
  });
}
