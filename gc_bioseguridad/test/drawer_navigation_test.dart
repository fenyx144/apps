import 'package:bioseguridad/screens/register_cerco_screen.dart';
import 'package:bioseguridad/screens/register_control_ingreso_screen.dart';
import 'package:bioseguridad/screens/register_fomites_screen.dart';
import 'package:bioseguridad/screens/register_garita_screen.dart';
import 'package:bioseguridad/services/catalog_service.dart';
import 'package:bioseguridad/services/storage_service.dart';
import 'package:bioseguridad/utils/constants.dart';
import 'package:bioseguridad/widgets/app_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pantalla mínima que sólo hospeda el drawer, para probar la navegación.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(drawer: AppDrawer(), body: SizedBox.shrink());
}

Finder _enDrawer(String texto) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(texto));

/// Desplaza la lista del menú hasta que [destino] esté montado.
Future<void> _desplazarHasta(WidgetTester tester, Finder destino) async {
  if (destino.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    destino,
    80,
    scrollable: find
        .descendant(of: find.byType(Drawer), matching: find.byType(Scrollable))
        .first,
  );
  await tester.pumpAndSettle();
}

/// Abre el drawer y toca el ítem [titulo].
///
/// El objetivo se busca dentro del [Drawer] a propósito: cuando ya estamos en
/// una sección, su AppBar muestra el mismo texto que el ítem del menú. Además,
/// la lista del menú puede quedar más alta que la ventana de pruebas, así que se
/// desplaza hasta que el ítem se monte antes de tocarlo.
///
/// [indice] elige cuál de las coincidencias se toca: «Anomalías» aparece una vez
/// por grupo de bioseguridad, y el orden de esos grupos es parte de lo que se
/// valida aquí.
Future<void> _irA(WidgetTester tester, String titulo, {int indice = 0}) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();

  final destino = _enDrawer(titulo).at(indice);
  await _desplazarHasta(tester, destino);
  // El ítem puede estar montado pero fuera del viewport (caché del ListView):
  // hay que traerlo a la vista o el toque no aterriza sobre él.
  await tester.ensureVisible(destino);
  await tester.pumpAndSettle();

  await tester.tap(destino);
  await tester.pumpAndSettle();
}

/// Abre (o cierra) el grupo de bioseguridad [label] del menú.
Future<void> _plegarGrupo(WidgetTester tester, String label) async {
  final encabezado = _enDrawer(label);
  await _desplazarHasta(tester, encabezado);
  await tester.ensureVisible(encabezado);
  await tester.pumpAndSettle();
  await tester.tap(encabezado);
  await tester.pumpAndSettle();
}

/// Abre el drawer del Scaffold visible.
Future<void> _abrirDrawer(WidgetTester tester) async {
  tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
  await tester.pumpAndSettle();
}

/// Color del título de un ítem del menú: el resaltado lo pinta en azul oscuro.
Color? _colorTitulo(WidgetTester tester, String titulo, {int indice = 0}) =>
    tester.widget<Text>(_enDrawer(titulo).at(indice)).style?.color;

