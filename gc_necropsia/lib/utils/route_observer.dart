import 'package:flutter/widgets.dart';

/// RouteObserver global para poder re-disparar animaciones al volver a una pantalla.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();
