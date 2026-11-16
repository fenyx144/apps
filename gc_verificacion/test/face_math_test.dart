import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gc_verificacion/services/nomina_store.dart';
import 'package:gc_verificacion/utils/face_math.dart';

Float32List _base(int seno) {
  final v = Float32List(512);
  v[seno] = 1;
  return v;
}

PersonaFace _persona(String dni, Float32List v) {
  return PersonaFace(dni: dni, nombre: 'N $dni', vector: v);
}

void main() {
  group('face math', () {
    test('coseno de idénticos es 1', () {
      final v = _base(0);
      expect(coseno(v, v), closeTo(1, 1e-6));
    });

    test('coseno de ortogonales es 0', () {
      expect(coseno(_base(0), _base(1)), closeTo(0, 1e-6));
    });

    test('normalizar deja norma 1', () {
      final v = normalizar([3, 4]);
      expect(v[0], closeTo(0.6, 1e-6));
      expect(v[1], closeTo(0.8, 1e-6));
    });

    test('decidir ok con margen', () {
      final d = decidir(
        emb: _base(0),
        todas: [_persona('11111111', _base(0)), _persona('22222222', _base(1))],
        umbral: 0.45,
        margen: 0.10,
      );
      expect(d.estado, DecisionEstado.ok);
      expect(d.persona?.dni, '11111111');
      expect(d.sim, closeTo(1, 1e-6));
    });

    test('decidir ambiguo sin margen', () {
      final mitad = Float32List(512);
      mitad[0] = 0.7071068;
      mitad[1] = 0.7071068;
      final d = decidir(
        emb: mitad,
        todas: [_persona('11111111', _base(0)), _persona('22222222', _base(1))],
        umbral: 0.45,
        margen: 0.10,
      );
      expect(d.estado, DecisionEstado.ambiguo);
    });

    test('decidir no bajo umbral', () {
      final neg = Float32List(512);
      neg[0] = -1;
      final d = decidir(
        emb: neg,
        todas: [_persona('11111111', _base(0))],
        umbral: 0.45,
        margen: 0.10,
      );
      expect(d.estado, DecisionEstado.no);
    });

    test('decidir 1:1 compara contra el resto', () {
      final d = decidir(
        emb: _base(0),
        todas: [_persona('11111111', _base(0)), _persona('22222222', _base(0))],
        doc: '11111111',
        umbral: 0.45,
        margen: 0.10,
      );
      expect(d.estado, DecisionEstado.ambiguo);
      expect(d.segundo, closeTo(1, 1e-6));
    });

    test('votos cuentan 3 de 5', () {
      final v = Votos();
      v.push('a');
      v.push(null);
      v.push('a');
      v.push('b');
      v.push('a');
      expect(v.contar('a'), 3);
      v.push('b');
      expect(v.contar('a'), 2);
    });

    test('similar identidad', () {
      final src = [for (final p in tpl112) Offset(p[0], p[1])];
      final m = similarSrcDst(src, tpl112);
      expect(m[0], closeTo(1, 1e-9));
      expect(m[1], closeTo(0, 1e-9));
      expect(m[4], closeTo(0, 1e-6));
      expect(m[5], closeTo(0, 1e-6));
    });

    test('warp de imagen plana', () {
      final rgb = Uint8List(4 * 4 * 3)..fillRange(0, 48, 127);
      final src = [
        const Offset(0, 0),
        const Offset(3, 0),
        const Offset(1.5, 1.5),
        const Offset(0, 3),
        const Offset(3, 3),
      ];
      final out = warp112(rgb, 4, 4, src);
      expect(out.length, 3 * 112 * 112);
      expect(out[0], closeTo((127 - 127.5) / 127.5, 1e-6));
    });

    test('stats de gris plano', () {
      final rgb = Uint8List(8 * 8 * 3)..fillRange(0, 8 * 8 * 3, 100);
      final st = statsRegion(rgb, 8, 8);
      expect(st.brillo, closeTo(100, 1e-6));
      expect(st.nitidez, closeTo(0, 1e-6));
    });

    test('guia enrolar frontal centrado', () {
      expect(
        guiaEnrolar(
          caja: const Rect.fromLTWH(300, 400, 220, 220),
          yaw: 5,
          pitch: -4,
          ancho: 720,
          alto: 1280,
          exigirCentro: true,
        ),
        isNull,
      );
    });

    test('guia enrolar descentrado', () {
      expect(
        guiaEnrolar(
          caja: const Rect.fromLTWH(50, 400, 220, 220),
          yaw: 0,
          pitch: 0,
          ancho: 720,
          alto: 1280,
          exigirCentro: true,
        ),
        'Centre el rostro',
      );
    });

    test('guia enrolar sin centro exigido', () {
      expect(
        guiaEnrolar(
          caja: const Rect.fromLTWH(50, 400, 220, 220),
          yaw: 0,
          pitch: 0,
          ancho: 720,
          alto: 1280,
          exigirCentro: false,
        ),
        isNull,
      );
    });

    test('guia enrolar girado', () {
      expect(
        guiaEnrolar(
          caja: const Rect.fromLTWH(300, 400, 220, 220),
          yaw: 20,
          pitch: 0,
          ancho: 720,
          alto: 1280,
          exigirCentro: true,
        ),
        'Mire de frente',
      );
    });

    test('guia enrolar lejos', () {
      expect(
        guiaEnrolar(
          caja: const Rect.fromLTWH(300, 400, 100, 100),
          yaw: 0,
          pitch: 0,
          ancho: 720,
          alto: 1280,
          exigirCentro: true,
        ),
        'Acérquese',
      );
    });

    test('tiempos mediana y p95', () {
      final t = TiemposMotor();
      for (var i = 1; i <= 100; i++) {
        t.add('x', i.toDouble());
      }
      expect(t.mediana('x'), closeTo(50.5, 1));
      expect(t.p95('x'), closeTo(95, 1));
      expect(t.n('x'), 100);
    });
  });
}
