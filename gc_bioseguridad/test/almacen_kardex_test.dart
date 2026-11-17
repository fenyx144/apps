import 'package:bioseguridad/services/almacen_kardex.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = [
    AlmacenLinea(frente: 'LIMPIO', item: '2', nombre: 'Ropa para el proceso', si: 20),
    AlmacenLinea(frente: 'LAVADERO', item: '2', nombre: 'Ropa para el proceso'),
    AlmacenLinea(frente: 'INSUMOS', item: '6', nombre: 'Alcohol 70%', si: 10),
  ];

  test('entrega y recepción no dejan el lavadero en negativo', () {
    final out = aplicarAlmacen(base, [
      {'operacion': 'ENTREGA', 'item': '2', 'cantidad': 1},
      {'operacion': 'RECEPCION', 'item': '2', 'cantidad': 1},
      {'operacion': 'LAVADO', 'item': '2', 'cantidad': 2},
    ]);
    final limpio = out.firstWhere((l) => l.frente == 'LIMPIO');
    final lavadero = out.firstWhere((l) => l.frente == 'LAVADERO');
    expect(limpio.stock, 19);
    expect(lavadero.stock, 1);
    expect(rechazoAlmacen(out, operacion: 'LAVADO', item: '2', cantidad: 2), 'Sin stock');
  });

  test('el consumo resta insumos y no el almacén limpio', () {
    final out = aplicarAlmacen(base, [
      {'operacion': 'CONSUMO', 'item': '6', 'cantidad': 2},
    ]);
    expect(out.firstWhere((l) => l.frente == 'LIMPIO').stock, 20);
    expect(out.firstWhere((l) => l.frente == 'INSUMOS' && l.item == '6').stock, 8);
    expect(rechazoAlmacen(out, operacion: 'CONSUMO', item: '6', cantidad: 9), 'Sin stock');
  });

  test('el relevo pasa el uniforme limpio al lavadero y no cambia implementos', () {
    final conImp = [
      ...base,
      AlmacenLinea(frente: 'IMPLEMENTOS', item: '4', nombre: 'Botas', si: 3),
    ];
    final out = aplicarAlmacen(conImp, [
      {'operacion': 'RELEVO', 'categoria': 'UNIFORME', 'item': '2', 'cantidad': 1},
    ]);
    expect(out.firstWhere((l) => l.frente == 'LIMPIO' && l.item == '2').stock, 19);
    expect(out.firstWhere((l) => l.frente == 'LAVADERO').stock, 1);
    expect(out.firstWhere((l) => l.frente == 'IMPLEMENTOS').stock, 3);
    expect(rechazoAlmacen(out, operacion: 'RELEVO', item: '2', cantidad: 1), isNull);
  });

  test('no se entregan más limpios de los que hay', () {
    expect(rechazoAlmacen(base, operacion: 'ENTREGA', item: '2', cantidad: 21), 'Sin stock');
    final out = aplicarAlmacen(base, [
      {'operacion': 'ENTREGA', 'item': '2', 'cantidad': 21},
    ]);
    expect(out.firstWhere((l) => l.frente == 'LIMPIO').stock, 20);
  });
}
