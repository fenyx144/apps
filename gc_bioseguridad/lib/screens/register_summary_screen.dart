import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/catalog_service.dart';
import '../services/ingreso_presencia_service.dart';
import '../utils/constants.dart';
import '../utils/control_personal_resumen.dart';
import '../utils/dni_utils.dart';
import '../utils/theme_colors.dart';
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

Widget _resumenEtiquetaValor(
  BuildContext context,
  String etiqueta,
  String valor, {
  int maxLines = 2,
}) {
  final v = valor.trim().isEmpty ? '—' : valor.trim();
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: context.textThemePrimary,
        ),
        children: [
          TextSpan(
            text: '$etiqueta: ',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: context.textThemeSecondary,
            ),
          ),
          TextSpan(
            text: v,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

String _fmtHora(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '—';
  final partes = s.split(':');
  if (partes.length >= 2) return '${partes[0]}:${partes[1]}';
  return s;
}

String _etiquetaPermisoIngresoGranja(bool ingresa) =>
    ingresa ? 'Ingresa a granja' : 'No ingresa a granja';

List<Map<String, dynamic>> _alcoholemiaPruebasResumen(
  Map<String, dynamic> registro,
) {
  final raw = registro['alcoholemia_pruebas'];
  if (raw is List && raw.isNotEmpty) {
    return [
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
  }
  final uno = registro['alcoholemia'];
  if (uno is Map) {
    final dni = (uno['dni'] ?? '').toString().trim();
    final grado = (uno['grado_g_l'] ?? '').toString().trim();
    if (dni.isNotEmpty && grado.isNotEmpty) {
      return [Map<String, dynamic>.from(uno)];
    }
  }
  return const [];
}

double? _parseGradoGlResumen(dynamic v) {
  final s = v?.toString().trim().replaceAll(',', '.') ?? '';
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

String _estadoAlcoholemiaResumen(double? grado, double umbral) {
  if (grado == null) return '—';
  if (grado > umbral) return 'Supera';
  return 'OK';
}

bool _boolResumen(dynamic v, {bool defaultValue = false}) {
  if (v == null) return defaultValue;
  if (v is bool) return v;
  if (v == 1 || v == '1' || v == 'true' || v == 'S' || v == 's') return true;
  if (v == 0 || v == '0' || v == 'false' || v == 'N' || v == 'n') return false;
  return defaultValue;
}

List<Map<String, dynamic>> _articulosRegistroResumen(
  Map<String, dynamic> registro,
) {
  final raw = registro['articulos'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) Map<String, dynamic>.from(item),
  ];
}

List<Map<String, dynamic>> _anomaliasArticulosResumen(
  List<Map<String, dynamic>> items,
) {
  final out = <Map<String, dynamic>>[];
  for (final a in items) {
    final nombre = (a['descripcion'] ?? '').toString().trim();
    if (nombre.isEmpty) continue;
    final permitido = _boolResumen(a['permitido'], defaultValue: true);
    if (!permitido) {
      out.add({
        'articulo': nombre,
        'motivo': 'No permitido',
        'anomalia': (a['anomalia_permitido'] ?? '').toString().trim(),
        'agente': (a['agente_causal_permitido'] ?? '').toString().trim(),
        'accion': (a['accion_permitido'] ?? '').toString().trim(),
      });
    }
    if (permitido && !_boolResumen(a['desinfectado'], defaultValue: true)) {
      out.add({
        'articulo': nombre,
        'motivo': 'Sin desinfección',
        'anomalia': (a['anomalia_desinfeccion'] ?? '').toString().trim(),
        'agente': (a['agente_causal_desinfeccion'] ?? '').toString().trim(),
        'accion': (a['accion_desinfeccion'] ?? '').toString().trim(),
      });
    }
  }
  return out;
}

List<String> _imagenesArticulosRecord(Map<String, dynamic> record) {
  final vistos = <String>{};
  final out = <String>[];
  void addPath(String? p) {
    if (p == null || p.isEmpty || !vistos.add(p)) return;
    if (File(p).existsSync()) out.add(p);
  }

  for (final item in (record['imagenes'] as List?) ?? []) {
    addPath(_rutaImagen(item));
  }
  final reg = Map<String, dynamic>.from((record['registro'] as Map?) ?? {});
  for (final a in _articulosRegistroResumen(reg)) {
    for (final img in (a['imagenes'] as List?) ?? []) {
      addPath(_rutaImagen(img));
    }
  }
  return out;
}

bool _vehiculoIngresaFlag(dynamic ingresa) {
  if (ingresa == false || ingresa == 0 || ingresa == '0') return false;
  if (ingresa == true || ingresa == 1 || ingresa == '1') return true;
  return true;
}

String _lineaVehiculoResumen(Map<String, dynamic> v) {
  final placa = (v['placa'] ?? '').toString().trim().toUpperCase();
  if (placa.isEmpty) return '';
  final ingresa = _vehiculoIngresaFlag(v['ingresa']);
  return '$placa / ${_etiquetaPermisoIngresoGranja(ingresa)}';
}

List<String> _vehiculosSalidaResumen(Map<String, dynamic> registro) {
  final raw = registro['vehiculos'];
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        (item['placa'] ?? '').toString().trim().toUpperCase()
      else
        item.toString().trim().toUpperCase(),
  ].where((e) => e.isNotEmpty).toList();
}

List<String> _vehiculosIngresoResumen(Map<String, dynamic> registro) {
  final raw = registro['vehiculos'];
  if (raw is! List || raw.isEmpty) return const [];
  return [
    for (final item in raw)
      if (item is Map) _lineaVehiculoResumen(Map<String, dynamic>.from(item))
  ].where((e) => e.isNotEmpty).toList();
}

/// Nombre (y RUC si hay) del proveedor en un registro de ingreso.
String proveedorIngresoResumen(Map<String, dynamic> registro) {
  final nombre = registro['proveedor']?.toString().trim() ?? '';
  final ruc = registro['proveedor_ruc']?.toString().trim() ?? '';
  if (nombre.isNotEmpty && ruc.isNotEmpty) return '$nombre · RUC $ruc';
  if (nombre.isNotEmpty) return nombre;
  if (ruc.isNotEmpty) return 'RUC $ruc';
  return '—';
}

int conteoPersonasIngreso(Map<String, dynamic> registro) {
  final raw = registro['numpersonas'];
  if (raw != null) {
    final n = int.tryParse(raw.toString().trim());
    if (n != null) return n;
  }
  return listaDnis(registro['dnis']).length;
}

int conteoVehiculosIngreso(Map<String, dynamic> registro) =>
    _vehiculosIngresoResumen(registro).length;

/// Línea compacta para tarjetas de reportes (control de personal).
String lineaIngresoReporte(Map<String, dynamic> registro) {
  final nombre = registro['proveedor']?.toString().trim() ?? '';
  final prov =
      nombre.isNotEmpty ? nombre : proveedorIngresoResumen(registro);
  final pers = conteoPersonasIngreso(registro);
  final veh = conteoVehiculosIngreso(registro);
  return '$prov · ${lineaConteoPersonal(personas: pers, vehiculos: veh)}';
}

String _personasIngresoResumen(List<DniEntrada> dnis) {
  if (dnis.isEmpty) return '—';
  return dnis.map((d) => d.etiqueta).join('\n');
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
    case 'garita':
      return AppStrings.menuInstalaciones;
    case 'cerco':
      return AppStrings.menuCerco;
    case 'fomites':
      return AppStrings.menuFomites;
    case 'ingreso':
      return AppStrings.menuIngreso;
    case 'salida':
      return AppStrings.menuSalida;
    case 'articulos':
      return AppStrings.menuArticulos;
  }
  return reporte;
}

