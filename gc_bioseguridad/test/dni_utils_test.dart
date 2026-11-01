import 'package:bioseguridad/utils/dni_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DniCodeParser.parse', () {
    test('acepta el número solo', () {
      expect(DniCodeParser.parse('12345678'), '12345678');
      expect(DniCodeParser.parse('  12345678  '), '12345678');
    });

    test('toma el DNI de una trama separada por «|»', () {
      expect(
        DniCodeParser.parse('12345678|PEREZ QUISPE JUAN|1990-01-01'),
        '12345678',
      );
      expect(DniCodeParser.parse('APELLIDOS,NOMBRES|12345678'), '12345678');
      expect(DniCodeParser.parse('12345678 , 87654321'), '12345678');
    });

    test('toma el DNI pegado al inicio del contenido (PDF417)', () {
      expect(DniCodeParser.parse('12345678PEREZ QUISPE JUAN'), '12345678');
    });

    test('usa el único bloque de 8 dígitos si la trama no es clara', () {
      expect(DniCodeParser.parse('DNI: 12345678 ok'), '12345678');
    });

    test('toma el primer candidato cuando la trama trae varios', () {
      // En un listado el documento suele ir primero; se prefiere ese orden a
      // rechazar el escaneo.
      expect(DniCodeParser.parse('12345678 87654321'), '12345678');
    });

    test('no inventa un DNI cuando los dígitos están pegados', () {
      // 20 dígitos seguidos: ningún bloque de 8 es claramente el documento,
      // así que es mejor pedir otro escaneo que guardar un DNI equivocado.
      expect(DniCodeParser.parse('12345678901234567890'), isNull);
    });

    test('devuelve null con contenido vacío o sin 8 dígitos', () {
      expect(DniCodeParser.parse(null), isNull);
      expect(DniCodeParser.parse(''), isNull);
      expect(DniCodeParser.parse('   '), isNull);
      expect(DniCodeParser.parse('1234567'), isNull);
      expect(DniCodeParser.parse('https://ejemplo.com'), isNull);
    });
  });

  group('parseDnisEntradas', () {
    test('lee los pares {dni, nombre} que guarda el formulario', () {
      final r = parseDnisEntradas([
        {'dni': '12345678', 'nombre': 'JUAN PEREZ'},
        {'dni': '87654321', 'nombre': ''},
      ]);
      expect(r.length, 2);
      expect(r[0].dni, '12345678');
      expect(r[0].nombre, 'JUAN PEREZ');
      expect(r[0].etiqueta, '12345678 · JUAN PEREZ');
      expect(r[1].etiqueta, '87654321');
    });

    test('lee la lista de números de los registros anteriores', () {
      final r = parseDnisEntradas(['12345678', '87654321']);
      expect(r.map((e) => e.dni), ['12345678', '87654321']);
      expect(r.every((e) => e.nombre.isEmpty), isTrue);
    });

    test('lee el texto separado por comas que llega de la web', () {
      final r = parseDnisEntradas('12345678, 87654321');
      expect(r.map((e) => e.dni), ['12345678', '87654321']);
    });

    test('descarta vacíos y repetidos conservando el orden', () {
      final r = parseDnisEntradas([
        {'dni': '', 'nombre': 'X'},
        {'dni': '12345678', 'nombre': 'A'},
        '12345678',
        {'dni': '87654321', 'nombre': 'B'},
      ]);
      expect(r.map((e) => e.dni), ['12345678', '87654321']);
      expect(r.first.nombre, 'A');
    });

    test('devuelve lista vacía con valores nulos o desconocidos', () {
      expect(parseDnisEntradas(null), isEmpty);
      expect(parseDnisEntradas(''), isEmpty);
      expect(parseDnisEntradas(const <String>[]), isEmpty);
    });

    test('listaDnisNumeros descarta los nombres', () {
      expect(
        listaDnisNumeros([
          {'dni': '12345678', 'nombre': 'JUAN'},
        ]),
        ['12345678'],
      );
    });
  });

  group('DniEntrada', () {
    test('toJson conserva documento y nombre para el backend', () {
      const e = DniEntrada(dni: '12345678', nombre: 'JUAN PEREZ');
      expect(e.toJson(), {'dni': '12345678', 'nombre': 'JUAN PEREZ'});
    });
  });

  group('nombreDniEfectivo', () {
    test('usa el nombre que resolvió la consulta', () {
      expect(
        nombreDniEfectivo(resuelto: 'JUAN PEREZ', manual: ''),
        'JUAN PEREZ',
      );
    });

    test('en línea y a mano a la vez gana el de la consulta', () {
      expect(
        nombreDniEfectivo(resuelto: 'JUAN PEREZ', manual: 'juan peres'),
        'JUAN PEREZ',
      );
    });

    test('sin consulta usa el nombre escrito a mano', () {
      // El caso del guardia sin conexión: el documento no está en el catálogo
      // local y el nombre lo escribe él.
      expect(
        nombreDniEfectivo(resuelto: '', manual: 'JUAN PEREZ'),
        'JUAN PEREZ',
      );
    });

    test('sin ninguno de los dos devuelve vacío', () {
      expect(nombreDniEfectivo(resuelto: '', manual: ''), '');
      expect(nombreDniEfectivo(resuelto: '   ', manual: '  '), '');
    });
  });
}
