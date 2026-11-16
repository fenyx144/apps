import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../utils/vacuna_payload.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_table.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/screen_status_bar.dart';
import '../widgets/section_app_bar.dart';

/// Convierte fechas guardadas (yyyy-MM-dd o ISO completo) a dd/MM/yyyy.
String _fmtFecha(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  if (s.contains('/')) return s;
  final f = DateTime.tryParse(s);
  if (f == null) return s;
  return DateFormat('dd/MM/yyyy').format(f);
}

String _fmtHora(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '—';
  final partes = s.split(':');
  if (partes.length >= 2) return '${partes[0]}:${partes[1]}';
  return s;
}

/// Formatea un número del detalle sin decimales de más: 7.5 queda «7.5» y
/// 50.0 «50». En el detalle las cantidades viajan como número (JSON), no como
/// texto, así que hay que darles formato antes de mostrarlas.
String _fmtDecimal(Object? valor) {
  if (valor == null) return '—';
  final n = valor is num ? valor.toDouble() : double.tryParse(valor.toString());
  if (n == null) return valor.toString();
  final s = n.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

/// Extrapola la ruta local de una imagen del registro.
/// Los formularios guardan `{'path': '...'}`; registros antiguos podían
/// guardar la ruta suelta como String.
String? _rutaImagen(dynamic item) {
  if (item == null) return null;
  if (item is Map) {
    final p = item['path'] ?? item['ruta'] ?? item['archivo'];
    final s = p?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }
  final s = item.toString().trim();
  return s.isEmpty ? null : s;
}

/// Nombre visible de cada reporte.
/// El tipo guardado sigue siendo `garita` (es la tabla `rgarita` y la llave de
/// los registros ya enviados); lo que cambió es el nombre que ve el usuario.
String nombreReporte(String reporte) {
  switch (reporte) {
    case 'decloracion':
      return AppStrings.menuDecloracion;
    case 'vacunacion':
      return AppStrings.menuVacunacion;
  }
  return reporte;
}

IconData iconoReporte(String reporte) {
  switch (reporte) {
    case 'decloracion':
      return Icons.water_drop_outlined;
    case 'vacunacion':
      return Icons.vaccines_outlined;
  }
  return Icons.assignment_outlined;
}

/// Contenido reutilizable del resumen de un registro.
class RegisterSummaryContent extends StatelessWidget {
  const RegisterSummaryContent({
    super.key,
    required this.record,
    this.title = 'Resumen del registro',
  });

  final Map<String, dynamic> record;
  final String title;

  @override
  Widget build(BuildContext context) {
    final imagenes = ((record['imagenes'] as List?) ?? [])
        .map(_rutaImagen)
        .whereType<String>()
        .where((p) => File(p).existsSync())
        .toList();
    final granjaLabel = GranjaCampaniaPicker.formatGranjaLabel(
      record['granja']?.toString() ?? '',
      record['granjaNombre']?.toString() ?? '',
    );
    final reporte = record['reporte']?.toString() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title.isNotEmpty) ...[
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: context.textThemePrimary,
            ),
          ),
          const SizedBox(height: 16),
        ],
        _row(context, 'Reporte', nombreReporte(reporte)),
        _row(context, 'Fecha', _fmtFecha(record['fecha']?.toString() ?? '')),
        if (reporte != 'decloracion')
          _row(context, 'Turno', record['turno']?.toString() ?? '—'),
        _row(context, 'Granja', granjaLabel),
        _row(
          context,
          'Campaña',
          GranjaCampaniaPicker.padCampania(
            record['campania']?.toString() ?? '',
          ),
        ),
        if (reporte != 'decloracion')
          _row(
            context,
            'Registrado por',
            record['nombre_usuario']?.toString() ?? '—',
          ),
        const SizedBox(height: 8),
        ..._detalle(context, reporte),
        const SizedBox(height: 12),
        Text(
          'Imágenes',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: context.textThemeSecondary,
          ),
        ),
        const SizedBox(height: 8),
        imagenes.isEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Sin imágenes adjuntas',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                    color: context.textThemeMuted,
                  ),
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: imagenes.map((path) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppColors.radiusSm),
                    child: Image.file(
                      File(path),
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 90,
                        height: 90,
                        color: context.surfaceCard,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: context.textThemeMuted,
                          size: 26,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
      ],
    );
  }

  List<Widget> _detalle(BuildContext context, String reporte) {
    final registro = Map<String, dynamic>.from(
      (record['registro'] as Map?) ?? const {},
    );

    if (reporte == 'decloracion') {
      final filas = [
        (
          'Inicio',
          registro['hora_inicio']?.toString() ?? '',
          registro['cloro_inicio']?.toString() ?? '',
        ),
        (
          'Final',
          registro['hora_final']?.toString() ?? '',
          registro['cloro_final']?.toString() ?? '',
        ),
      ];
      return [
        _row(context, 'Galpones', 'TODOS'),
        const SizedBox(height: 12),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppColors.radiusSm),
          ),
          child: BioTable(
            caption: 'Decloración',
            rowHeight: 42,
            columns: const [
              BioColumn('Momento', width: 140, align: TextAlign.left),
              BioColumn('Hora', width: 110),
              BioColumn('Cloro residual', width: 130),
            ],
            rowCount: filas.length,
            rowBuilder: (context, index) {
              final (momento, hora, cloro) = filas[index];
              return [
                BioText(momento, align: TextAlign.left, fontSize: 11.5, bold: true),
                BioText(_fmtHora(hora), fontSize: 11.5),
                BioText(cloro.isEmpty ? '—' : '$cloro ppm', fontSize: 11.5),
              ];
            },
          ),
        ),
        const SizedBox(height: 12),
        _textFieldRow(
          context,
          'Responsable',
          registro['responsable']?.toString(),
        ),
        _textFieldRow(
          context,
          'Observaciones',
          registro['observacion']?.toString(),
        ),
      ];
    }

    if (reporte == 'vacunacion') {
      final galpones = _galponesVacuna(registro);
      // Todo el detalle del formato (secciones 3 a 8) viaja en una sola lista
      // de filas paramétricas; el resumen arma una tabla por sección.
      final detalle = ((registro['detalle'] as List?) ?? [])
          .whereType<Map>()
          .map((f) => Map<String, dynamic>.from(f))
          .toList();
      final edad = int.tryParse(registro['edad']?.toString() ?? '') ?? 0;
      return [
        _row(
          context,
          'Galpones',
          galpones.isEmpty ? 'Sin galpones' : galpones.join(', '),
          placeholder: galpones.isEmpty,
        ),
        if (edad > 0) _row(context, 'Edad promedio', '$edad días'),
        _row(context, 'Vacuna', registro['vacuna']?.toString() ?? '—'),
        _row(context, 'Lote', registro['lote']?.toString() ?? '—'),
        _row(
          context,
          'Expiración',
          _fmtFecha(registro['expiracion']?.toString() ?? ''),
        ),
        _row(
          context,
          'Dosis de frasco',
          registro['dosis_frasco']?.toString() ?? '—',
        ),
        _row(context, 'Laboratorio', registro['laboratorio']?.toString() ?? '—'),
        _row(
          context,
          'Responsable',
          registro['responsable']?.toString() ?? '',
          placeholder: (registro['responsable']?.toString() ?? '').isEmpty,
        ),
        const SizedBox(height: 12),
        _tablaCadena(
          detalle.where((f) => f['seccion'] == VacSeccion.cadena).toList(),
        ),
        const SizedBox(height: 12),
        _tablaEquipo(
          detalle.where((f) => f['seccion'] == VacSeccion.equipo).toList(),
        ),
        const SizedBox(height: 12),
        _tablaSedeo(
          galpones,
          detalle.where((f) => f['seccion'] == VacSeccion.sedeo).toList(),
        ),
        const SizedBox(height: 12),
        ..._tablasBebederos(
          context,
          detalle.where((f) => f['seccion'] == VacSeccion.bebederos).toList(),
        ),
        const SizedBox(height: 12),
        _tablaSolucion(
          galpones,
          edad,
          detalle.where((f) => f['seccion'] == VacSeccion.solucion).toList(),
        ),
        const SizedBox(height: 12),
        _tablaEficiencia(
          galpones,
          detalle.where((f) => f['seccion'] == VacSeccion.eficiencia).toList(),
        ),
      ];
    }

    return const [];
  }

  static const _filasSolucion = [
    'Edad',
    'Lectura inicial de medidor',
    'Lectura final de medidor',
    'Cantidad de agua (m3)',
    'Litros de vacuna preparada',
    'Marcador azul',
    'Temperatura Corral macho',
    'Temperatura Corral hembra',
    'Hora de inicio de vacunación',
    'Hora final de vacunación',
    'Tiempo de vacunación',
  ];

  List<String> _galponesVacuna(Map<String, dynamic> registro) {
    final deCabecera = ((registro['galpones'] as List?) ?? [])
        .map((g) => g.toString().trim())
        .where((g) => g.isNotEmpty)
        .toList();
    if (deCabecera.isNotEmpty) return deCabecera;
    final detalle = ((registro['detalle'] as List?) ?? []).whereType<Map>();
    final vistos = <String>[];
    for (final f in detalle) {
      final g = f['galpon']?.toString().trim() ?? '';
      if (g.isNotEmpty && !vistos.contains(g)) vistos.add(g);
    }
    return vistos;
  }

  Widget _cajaTabla(Widget child) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
      ),
      child: child,
    );
  }

  bool? _flagDe(Object? valor) {
    if (valor == null) return null;
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    final s = valor.toString().trim().toLowerCase();
    if (s == 'true' || s == '1' || s == 's' || s == 'si' || s == 'sí') {
      return true;
    }
    if (s == 'false' || s == '0' || s == 'n' || s == 'no') return false;
    return null;
  }

  /// Duración de vacunación siempre en `hh:mm`.
  /// El registro nuevo la guarda como texto (`01:30`). Si llegó como fracción
  /// de hora (`1.5`), se traduce a minutos para mostrarla igual.
  String _tiempoHhmm(Map<String, dynamic> fila) {
    final texto = fila['valor_texto']?.toString().trim() ?? '';
    final reloj = RegExp(r'^(\d{1,3}):(\d{2})$');
    final comoReloj = reloj.firstMatch(texto);
    if (comoReloj != null) {
      final h = int.parse(comoReloj.group(1)!);
      final m = comoReloj.group(2)!;
      return '${h.toString().padLeft(2, '0')}:$m';
    }
    final crudo = fila['valor_num'] ?? texto.replaceAll(',', '.');
    final horas = crudo is num ? crudo.toDouble() : double.tryParse('$crudo');
    if (horas == null) return texto.isEmpty ? '—' : texto;
    final minutos = (horas * 60).round();
    final h = minutos ~/ 60;
    final m = minutos % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String _textoFila(Map<String, dynamic> fila) {
    final texto = fila['valor_texto']?.toString().trim() ?? '';
    if (texto.isNotEmpty) return texto;
    final hora = fila['hora']?.toString().trim() ?? '';
    if (hora.isNotEmpty) return _fmtHora(hora);
    if (fila['valor_num'] != null) return _fmtDecimal(fila['valor_num']);
    return '—';
  }

  Map<String, dynamic>? _buscarFila(
    List<Map<String, dynamic>> filas, {
    required String galpon,
    required String parametro,
    String grupo = '',
  }) {
    final p = parametro.toLowerCase();
    final g = grupo.toLowerCase();
    for (final f in filas) {
      if ((f['galpon']?.toString() ?? '') != galpon) continue;
      if ((f['grupo']?.toString() ?? '').toLowerCase() != g) continue;
      if ((f['parametro']?.toString() ?? '').toLowerCase() != p) continue;
      return f;
    }
    return null;
  }

  Widget _tablaCadena(List<Map<String, dynamic>> filas) {
    return _cajaTabla(
      BioTable(
        caption: 'Cadena de frío',
        rowHeight: 42,
        columns: const [
          BioColumn('Descripción', width: 176, align: TextAlign.left),
          BioColumn('Hora', width: 90),
          BioColumn('Temperatura', width: 96),
        ],
        rowCount: filas.length,
        rowBuilder: (context, index) {
          final fila = filas[index];
          return [
            BioText(
              fila['parametro']?.toString() ?? '—',
              align: TextAlign.left,
              fontSize: 11,
              bold: true,
            ),
            BioText(_fmtHora(fila['hora']?.toString() ?? ''), fontSize: 11),
            BioText(
              fila['valor_num'] == null ? '—' : _fmtDecimal(fila['valor_num']),
              fontSize: 11,
            ),
          ];
        },
      ),
    );
  }

  Widget _tablaEquipo(List<Map<String, dynamic>> filas) {
    return _cajaTabla(
      BioTable(
        caption: 'Equipo de vacunación',
        rowHeight: 42,
        columns: const [
          BioColumn('Descripción', width: 176, align: TextAlign.left),
          BioColumn('Operativa', width: 110),
          BioColumn('Observación', width: 140, align: TextAlign.left),
        ],
        rowCount: filas.length,
        rowBuilder: (context, index) {
          final fila = filas[index];
          final operativo = _flagDe(fila['flag']);
          final obs = fila['valor_texto']?.toString().trim() ?? '';
          return [
            BioText(
              fila['parametro']?.toString() ?? '—',
              align: TextAlign.left,
              fontSize: 11,
              bold: true,
            ),
            BioText(
              operativo == null
                  ? '—'
                  : (operativo ? 'Sí' : 'No'),
              fontSize: 11,
              bold: true,
              color: operativo == null
                  ? null
                  : (operativo ? AppColors.success : AppColors.errorDark),
            ),
            BioText(
              obs.isEmpty ? '—' : obs,
              align: TextAlign.left,
              fontSize: 11,
            ),
          ];
        },
      ),
    );
  }

  Widget _tablaSedeo(List<String> galpones, List<Map<String, dynamic>> filas) {
    if (galpones.isEmpty) {
      return _cajaTabla(
        BioTable(
          caption: 'Tiempo de sedeó (horas)',
          columns: const [BioColumn('Galpón', width: 120)],
          rowCount: 1,
          rowBuilder: (context, index) => const [BioText('—')],
        ),
      );
    }
    return _cajaTabla(
      BioTable(
        caption: 'Tiempo de sedeó (horas)',
        rowHeight: 42,
        expandir: true,
        columns: [
          for (final g in galpones) BioColumn('Galpón $g', width: 80),
        ],
        rowCount: 1,
        rowBuilder: (context, _) => [
          for (final g in galpones)
            BioText(
              _textoFila(
                _buscarFila(filas, galpon: g, parametro: 'Horas') ?? const {},
              ),
              bold: true,
            ),
        ],
      ),
    );
  }

  List<Widget> _tablasBebederos(
    BuildContext context,
    List<Map<String, dynamic>> filas,
  ) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final f in filas) {
      final grupo = f['grupo']?.toString().trim() ?? '';
      grupos.putIfAbsent(grupo, () => []).add(f);
    }
    final tablas = <Widget>[
      Text(
        'Verificación del sistema de bebederos',
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: context.textThemeSecondary,
        ),
      ),
      const SizedBox(height: 8),
    ];
    if (grupos.isEmpty) {
      tablas.add(
        Text(
          'Sin registros de bebederos',
          style: TextStyle(
            fontStyle: FontStyle.italic,
            fontSize: 13,
            color: context.textThemeMuted,
          ),
        ),
      );
      return tablas;
    }
    var primero = true;
    for (final entry in grupos.entries) {
      if (!primero) tablas.add(const SizedBox(height: 12));
      primero = false;
      final items = entry.value;
      tablas.add(
        _cajaTabla(
          BioTable(
            caption: entry.key.isEmpty ? 'Bebederos' : entry.key,
            rowHeight: 42,
            expandir: true,
            columns: const [
              BioColumn('Descripción', width: 176, align: TextAlign.left),
              BioColumn('SI / NO', width: 88),
              BioColumn('Detalle', width: 120, flex: 1),
            ],
            rowCount: items.length,
            rowBuilder: (context, index) {
              final fila = items[index];
              final si = _flagDe(fila['flag']);
              final obs = fila['valor_texto']?.toString().trim() ?? '';
              final esOtro =
                  (fila['parametro']?.toString().trim() ?? '') == 'Otro';
              return [
                BioText(
                  fila['parametro']?.toString() ?? '—',
                  align: TextAlign.left,
                  bold: true,
                  fontSize: 11,
                ),
                BioText(
                  si == null ? '—' : (si ? 'SI' : 'NO'),
                  fontSize: 11,
                  bold: true,
                  color: si == null
                      ? null
                      : (si ? AppColors.errorDark : AppColors.success),
                ),
                BioText(
                  esOtro && obs.isNotEmpty ? obs : '—',
                  align: TextAlign.left,
                  fontSize: 11,
                ),
              ];
            },
          ),
        ),
      );
    }
    return tablas;
  }

  Widget _tablaSolucion(
    List<String> galpones,
    int edad,
    List<Map<String, dynamic>> filas,
  ) {
    final columnas = galpones.isEmpty
        ? const [BioColumn('Descripción', width: 168, align: TextAlign.left)]
        : [
            const BioColumn('Descripción', width: 168, align: TextAlign.left),
            for (final g in galpones) BioColumn('Galpón $g', width: 84),
          ];
    return _cajaTabla(
      BioTable(
        caption: 'Preparación de solución vacunal',
        rowHeight: 42,
        expandir: true,
        columns: columnas,
        rowCount: _filasSolucion.length,
        rowBuilder: (context, index) {
          final parametro = _filasSolucion[index];
          return [
            BioText(parametro, align: TextAlign.left, bold: true, fontSize: 11),
            for (final g in galpones)
              BioText(
                parametro == 'Edad'
                    ? (edad > 0 ? '$edad días' : '—')
                    : parametro == 'Tiempo de vacunación'
                        ? _tiempoHhmm(
                            _buscarFila(
                                  filas,
                                  galpon: g,
                                  parametro: parametro,
                                ) ??
                                const {},
                          )
                        : _textoFila(
                            _buscarFila(
                                  filas,
                                  galpon: g,
                                  parametro: parametro,
                                ) ??
                                const {},
                          ),
                bold: true,
                fontSize: 11,
              ),
          ];
        },
      ),
    );
  }

  Widget _tablaEficiencia(
    List<String> galpones,
    List<Map<String, dynamic>> filas,
  ) {
    String celda(String galpon, String grupo, String parametro) {
      final fila = _buscarFila(
        filas,
        galpon: galpon,
        grupo: grupo,
        parametro: parametro,
      );
      if (fila == null) return '—';
      final texto = _textoFila(fila);
      if (parametro.toLowerCase() == 'eficiencia' && texto != '—') {
        return texto.endsWith('%') ? texto : '$texto%';
      }
      return texto;
    }

    int? eficienciaDe(String galpon) {
      final fila = _buscarFila(
        filas,
        galpon: galpon,
        parametro: 'Eficiencia',
      );
      if (fila == null || fila['valor_num'] == null) return null;
      final n = fila['valor_num'];
      if (n is num) return n.round();
      return int.tryParse(n.toString());
    }

    return _cajaTabla(
      BioTable(
        caption: 'Evaluación de eficiencia de vacunación',
        rowHeight: 42,
        expandir: true,
        groups: const [
          BioColGroup('Pollos evaluados', desde: 1, hasta: 2),
          BioColGroup('Pollos con vacuna', desde: 4, hasta: 5),
          BioColGroup('Pollos sin vacuna', desde: 6, hasta: 7),
        ],
        columns: const [
          BioColumn('Galpón', width: 66),
          BioColumn('Macho', width: 70),
          BioColumn('hembra', width: 70),
          BioColumn('Cantidad total', width: 88),
          BioColumn('Macho', width: 70),
          BioColumn('hembra', width: 70),
          BioColumn('Macho', width: 70),
          BioColumn('hembra', width: 70),
          BioColumn('Eficiencia', width: 88),
        ],
        rowCount: galpones.length,
        rowBuilder: (context, index) {
          final g = galpones[index];
          final eficiencia = eficienciaDe(g);
          return [
            BioText(g, bold: true),
            BioText(celda(g, 'Pollos evaluados', 'Macho')),
            BioText(celda(g, 'Pollos evaluados', 'hembra')),
            BioText(celda(g, '', 'Cantidad total'), bold: true),
            BioText(celda(g, 'Pollos con vacuna', 'Macho')),
            BioText(celda(g, 'Pollos con vacuna', 'hembra')),
            BioText(celda(g, 'Pollos sin vacuna', 'Macho')),
            BioText(celda(g, 'Pollos sin vacuna', 'hembra')),
            BioText(
              celda(g, '', 'Eficiencia'),
              bold: true,
              color: eficiencia == null
                  ? null
                  : (eficiencia >= 90 ? AppColors.success : AppColors.errorDark),
            ),
          ];
        },
      ),
    );
  }

  Widget _textFieldRow(BuildContext context, String label, String? raw) {
    final value = raw?.trim() ?? '';
    return _row(
      context,
      label,
      value.isEmpty ? 'No ingresado' : value,
      placeholder: value.isEmpty,
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool placeholder = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                '$label:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: context.textThemeSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: placeholder
                      ? context.textThemeMuted
                      : context.textThemePrimary,
                  fontStyle: placeholder ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Modal de resumen a pantalla completa antes de guardar.
/// Si [onConfirm] es null, el modal es de solo lectura.
class RegisterSummarySheet {
  static Future<bool> show(
    BuildContext context, {
    required Map<String, dynamic> record,
    Future<void> Function()? onConfirm,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 1.0,
        minChildSize: 0.5,
        maxChildSize: 1.0,
        builder: (context, scrollController) => ScreenStatusBar(
          color: sheetContext.scaffoldMuted,
          child: Container(
            decoration: BoxDecoration(
              color: sheetContext.scaffoldMuted,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: sheetContext.surfaceCard,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                    boxShadow: sheetContext.cardShadow(blur: 10, dy: -2),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: sheetContext.textThemeMuted
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.fact_check_outlined,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Resumen del registro',
                              style: TextStyle(
                                color: sheetContext.textThemePrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: sheetContext.textThemeSecondary,
                            ),
                            onPressed: () =>
                                Navigator.pop(sheetContext, false),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: sheetContext.surfaceCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2),
                        ),
                      ),
                      child: RegisterSummaryContent(record: record, title: ''),
                    ),
                  ),
                ),
                if (onConfirm != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: sheetContext.surfaceCard,
                      boxShadow: sheetContext.cardShadow(blur: 10, dy: -2),
                    ),
                    child: SafeArea(
                      top: false,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: () async {
                              await onConfirm();
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext, true);
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Confirmar y Guardar',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return result ?? false;
  }
}

/// Vista de solo lectura para reportes.
class RegisterSummaryScreen extends StatelessWidget {
  const RegisterSummaryScreen({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final reporte = record['reporte']?.toString() ?? '';
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: nombreReporte(reporte),
        sectionIcon: iconoReporte(reporte),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RegisterSummaryContent(
              record: record,
              title: 'Registro guardado',
            ),
          ),
        ),
      ),
    );
  }
}