IconData iconoReporte(String reporte) {
  switch (reporte) {
    case 'garita':
      return kIconoAnomalias;
    case 'cerco':
      return Icons.bolt_rounded;
    case 'fomites':
      // Huella de animal: fómites es el arrastre de suciedad por animales,
      // patas y vehículos.
      return Icons.pets;
    case 'ingreso':
      return Icons.badge_outlined;
    case 'salida':
      return Icons.logout_rounded;
    case 'articulos':
      return Icons.checklist_rtl_rounded;
  }
  return Icons.assignment_outlined;
}

/// DNIs declarados en un registro de Control de ingreso, con el nombre
/// consultado cuando lo hay.
/// Acepta los formatos que existen en la app: pares `{dni, nombre}` (lo que
/// guarda el formulario con el escáner), lista de números (registros anteriores)
/// y texto separado por comas (reportes que vienen del backend).
List<DniEntrada> listaDnis(dynamic raw) => parseDnisEntradas(raw);

/// Contenido reutilizable del resumen de un registro de bioseguridad.
class RegisterSummaryContent extends StatelessWidget {
  const RegisterSummaryContent({
    super.key,
    required this.record,
    this.title = 'Resumen del registro',
    this.compact = false,
  });

  final Map<String, dynamic> record;
  final String title;

  /// Resumen corto (ficha + tablas) antes de guardar ingreso/salida.
  final bool compact;

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

