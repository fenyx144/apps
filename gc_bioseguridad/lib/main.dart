import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/splash_screen.dart';
import 'services/catalog_service.dart';
import 'services/storage_service.dart';
import 'utils/app_theme.dart';
import 'utils/constants.dart';
import 'utils/route_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );
  AppTheme.applySystemChrome();
  final prefs = await SharedPreferences.getInstance();
  // Diseño: la sesión no persiste entre arranques. Cada arranque del proceso
  // (incluido hot restart) comienza con sesión cerrada; el usuario debe
  // iniciar sesión de nuevo. Los catálogos y registros guardados se conservan.
  await prefs.setBool(AppConstants.keyIsLoggedIn, false);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => StorageService(prefs),
          lazy: false,
        ),
        ChangeNotifierProvider(
          create: (_) {
            final catalog = CatalogService();
            catalog.loadFromPrefs();
            return catalog;
          },
          lazy: false,
        ),
      ],
      child: const BioseguridadApp(),
    ),
  );
}

class BioseguridadApp extends StatelessWidget {
  const BioseguridadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Bioseguridad',
      locale: const Locale('es', 'ES'),
      navigatorObservers: [routeObserver],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES')],
      debugShowCheckedModeBanner: false,
      defaultTransition: Transition.fadeIn,
      transitionDuration: const Duration(milliseconds: 300),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      builder: (context, child) {
        return _AppLifecycleObserver(child: child ?? const SizedBox.shrink());
      },
      home: const SplashScreen(),
    );
  }
}

/// Cierra la sesión cuando la app se cierra por completo (design: la sesión
/// no debe persistir entre arranques). No borra catálogos ni registros.
class _AppLifecycleObserver extends StatefulWidget {
  const _AppLifecycleObserver({required this.child});

  final Widget child;

  @override
  State<_AppLifecycleObserver> createState() => _AppLifecycleObserverState();
}

class _AppLifecycleObserverState extends State<_AppLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppTheme.applySystemChrome(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void didChangePlatformBrightness() {
    AppTheme.applySystemChrome(
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      unawaited(context.read<StorageService>().clearSession());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
