import 'package:bioseguridad/screens/register_salida_screen.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('salida muestra escaneo cuando hay granja', (tester) async {
    SharedPreferences.setMockInitialValues({
      AppConstants.keyGranjaTrabajo: '621',
    });
    final storage = StorageService(await SharedPreferences.getInstance());

    await tester.pumpWidget(
      MultiProvider(
        providers: [ChangeNotifierProvider.value(value: storage)],
        child: const MaterialApp(home: RegisterSalidaScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1. Identificar'), findsOneWidget);
    expect(find.text('Escanear Documento'), findsWidgets);
    expect(find.text('Escanear Placa'), findsWidgets);
    expect(find.text('Ingreso manual documento'), findsOneWidget);
    expect(find.text('Ingreso manual placa'), findsOneWidget);
    expect(find.text('Granja'), findsNothing);
    expect(find.textContaining('planificadas'), findsNothing);
    expect(find.textContaining('Ver ficha de salida'), findsNothing);
    expect(find.byIcon(Icons.save_outlined), findsNothing);
  });
}