Future<void> _montar(WidgetTester tester) async {
  // Ventana alta: el menú entero queda montado y visible, así las aserciones
  // sobre los grupos no dependen de haber desplazado la lista.
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => StorageService(prefs)),
        ChangeNotifierProvider(create: (_) => CatalogService()),
      ],
      child: const GetMaterialApp(home: _Host()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('los grupos de bioseguridad van en orden física, química y biológica', () {
    expect(
      bioNavTipos.map((t) => t.id).toList(),
      [BioTipos.fisica, BioTipos.quimica, BioTipos.biologica],
    );
    // Los rótulos son cortos: el drawer ya dibuja «BIOSEGURIDAD» sobre los tres.
    expect(
      bioNavTipos.map((t) => t.label).toList(),
      ['Física', 'Química', 'Biológica'],
    );

    // Las secciones de física en el orden del menú; los otros dos grupos solo
    // registran anomalías.
    expect(
      bioNavTipos.first.secciones.map((s) => s.label).toList(),
      [
        AppStrings.menuIngreso,
        AppStrings.menuSalida,
        AppStrings.menuCerco,
        AppStrings.menuFomites,
        AppStrings.menuInstalaciones,
      ],
    );
    for (final tipo in bioNavTipos.skip(1)) {
      expect(tipo.secciones.map((s) => s.id).toList(), [BioSecciones.anomalias]);
    }
  });

  testWidgets('el drawer permite encadenar secciones distintas', (tester) async {
    await _montar(tester);

    // 1ra navegación: GetX la aceptaba incluso con el bug de nombres duplicados.
    await _irA(tester, AppStrings.menuCerco);
    expect(find.byType(RegisterCercoScreen), findsOneWidget);

    // 2da navegación: aquí GetX devolvía null y no pasaba nada.
    await _irA(tester, AppStrings.menuFomites);
    expect(find.byType(RegisterFomitesScreen), findsOneWidget);
    expect(find.byType(RegisterCercoScreen), findsNothing);

    // 3ra navegación: confirma que la cadena no se rompe.
    await _irA(tester, AppStrings.menuInstalaciones);
    expect(find.byType(RegisterGaritaScreen), findsOneWidget);
    expect(find.byType(RegisterFomitesScreen), findsNothing);

    // 4ta: el cambio de nombre de «Instalaciones» a «Anomalías» no rompió nada.
    await _irA(tester, AppStrings.menuIngreso);
    expect(find.byType(RegisterControlIngresoScreen), findsOneWidget);
    expect(find.byType(RegisterGaritaScreen), findsNothing);
  });

  testWidgets('el drawer agrupa las secciones por tipo de bioseguridad y las '
      'plega', (tester) async {
    await _montar(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    // Los tres encabezados existen y se alcanzan desplazándose en el mismo orden
    // en que los declara `bioNavTipos` (física, química, biológica).
    for (final tipo in bioNavTipos) {
      await _desplazarHasta(tester, _enDrawer(tipo.label));
      expect(_enDrawer(tipo.label), findsOneWidget);
    }

    // El grupo de física viene desplegado (el host no está en una ruta de
    // química ni biológica), así que sus cuatro secciones se ven una sola vez.
    expect(_enDrawer(AppStrings.menuIngreso), findsOneWidget);
    expect(_enDrawer(AppStrings.menuCerco), findsOneWidget);
    expect(_enDrawer(AppStrings.menuInstalaciones), findsOneWidget);

    // Química viene plegada: su Anomalías no está en el menú todavía.
    await _plegarGrupo(tester, 'Química');
    expect(_enDrawer(AppStrings.menuInstalaciones), findsNWidgets(2));

    // La 2.ª «Anomalías» es la de química: abre con ese tipo ya elegido.
    await _irA(tester, AppStrings.menuInstalaciones, indice: 1);

    final garita = tester.widget<RegisterGaritaScreen>(
      find.byType(RegisterGaritaScreen),
    );
    expect(garita.tipoInicial, BioTipos.quimica);
    expect(
      garita.bioseguridadInicial,
      BioTipos.descripcion[BioTipos.quimica],
    );
  });

  testWidgets('Reportes va después de los grupos de bioseguridad', (
    tester,
  ) async {
    await _montar(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    // Cierra la lista: va por debajo del rótulo de bioseguridad y del último
    // grupo, y por encima de «Opciones».
    final bioseguridad = tester.getTopLeft(_enDrawer('Bioseguridad')).dy;
    final biologica = tester.getTopLeft(_enDrawer('Biológica')).dy;
    final reportes = tester.getTopLeft(_enDrawer(AppStrings.menuReportes)).dy;
    final opciones = tester.getTopLeft(_enDrawer('Opciones')).dy;

    expect(reportes, greaterThan(bioseguridad));
    expect(reportes, greaterThan(biologica));
    expect(reportes, lessThan(opciones));
  });

  testWidgets('los bloques del menú van Navegación, Bioseguridad y Opciones', (
    tester,
  ) async {
    await _montar(tester);

    tester.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
    await tester.pumpAndSettle();

    final navegacion = tester.getTopLeft(_enDrawer('Navegación')).dy;
    final dashboard = tester.getTopLeft(_enDrawer(AppStrings.menuDashboard)).dy;
    final bioseguridad = tester.getTopLeft(_enDrawer('Bioseguridad')).dy;
    final reportes = tester.getTopLeft(_enDrawer(AppStrings.menuReportes)).dy;
    final opciones = tester.getTopLeft(_enDrawer('Opciones')).dy;

    // Navegación quedó con el dashboard solo, y Reportes pasó a cerrar la
    // bioseguridad, antes de Opciones.
    expect(dashboard, greaterThan(navegacion));
    expect(dashboard, lessThan(bioseguridad));
    expect(reportes, greaterThan(bioseguridad));
    expect(reportes, lessThan(opciones));
  });

  testWidgets('la sección actual se resalta y su grupo abre desplegado', (
    tester,
  ) async {
    await _montar(tester);

    // Control de personal vive en física: se resalta su fila y no las vecinas.
    await _irA(tester, AppStrings.menuIngreso);
    await _abrirDrawer(tester);

    expect(_colorTitulo(tester, AppStrings.menuIngreso), AppColors.primaryDark);
    expect(_colorTitulo(tester, AppStrings.menuCerco), isNot(AppColors.primaryDark));

    // Anomalías existe en los tres grupos: al entrar por química se resalta esa
    // y no la de física, y el grupo de química abre solo.
    await _plegarGrupo(tester, 'Química');
    await _irA(tester, AppStrings.menuInstalaciones, indice: 1);
    await _abrirDrawer(tester);

    // Química viene desplegada por ser la sección actual, y física plegada: en
    // el menú aparece una sola «Anomalías», la de química.
    expect(_enDrawer(AppStrings.menuIngreso), findsNothing);
    expect(_enDrawer(AppStrings.menuInstalaciones), findsOneWidget);
    expect(
      _colorTitulo(tester, AppStrings.menuInstalaciones),
      AppColors.primaryDark,
    );

    // Al desplegar física aparece su Anomalías, que no es la activa.
    await _plegarGrupo(tester, 'Física');
    expect(_enDrawer(AppStrings.menuInstalaciones), findsNWidgets(2));
    expect(
      _colorTitulo(tester, AppStrings.menuInstalaciones),
      isNot(AppColors.primaryDark),
      reason: 'la Anomalías de física no es la activa',
    );
    expect(
      _colorTitulo(tester, AppStrings.menuInstalaciones, indice: 1),
      AppColors.primaryDark,
      reason: 'la Anomalías de química sí es la activa',
    );
  });

  testWidgets('«Mis granjas» va en Opciones, antes de «Acerca de»', (
    tester,
  ) async {
    await _montar(tester);
    await _abrirDrawer(tester);

    final opciones = tester.getTopLeft(_enDrawer('Opciones')).dy;
    final granja = tester.getTopLeft(_enDrawer(AppStrings.menuMiGranja)).dy;
    final acerca = tester.getTopLeft(_enDrawer('Acerca de')).dy;

    expect(granja, greaterThan(opciones));
    expect(granja, lessThan(acerca));
  });

  testWidgets('Física, Química y Biológica van sangradas dentro de '
      'Bioseguridad', (tester) async {
    await _montar(tester);
    await _abrirDrawer(tester);

    final rotulo = tester.getTopLeft(_enDrawer('Navegación')).dx;
    final fisica = tester.getTopLeft(_enDrawer('Física')).dx;
    final ingreso = tester.getTopLeft(_enDrawer(AppStrings.menuIngreso)).dx;

    // Bioseguridad → grupo → sección: cada nivel entra un poco más adentro, así
    // se ve que física, química y biológica cuelgan de Bioseguridad.
    expect(fisica, greaterThan(rotulo));
    expect(ingreso, greaterThan(fisica));

    // Los tres grupos arrancan en la misma vertical: son hermanos, no escalones.
    for (final tipo in bioNavTipos) {
      expect(
        tester.getTopLeft(_enDrawer(tipo.label)).dx,
        fisica,
        reason: '«${tipo.label}» debe arrancar donde los otros grupos',
      );
    }
  });

  testWidgets('«Bioseguridad» se destaca con un ícono propio más grande', (
    tester,
  ) async {
    await _montar(tester);
    await _abrirDrawer(tester);

    final escudo = tester.widget<Icon>(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.byIcon(Icons.health_and_safety_rounded),
      ),
    );
    final iconoGrupo = tester.widget<Icon>(
      find.descendant(
        of: find.byType(Drawer),
        matching: find.byIcon(bioNavTipos.first.icon),
      ),
    );

    // El encabezado del bloque lleva un ícono más grande que los grupos y un
    // texto más grande que los otros rótulos del menú.
    expect(escudo.size, greaterThan(iconoGrupo.size!));
    final titulo = tester.widget<Text>(_enDrawer('Bioseguridad'));
    final rotulo = tester.widget<Text>(_enDrawer('Navegación'));
    expect(titulo.style!.fontSize!, greaterThan(rotulo.style!.fontSize!));
    expect(
      titulo.style!.fontWeight!.index,
      greaterThan(rotulo.style!.fontWeight!.index),
    );
  });
}
