import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

String _fmtHora(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '—';
  final partes = s.split(':');
  if (partes.length >= 2) return '${partes[0]}:${partes[1]}';
  return s;
}

String _etiquetaPermisoIngresoGranja(bool ingresa) =>
    ingresa ? 'Ingresa a granja' : 'No ingresa a granja';

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
                  child: SafeArea(
                    top: false,
                    bottom: onConfirm == null,
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
                        child: RegisterSummaryContent(
                          record: record,
                          title: '',
                        ),
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
