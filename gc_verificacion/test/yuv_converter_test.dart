import 'package:flutter_test/flutter_test.dart';
import 'package:gc_verificacion/utils/yuv_converter.dart';

void main() {
  group('yuv converter', () {
    test('giro frontal 270 se mantiene', () {
      final u = uprightPara(270);
      expect(u.giro, 270);
      expect(u.espejo, false);
    });

    test('giro trasero 90 se mantiene', () {
      final u = uprightPara(90);
      expect(u.giro, 90);
      expect(u.espejo, false);
    });

    test('giro 0 y 180 se mantienen', () {
      expect(uprightPara(0).giro, 0);
      expect(uprightPara(180).giro, 180);
    });

    test('tamaño vertical rota dimensiones', () {
      final t = uprightSize(1280, 720, 270);
      expect(t.ancho, 720);
      expect(t.alto, 1280);
    });

    test('tamaño sin giro conserva dimensiones', () {
      final t = uprightSize(1280, 720, 0);
      expect(t.ancho, 1280);
      expect(t.alto, 720);
    });
  });
}
