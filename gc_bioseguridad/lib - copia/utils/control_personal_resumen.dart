/// Textos compartidos para resúmenes, tarjetas y reportes de control personal.

/// «N° de vehículos: 1 · N° de personas: 3»
String lineaConteoPersonal({required int personas, required int vehiculos}) {
  return 'N° de vehículos: $vehiculos · N° de personas: $personas';
}

/// Partes sueltas para reportes (solo si el conteo es mayor que 0). Vehículos primero.
List<String> partesConteoPersonal({required int personas, required int vehiculos}) {
  return [
    if (vehiculos > 0) 'N° de vehículos: $vehiculos',
    if (personas > 0) 'N° de personas: $personas',
  ];
}