    if (compact && reporte == 'articulos') {
      final imgs = _imagenesArticulosRecord(record);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fichaArticulosResumen(context),
          const SizedBox(height: 14),
          ..._bloquesArticulosResumen(context),
          if (imgs.isNotEmpty) ...[
            const SizedBox(height: 14),
            _bloqueImagenesResumen(context, imgs),
          ],
        ],
      );
    }

    if (reporte == 'articulos') {
      final imgs = _imagenesArticulosRecord(record);
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
          _row(context, 'Turno', record['turno']?.toString() ?? '—'),
          _row(
            context,
            'Registrado por',
            record['nombre_usuario']?.toString() ?? '—',
          ),
          const SizedBox(height: 8),
          ..._bloquesArticulosResumen(context),
          const SizedBox(height: 12),
          _bloqueImagenesResumen(context, imgs),
        ],
      );
    }

    if (compact && (reporte == 'ingreso' || reporte == 'salida')) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fichaIngresoSalidaResumen(context, reporte, granjaLabel),
          const SizedBox(height: 14),
          ..._tablasPersonasVehiculosCompactas(context, reporte),
          if (imagenes.isNotEmpty) ...[
            const SizedBox(height: 14),
            _bloqueImagenesResumen(context, imagenes),
          ],
        ],
      );
    }

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
        _row(context, 'Turno', record['turno']?.toString() ?? '—'),
        _row(context, 'Granja', granjaLabel),
        _row(
          context,
          'Campaña',
          GranjaCampaniaPicker.padCampania(
            record['campania']?.toString() ?? '',
          ),
        ),
        _row(
          context,
          'Registrado por',
          record['nombre_usuario']?.toString() ?? '—',
        ),
        const SizedBox(height: 8),
        ..._detalle(context, reporte),
        const SizedBox(height: 12),
        _bloqueImagenesResumen(context, imagenes),
      ],
    );
  }

  Widget _bloqueImagenesResumen(BuildContext context, List<String> imagenes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Imágenes',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: compact ? 13 : null,
            color: context.textThemeSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (imagenes.isEmpty)
          Text(
            'Sin imágenes adjuntas',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontSize: 12,
              color: context.textThemeMuted,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: imagenes.map((path) {
              final side = compact ? 72.0 : 90.0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(AppColors.radiusSm),
                child: Image.file(
                  File(path),
                  width: side,
                  height: side,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: side,
                    height: side,
                    color: context.surfaceCard,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: context.textThemeMuted,
                      size: 22,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _fichaIngresoSalidaResumen(
    BuildContext context,
    String reporte,
    String granjaLabel,
  ) {
    final registro = Map<String, dynamic>.from(
      (record['registro'] as Map?) ?? const {},
    );
    final fecha = _fmtFecha(record['fecha']?.toString() ?? '');
    final turno = record['turno']?.toString() ?? '—';
    final camp = GranjaCampaniaPicker.padCampania(
      record['campania']?.toString() ?? '',
    );
    final campTxt = camp.isEmpty ? '—' : camp;
    final hora = _fmtHora(registro['hora']?.toString() ?? '');
    final mov = (registro['movimiento'] ?? 'salida').toString().toLowerCase();
    final esRegreso = mov == 'regreso' || mov == 'reingreso';
    final tituloFicha = reporte == 'ingreso'
        ? 'Ficha de ingreso'
        : (esRegreso ? 'Ficha de regreso' : 'Ficha de salida');
    final horaLabel = reporte == 'ingreso'
        ? 'Hora de ingreso'
        : (esRegreso ? 'Hora de regreso' : 'Hora de salida');
    final proceso = registro['motivo']?.toString().trim() ?? '';
    final galpon = registro['galpon']?.toString().trim() ?? '';
    final obs = registro['observacion']?.toString().trim() ?? '';

    final turnoTxt = turno == 'Dia' ? 'Día' : turno;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tituloFicha,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _resumenEtiquetaValor(context, 'Fecha', fecha),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _resumenEtiquetaValor(context, 'Turno', turnoTxt),
            ),
          ],
        ),
        _resumenEtiquetaValor(context, horaLabel, hora),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _resumenEtiquetaValor(context, 'Granja', granjaLabel),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _resumenEtiquetaValor(context, 'Campaña', campTxt),
            ),
          ],
        ),
        _resumenEtiquetaValor(
          context,
          'Proveedor',
          proveedorIngresoResumen(registro),
          maxLines: 3,
        ),
        if (proceso.isNotEmpty)
          _resumenEtiquetaValor(context, 'Proceso', proceso, maxLines: 3),
        if (reporte == 'ingreso' && galpon.isNotEmpty)
          _resumenEtiquetaValor(context, 'Galpones', galpon, maxLines: 3),
        if (reporte == 'salida' && !esRegreso)
          _resumenEtiquetaValor(
            context,
            'Tipo de salida',
            IngresoPresenciaService.etiquetaTipoSalida(
              registro['tipo_salida']?.toString(),
            ),
          ),
        if (obs.isNotEmpty)
          _resumenEtiquetaValor(context, 'Observación', obs, maxLines: 4),
      ],
    );
  }

  List<Widget> _tablasPersonasVehiculosCompactas(
    BuildContext context,
    String reporte,
  ) {
    final registro = Map<String, dynamic>.from(
      (record['registro'] as Map?) ?? const {},
    );
    final dnis = listaDnis(registro['dnis']);
    final widgets = <Widget>[
      _tablaPersonasResumen(context, dnis, reporte),
    ];

    if (reporte == 'ingreso') {
      final vehRaw = registro['vehiculos'];
      if (vehRaw is List && vehRaw.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_tablaVehiculosIngresoResumen(context, vehRaw));
      }
      final pruebas = _alcoholemiaPruebasResumen(registro);
      if (pruebas.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_tablaAlcoholemiaResumen(context, pruebas));
      }
    } else {
      final placas = _vehiculosSalidaResumen(registro);
      if (placas.isNotEmpty) {
        widgets.add(const SizedBox(height: 10));
        widgets.add(_tablaVehiculosSalidaResumen(context, placas, reporte));
      }
    }
    return widgets;
  }

  Widget _tablaPersonasResumen(
    BuildContext context,
    List<DniEntrada> dnis,
    String reporte,
  ) {
    final mov = reporte == 'ingreso' ? 'ingresan' : 'salen';
    return BioTable(
      caption: dnis.isEmpty ? 'Personas' : 'Personas ($mov · ${dnis.length})',
      rowHeight: 40,
      columns: const [
        BioColumn('DNI', width: 96, align: TextAlign.left),
        BioColumn('Nombre', width: 140, align: TextAlign.left, flex: 2),
      ],
      rowCount: dnis.isEmpty ? 1 : dnis.length,
      rowBuilder: (context, index) {
        if (dnis.isEmpty) {
          return const [
            BioText('—', align: TextAlign.left, fontSize: 11),
            BioText('—', align: TextAlign.left, fontSize: 11),
          ];
        }
        final d = dnis[index];
        return [
          BioText(d.dni, align: TextAlign.left, fontSize: 11, bold: true),
          BioText(
            d.nombre.trim().isEmpty ? '—' : d.nombre.trim(),
            align: TextAlign.left,
            fontSize: 11,
          ),
        ];
      },
    );
  }

  Widget _fichaArticulosResumen(BuildContext context) {
    final registro = Map<String, dynamic>.from(
      (record['registro'] as Map?) ?? const {},
    );
    final fecha = _fmtFecha(record['fecha']?.toString() ?? '');
    final turno = record['turno']?.toString() ?? '—';
    final turnoTxt = turno == 'Dia' ? 'Día' : turno;
    final dni = registro['dni']?.toString().trim() ?? '';
    final nombre = registro['nombre']?.toString().trim() ?? '';
    final persona = dni.isEmpty
        ? (nombre.isEmpty ? '—' : nombre)
        : (nombre.isEmpty ? dni : '$dni · $nombre');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Control de artículos',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _resumenEtiquetaValor(context, 'Fecha', fecha)),
            const SizedBox(width: 12),
            Expanded(child: _resumenEtiquetaValor(context, 'Turno', turnoTxt)),
          ],
        ),
        _resumenEtiquetaValor(context, 'Persona', persona, maxLines: 3),
      ],
    );
  }

  List<Widget> _bloquesArticulosResumen(BuildContext context) {
    final registro = Map<String, dynamic>.from(
      (record['registro'] as Map?) ?? const {},
    );
    final items = _articulosRegistroResumen(registro);
    final anomalias = _anomaliasArticulosResumen(items);
    return [
      _tablaArticulosControlResumen(context, items),
      if (anomalias.isNotEmpty) ...[
        const SizedBox(height: 10),
        _tablaAnomaliasArticulosResumen(context, anomalias),
      ],
    ];
  }

  Widget _tablaArticulosControlResumen(
    BuildContext context,
    List<Map<String, dynamic>> items,
  ) {
    return BioTable(
      caption: items.isEmpty ? 'Artículos' : 'Artículos (${items.length})',
      rowHeight: 40,
      columns: const [
        BioColumn('Artículo', width: 100, align: TextAlign.left, flex: 2),
        BioColumn('Perm.', width: 44, align: TextAlign.center),
        BioColumn('Desinf.', width: 52, align: TextAlign.center),
        BioColumn('Producto', width: 88, align: TextAlign.left, flex: 1),
      ],
      rowCount: items.isEmpty ? 1 : items.length,
      rowBuilder: (context, index) {
        if (items.isEmpty) {
          return const [
            BioText('—', align: TextAlign.left, fontSize: 11),
            BioText('—', align: TextAlign.center, fontSize: 11),
            BioText('—', align: TextAlign.center, fontSize: 11),
            BioText('—', align: TextAlign.left, fontSize: 11),
          ];
        }
        final a = items[index];
        final nombre = (a['descripcion'] ?? '').toString().trim();
        final permitido = _boolResumen(a['permitido'], defaultValue: true);
        final desinfectado = _boolResumen(a['desinfectado'], defaultValue: true);
        final producto = (a['desinfectante'] ?? '').toString().trim();
        return [
          BioText(
            nombre.isEmpty ? '—' : nombre,
            align: TextAlign.left,
            fontSize: 11,
            bold: true,
          ),
          BioText(
            permitido ? 'Sí' : 'No',
            align: TextAlign.center,
            fontSize: 11,
            color: permitido ? null : AppColors.errorDark,
            bold: !permitido,
          ),
          BioText(
            !permitido
                ? '—'
                : (desinfectado ? 'Sí' : 'No'),
            align: TextAlign.center,
            fontSize: 11,
            color: permitido && !desinfectado ? AppColors.errorDark : null,
            bold: permitido && !desinfectado,
          ),
          BioText(
            permitido && desinfectado && producto.isNotEmpty ? producto : '—',
            align: TextAlign.left,
            fontSize: 11,
          ),
        ];
      },
    );
  }

  Widget _tablaAnomaliasArticulosResumen(
    BuildContext context,
    List<Map<String, dynamic>> filas,
  ) {
    return BioTable(
      caption: 'Anomalías AGC (${filas.length})',
      rowHeight: 44,
      columns: const [
        BioColumn('Artículo', width: 80, align: TextAlign.left),
        BioColumn('Motivo', width: 68, align: TextAlign.left),
        BioColumn('Anomalía', width: 90, align: TextAlign.left, flex: 2),
        BioColumn('Agente', width: 80, align: TextAlign.left, flex: 1),
        BioColumn('Acción', width: 80, align: TextAlign.left, flex: 1),
      ],
      rowCount: filas.length,
      rowBuilder: (context, index) {
        final f = filas[index];
        final art = (f['articulo'] ?? '').toString();
        final motivo = (f['motivo'] ?? '').toString();
        final anomalia = (f['anomalia'] ?? '').toString();
        final agente = (f['agente'] ?? '').toString();
        final accion = (f['accion'] ?? '').toString();
        return [
          BioText(art, align: TextAlign.left, fontSize: 11, bold: true),
          BioText(motivo, align: TextAlign.left, fontSize: 11),
          BioText(
            anomalia.isEmpty ? '—' : anomalia,
            align: TextAlign.left,
            fontSize: 11,
          ),
          BioText(
            agente.isEmpty ? '—' : agente,
            align: TextAlign.left,
            fontSize: 11,
          ),
          BioText(
            accion.isEmpty ? '—' : accion,
            align: TextAlign.left,
            fontSize: 11,
          ),
        ];
      },
    );
  }

  Widget _tablaAlcoholemiaResumen(
    BuildContext context,
    List<Map<String, dynamic>> filas,
  ) {
    final umbral = context.read<CatalogService>().alcoholemiaMeta.umbralGl;
    return BioTable(
      caption: 'Alcoholemia (${filas.length})',
      rowHeight: 40,
      columns: const [
        BioColumn('DNI', width: 88, align: TextAlign.left),
        BioColumn('Nombre', width: 100, align: TextAlign.left, flex: 2),
        BioColumn('g/L', width: 44, align: TextAlign.right),
        BioColumn('Resultado', width: 68, align: TextAlign.center),
      ],
      rowCount: filas.length,
      rowBuilder: (context, index) {
        final p = filas[index];
        final dni = (p['dni'] ?? '').toString().trim();
        final nombre = (p['nombre'] ?? '').toString().trim();
        final gradoTxt = (p['grado_g_l'] ?? '').toString().trim();
        final grado = _parseGradoGlResumen(p['grado_g_l']);
        final estado = _estadoAlcoholemiaResumen(grado, umbral);
        final supera = estado == 'Supera';
        return [
          BioText(dni.isEmpty ? '—' : dni, align: TextAlign.left, fontSize: 11, bold: true),
          BioText(
            nombre.isEmpty ? '—' : nombre,
            align: TextAlign.left,
            fontSize: 11,
          ),
          BioText(
            gradoTxt.isEmpty ? '—' : gradoTxt,
            align: TextAlign.right,
            fontSize: 11,
            bold: true,
          ),
          BioText(
            estado,
            align: TextAlign.center,
            fontSize: 11,
            bold: supera,
            color: supera ? AppColors.errorDark : null,
          ),
        ];
      },
    );
  }

  Widget _tablaVehiculosIngresoResumen(BuildContext context, List<dynamic> raw) {
    final filas = <Map<String, dynamic>>[
      for (final item in raw)
        if (item is Map) Map<String, dynamic>.from(item),
    ];
    return BioTable(
      caption: 'Vehículos (${filas.length})',
      rowHeight: 38,
      columns: const [
        BioColumn('Placa', width: 100, align: TextAlign.left),
        BioColumn('Permiso', width: 120, align: TextAlign.left, flex: 1),
      ],
      rowCount: filas.isEmpty ? 1 : filas.length,
      rowBuilder: (context, index) {
        if (filas.isEmpty) {
          return const [
            BioText('—', align: TextAlign.left, fontSize: 11),
            BioText('—', align: TextAlign.left, fontSize: 11),
          ];
        }
        final v = filas[index];
        final placa = (v['placa'] ?? '').toString().trim().toUpperCase();
        final ingresa = _vehiculoIngresaFlag(v['ingresa']);
        return [
          BioText(placa.isEmpty ? '—' : placa, align: TextAlign.left, fontSize: 11, bold: true),
          BioText(
            _etiquetaPermisoIngresoGranja(ingresa),
            align: TextAlign.left,
            fontSize: 11,
          ),
        ];
      },
    );
  }

  Widget _tablaVehiculosSalidaResumen(
    BuildContext context,
    List<String> placas,
    String reporte,
  ) {
    final mov = reporte == 'salida' ? 'salen' : 'regresan';
    return BioTable(
      caption: 'Vehículos ($mov · ${placas.length})',
      rowHeight: 38,
      columns: const [
        BioColumn('Placa', width: 120, align: TextAlign.left, flex: 1),
      ],
      rowCount: placas.length,
      rowBuilder: (context, index) {
        return [
          BioText(placas[index], align: TextAlign.left, fontSize: 11, bold: true),
        ];
      },
    );
  }

  List<Widget> _detalle(BuildContext context, String reporte) {
    final registro = Map<String, dynamic>.from(
      (record['registro'] as Map?) ?? const {},
    );

    if (reporte == 'garita') {
      final instalacion = registro['instalacion']?.toString().trim() ?? '';
      final bioseguridad = registro['bioseguridad']?.toString().trim() ?? '';
      return [
        // Registros anteriores al cambio no traen el campo: eran garita.
        _row(context, 'Instalación', instalacion.isEmpty ? 'Garita' : instalacion),
        _row(
          context,
          'Tipo de bioseguridad',
          bioseguridad.isEmpty ? 'Bioseguridad fisica' : bioseguridad,
        ),
        if (instalacion.isEmpty || instalacion == 'Garita')
          _row(context, 'Filtro', 'N° ${registro['numfiltro'] ?? '—'}'),
        _row(context, 'Hora', _fmtHora(registro['hora']?.toString() ?? '')),
        _textFieldRow(context, 'Detalle de anomalía', registro['descripcion']?.toString()),
        _textFieldRow(
          context,
          'Agente causal',
          registro['agentecausal']?.toString(),
        ),
      ];
    }

    if (reporte == 'ingreso') {
      final dnis = listaDnis(registro['dnis']);
      final vehiculos = _vehiculosIngresoResumen(registro);
      final pruebasAlc = _alcoholemiaPruebasResumen(registro);
      final proceso = registro['motivo']?.toString().trim() ?? '';
      final galpon = registro['galpon']?.toString().trim() ?? '';
      return [
        _row(context, 'Hora de ingreso', _fmtHora(registro['hora']?.toString() ?? '')),
        _row(context, 'Galpón', galpon.isEmpty ? '—' : galpon),
        _row(context, 'Proveedor', proveedorIngresoResumen(registro)),
        _row(context, 'Proceso', proceso.isEmpty ? '—' : proceso),
        _row(context, 'Cantidad de personas', '${registro['numpersonas'] ?? 0}'),
        _textFieldRow(
          context,
          dnis.isEmpty
              ? 'Personas que ingresan'
              : 'Personas que ingresan (${dnis.length})',
          _personasIngresoResumen(dnis),
        ),
        _textFieldRow(
          context,
          vehiculos.isEmpty
              ? 'Vehículos que ingresan'
              : 'Vehículos que ingresan (${vehiculos.length})',
          vehiculos.isEmpty ? '—' : vehiculos.join('\n'),
        ),
        if (pruebasAlc.isNotEmpty) ...[
          const SizedBox(height: 12),
          _tablaAlcoholemiaResumen(context, pruebasAlc),
        ],
        _textFieldRow(context, 'Motivo de visita/ Obs.', registro['observacion']?.toString()),
      ];
    }

    if (reporte == 'salida') {
      final dnis = listaDnis(registro['dnis']);
      final vehiculos = _vehiculosSalidaResumen(registro);
      final proceso = registro['motivo']?.toString().trim() ?? '';
      final mov = (registro['movimiento'] ?? 'salida').toString().toLowerCase();
      final esRegreso = mov == 'regreso' || mov == 'reingreso';
      final horaLabel = esRegreso ? 'Hora de regreso' : 'Hora de salida';
      final persLabel = esRegreso
          ? (dnis.isEmpty
              ? 'Personas que regresan'
              : 'Personas que regresan (${dnis.length})')
          : (dnis.isEmpty
              ? 'Personas que salen'
              : 'Personas que salen (${dnis.length})');
      final vehLabel = esRegreso
          ? (vehiculos.isEmpty
              ? 'Vehículos que regresan'
              : 'Vehículos que regresan (${vehiculos.length})')
          : (vehiculos.isEmpty
              ? 'Vehículos que salen'
              : 'Vehículos que salen (${vehiculos.length})');
      return [
        _row(
          context,
          horaLabel,
          _fmtHora(registro['hora']?.toString() ?? ''),
        ),
        if (!esRegreso)
          _row(
            context,
            'Tipo de salida',
            IngresoPresenciaService.etiquetaTipoSalida(
              registro['tipo_salida']?.toString(),
            ),
          ),
        if (esRegreso)
          _row(context, 'Acción', 'Regreso'),
        _row(context, 'Proveedor', proveedorIngresoResumen(registro)),
        _row(context, 'Proceso', proceso.isEmpty ? '—' : proceso),
        _textFieldRow(
          context,
          persLabel,
          _personasIngresoResumen(dnis),
        ),
        _textFieldRow(
          context,
          vehLabel,
          vehiculos.isEmpty ? '—' : vehiculos.join('\n'),
        ),
      ];
    }

    if (reporte == 'cerco') {
      final responsable = registro['evaluador']?.toString().trim() ?? '';
      final bloquesRaw = registro['bloques'];
      final tablas = <Widget>[];
      if (bloquesRaw is List && bloquesRaw.isNotEmpty) {
        for (final b in bloquesRaw) {
          if (b is! Map) continue;
          final titulo = b['titulo']?.toString().trim() ?? '';
          final filasB = (b['filas'] as List?) ?? [];
          if (filasB.isEmpty) continue;
          if (tablas.isNotEmpty) tablas.add(const SizedBox(height: 12));
          tablas.add(
            _tablaCercoResumen(
              context,
              caption: titulo.isEmpty ? 'Inspección' : titulo,
              filas: filasB,
            ),
          );
        }
      }
      if (tablas.isEmpty) {
        final filas = (registro['filas'] as List?) ?? [];
        if (filas.isNotEmpty) {
          tablas.add(
            _tablaCercoResumen(
              context,
              caption: 'Verificación del tablero',
              filas: filas,
            ),
          );
        }
      }
      return [
        if (responsable.isNotEmpty)
          _row(context, 'Responsable de inspección', responsable),
        _row(context, 'Hora inicio', _fmtHora(registro['horainicio']?.toString() ?? '')),
        _row(context, 'Hora fin', _fmtHora(registro['horafinal']?.toString() ?? '')),
        if (tablas.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...tablas,
        ],
        if ((registro['observacion']?.toString() ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _textFieldRow(
            context,
            'Observaciones generales',
            registro['observacion']?.toString(),
          ),
        ],
      ];
    }

    if (reporte == 'fomites') {
      final filas = (registro['filas'] as List?) ?? [];
      return [
        _row(context, 'Referencia', registro['referencia']?.toString() ?? '—'),
        _row(context, 'Proceso', registro['proceso']?.toString() ?? '—'),
        const SizedBox(height: 12),
        BioTable(
          caption: 'Fómites avistados',
          rowHeight: 40,
          columns: const [
            BioColumn('Fómite', width: 110, align: TextAlign.left),
            BioColumn('Tipo', width: 110),
            BioColumn('Cantidad', width: 72),
            BioColumn('Hora', width: 68),
            BioColumn('¿D. del cerco?', width: 104),
          ],
          rowCount: filas.length,
          rowBuilder: (context, index) {
            final fila = Map<String, dynamic>.from(
              filas[index] as Map? ?? const {},
            );
            final dentro = _siNo(fila['dentrocerco']);
            return [
              BioText(
                fila['depredador']?.toString() ?? '—',
                align: TextAlign.left,
                fontSize: 11,
                bold: true,
              ),
              BioText(fila['tipo']?.toString() ?? '—', fontSize: 11),
              BioText('${fila['cantidad'] ?? 0}', fontSize: 11),
              BioText(_fmtHora(fila['hora']?.toString() ?? ''), fontSize: 11),
              BioText(
                dentro,
                fontSize: 11,
                bold: true,
                color: dentro == 'SI'
                    ? AppColors.errorDark
                    : AppColors.success,
              ),
            ];
          },
        ),
        if ((registro['observacion']?.toString() ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _textFieldRow(context, 'Observación', registro['observacion']?.toString()),
        ],
      ];
    }

    return const [];
  }

  static String _siNo(dynamic v) {
    final s = v?.toString().trim().toLowerCase() ?? '';
    return (s == 'si' || s == 'sí' || s == '1' || s == 'true') ? 'SI' : 'NO';
  }

  /// Misma disposición que el formulario de cerco: componente + STD, L1 y L2.
  Widget _tablaCercoResumen(
    BuildContext context, {
    required String caption,
    required List<dynamic> filas,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
      ),
      child: BioTable(
        caption: caption,
        rowHeight: 44,
        columns: const [
          BioColumn('Componente', width: 118, align: TextAlign.left, flex: 1),
          BioColumn('L1\nEstado', width: 100, align: TextAlign.left),
          BioColumn('L2\nEstado', width: 100, align: TextAlign.left),
        ],
        rowCount: filas.length,
        rowBuilder: (context, index) {
          final fila = Map<String, dynamic>.from(
            filas[index] as Map? ?? const {},
          );
          final l1 = Map<String, dynamic>.from(
            (fila['linea1'] as Map?) ?? const {},
          );
          final l2 = Map<String, dynamic>.from(
            (fila['linea2'] as Map?) ?? const {},
          );
          return [
            _celdaComponenteCerco(context, fila),
            _celdaFalloObs(
              context,
              l1['fallo']?.toString() ?? 'No',
              l1['obs']?.toString() ?? '',
            ),
            _celdaFalloObs(
              context,
              l2['fallo']?.toString() ?? 'No',
              l2['obs']?.toString() ?? '',
            ),
          ];
        },
      ),
    );
  }

  Widget _celdaComponenteCerco(
    BuildContext context,
    Map<String, dynamic> fila,
  ) {
    final std = fila['std']?.toString().trim() ?? '';
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BioText(
          fila['componente']?.toString() ?? '—',
          align: TextAlign.left,
          fontSize: 12.5,
          bold: true,
        ),
        if (std.isNotEmpty) ...[
          const SizedBox(height: 2),
          BioText(
            'STD: $std',
            align: TextAlign.left,
            fontSize: 11,
            bold: true,
            color: context.textThemeSecondary,
          ),
        ],
      ],
    );
  }

  /// Celda «¿Falló?» + observación juntas, igual que en el formulario.
  Widget _celdaFalloObs(BuildContext context, String fallo, String obs) {
    final si = _siNo(fallo) == 'SI';
    final detalle = obs.trim();
    return Row(
      children: [
        Text(
          si ? 'SI' : 'NO',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: si ? AppColors.errorDark : AppColors.success,
          ),
        ),
        if (detalle.isNotEmpty) ...[
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              detalle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.textThemePrimary,
              ),
            ),
          ),
        ],
      ],
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
  /// [records]: varios registros que se guardan juntos (p. ej. dos cuadrillas
  /// planificadas con distinto proveedor). Se muestran apilados, uno por
  /// proveedor; sin él se muestra solo [record].
  static Future<bool> show(
    BuildContext context, {
    required Map<String, dynamic> record,
    List<Map<String, dynamic>>? records,
    Future<void> Function()? onConfirm,
    String? titulo,
  }) async {
    final lista = (records != null && records.isNotEmpty) ? records : [record];
    final varios = lista.length > 1;
    final provKeys = lista
        .where((r) => r['reporte'] == 'ingreso')
        .map((r) {
          final g = Map<String, dynamic>.from((r['registro'] as Map?) ?? {});
          final ruc = (g['proveedor_ruc'] ?? '').toString().trim();
          return ruc.isNotEmpty
              ? ruc
              : (g['proveedor'] ?? '').toString().trim().toUpperCase();
        })
        .toSet();
    final mismoProveedor =
        varios && provKeys.length == 1 && provKeys.first.isNotEmpty;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) {
        final tipo = record['reporte']?.toString() ?? '';
        final hojaCompacta =
            tipo == 'ingreso' || tipo == 'salida' || tipo == 'articulos';
        return DraggableScrollableSheet(
        initialChildSize: hojaCompacta ? 0.94 : 1.0,
        minChildSize: hojaCompacta ? 0.55 : 0.5,
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
                              titulo ?? 'Resumen del registro',
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
                  child: SafeArea(
                    top: false,
                    bottom: onConfirm == null,
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          for (var i = 0; i < lista.length; i++) ...[
                            if (i > 0) const SizedBox(height: 14),
                            if (varios)
                              _EncabezadoProveedor(
                                indice: lista
                                    .take(i + 1)
                                    .where((r) => r['reporte'] == 'ingreso')
                                    .length,
                                record: lista[i],
                                mismoProveedor: mismoProveedor,
                              ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: sheetContext.surfaceCard,
                                borderRadius: varios
                                    ? const BorderRadius.vertical(
                                        bottom: Radius.circular(12),
                                      )
                                    : BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.2),
                                ),
                              ),
                              child: RegisterSummaryContent(
                                record: lista[i],
                                title: '',
                                compact: hojaCompacta,
                              ),
                            ),
                          ],
                        ],
                      ),
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
      );
      },
    );
    return result ?? false;
  }
}

/// Cabecera «Proveedor 1 · Razón social» de cada registro cuando el resumen
/// muestra varios.
class _EncabezadoProveedor extends StatelessWidget {
  const _EncabezadoProveedor({
    required this.indice,
    required this.record,
    this.mismoProveedor = false,
  });

  final int indice;
  final Map<String, dynamic> record;
  final bool mismoProveedor;

  @override
  Widget build(BuildContext context) {
    final reg = Map<String, dynamic>.from((record['registro'] as Map?) ?? {});
    final nombre = (reg['proveedor'] ?? '').toString().trim();
    final ruc = (reg['proveedor_ruc'] ?? '').toString().trim();
    final detalle = nombre.isNotEmpty ? nombre : (ruc.isNotEmpty ? 'RUC $ruc' : '');
    final etiqueta = (reg['movimiento'] ?? '').toString() == 'regreso'
        ? 'Regreso'
        : (mismoProveedor
            ? 'Visita $indice'
            : 'Proveedor $indice');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: etiqueta,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark,
              ),
            ),
            if (detalle.isNotEmpty)
              TextSpan(
                text: ' · $detalle',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.textThemePrimary,
                ),
              ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14.5),
      ),
    );
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
