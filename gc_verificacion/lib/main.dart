import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/splash_screen.dart';
import 'services/face_engine.dart';
import 'services/nomina_store.dart';
import 'services/rostro_detector.dart';
import 'services/rostro_embedder.dart';
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
  await initializeDateFormatting('es_ES');
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(AppConstants.keyIsLoggedIn, false);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => StorageService(prefs),
          lazy: false,
        ),
        ChangeNotifierProvider(create: (_) => NominaStore(), lazy: false),
        Provider(
          create: (ctx) => FaceEngine(
            detector: RostroDetector(),
            embedder: OnnxRostroEmbedder(),
            nominas: ctx.read<NominaStore>(),
          ),
        ),
      ],
      child: const VerificacionApp(),
    ),
  );
}

class VerificacionApp extends StatelessWidget {
  const VerificacionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstants.appTitle,
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
        AppTheme.applySystemChrome(Theme.of(context).brightness);
        return _AppLifecycleObserver(child: child ?? const SizedBox.shrink());
      },
      home: const SplashScreen(),
    );
  }
}

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
