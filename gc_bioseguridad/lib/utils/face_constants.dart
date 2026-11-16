/// Parámetros del motor facial copiados de gc_verificacion.
class FaceConstants {
  static const String verificacionPath = '/verificacion';
  static const String nominaEndpoint = '/get_nomina_movil.php';

  static const double umbralDefecto = 0.45;
  static const double margenDefecto = 0.10;
  static const int votosRequeridos = 3;
  static const int ventanaVotos = 5;
  static const double giroMaxGrados = 15;
  static const int rechazosFinal11 = 8;
  static const String faceModel = 'arcface-w600k_mbf';
  static const double boxMinFrac = 0.22;
  static const double centroXTol = 0.18;
  static const double centroYTol = 0.2;
  static const double brilloMin = 60;
  static const double brilloMax = 215;
  static const double nitidezMin = 60;
}
