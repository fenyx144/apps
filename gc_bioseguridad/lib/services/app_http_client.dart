import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Red interna / Apache con certificado autofirmado (mismo criterio en toda la app).
bool aceptarCertificadoInterno(String host) {
  final h = host.toLowerCase();
  if (h == 'localhost' || h == '127.0.0.1') return true;
  if (h.startsWith('10.')) return true;
  if (h.startsWith('192.168.')) return true;
  if (h.contains('granjarinconadadelsur.com')) return true;
  if (h.startsWith('172.')) {
    final parts = h.split('.');
    if (parts.length >= 2) {
      final segundo = int.tryParse(parts[1]);
      if (segundo != null && segundo >= 16 && segundo <= 31) return true;
    }
  }
  return false;
}

/// Debe registrarse en `main()` antes de cualquier request HTTP.
class InternalHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      final ok = aceptarCertificadoInterno(host);
      if (kDebugMode && !ok) {
        // ignore: avoid_print
        print('[TLS] certificado rechazado para host=$host port=$port');
      }
      return ok;
    };
    return client;
  }
}

void configureInternalHttps() {
  if (!kIsWeb) {
    HttpOverrides.global = InternalHttpOverrides();
  }
}

/// Cliente HTTP (usa el [HttpClient] global con certificados internos).
http.Client createAppHttpClient() {
  if (kIsWeb) {
    return http.Client();
  }
  final inner = HttpClient();
  inner.badCertificateCallback = (cert, host, port) => aceptarCertificadoInterno(host);
  return IOClient(inner);
}
