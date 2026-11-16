/// Secciones 5 a 8 del «Formato vacuna al agua».
/// Van en su propio archivo porque son cuatro bloques con estado propio y la
/// pantalla de Vacunación ya carga las secciones 1 a 4. Todas reciben los
/// galpones elegidos en «Información de vacuna» y, cuando el formato los pide
/// como columnas, dibujan una columna por galpón.
/// Lo que se carga acá viaja al backend como filas del detalle paramétrico
/// (`san_fact_vacunaagua_det`): cada sección se registra en el
/// [VacunacionDetalleController] que le pasa la pantalla y entrega sus filas en
/// el momento de guardar, así la pantalla no necesita conocer el estado interno
/// de cada bloque.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import '../utils/vacuna_payload.dart';
import 'bio_form_fields.dart';
import 'bio_table.dart';

/// Recolector del detalle de las secciones 5 a 8.
/// Cada sección se registra al montarse y se da de baja al desmontarse, así que
/// [filas] devuelve solo lo que está en pantalla y en el orden en que se
/// dibujan. Es la forma de que la pantalla arme el `detalle` del payload sin
/// tener que replicar el estado de las cuatro tablas.
class VacunacionDetalleController {
  final List<List<Map<String, dynamic>> Function()> _fuentes = [];

  /// Registra una sección. El teardown lo hace [quitar] desde su `dispose`.
  void registrar(List<Map<String, dynamic>> Function() fuente) {
    if (!_fuentes.contains(fuente)) {
      _fuentes.add(fuente);
    }
  }

  /// Da de baja una sección (al desmontarse).
  void quitar(List<Map<String, dynamic>> Function() fuente) {
    _fuentes.remove(fuente);
  }

  /// Filas de detalle de todas las secciones montadas.
  List<Map<String, dynamic>> filas() {
    return [
      for (final fuente in _fuentes) ...fuente(),
    ];
  }
}

/// Cantidad con hasta dos decimales (agua, litros, marcador).
class _Numero2Decimales extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty || RegExp(r'^\d{0,6}([.,]\d{0,2})?$').hasMatch(t)) {
      return newValue;
    }
    return oldValue;
  }
}

/// Temperatura: admite signo y hasta dos decimales (p. ej. -2.5, 8.25).
class _Temperatura2Decimales extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final t = newValue.text;
    if (t.isEmpty || RegExp(r'^-?\d{0,3}([.,]\d{0,2})?$').hasMatch(t)) {
      return newValue;
    }
    return oldValue;
  }
}

/// Lee un número escrito en una celda (acepta coma o punto) o `null` si está
/// vacía o no es un número.
double? _numeroDe(TextEditingController c) {
  final t = c.text.trim().replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Lee un entero escrito en una celda, o `null` si está vacía o no es número.
int? _enteroDe(TextEditingController c) {
  final t = c.text.trim();
  if (t.isEmpty) return null;
  return int.tryParse(t);
}

/// Formatea una cantidad sin decimales de más: 22 queda «22» y 22.5 «22.50».
String _cantidad(double? valor) {
  if (valor == null) return '—';
  final s = valor.toStringAsFixed(2);
  return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
}

/// Minutos desde la medianoche de una hora `HH:mm`, o `null` si no se puede
/// leer.
int? _minutosDe(String hora) {
  if (hora.length < 5) return null;
  final h = int.tryParse(hora.substring(0, 2));
  final m = int.tryParse(hora.substring(3, 5));
  if (h == null || m == null) return null;
  return h * 60 + m;
}

/// Duración en `hh:mm` (p. ej. 90 minutos «01:30»).
/// El tiempo de vacunación se lee así en el formato de campo: una fracción de
/// hora («1.5 h») obliga a traducir mentalmente cuántos minutos son.
String _hhmm(int minutos) {
  final h = minutos ~/ 60;
  final m = minutos % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// Deja un controlador de texto por cada galpón vigente y libera los de los
/// galpones que salieron de la selección.
/// Se comparte entre las secciones que guardan un valor por galpón (tiempo de
/// sedeó y solución vacunal).
Map<String, TextEditingController> _sincronizarPorGalpon(
  List<String> galpones,
  Map<String, TextEditingController> actuales,
) {
  for (final g in galpones) {
    actuales.putIfAbsent(g, () => TextEditingController());
  }
  for (final g in actuales.keys.toList()) {
    if (!galpones.contains(g)) {
      actuales.remove(g)!.dispose();
    }
  }
  return actuales;
}

/// Sección 5: tiempo de sedeó (horas), una columna por galpón elegido.
class TiempoSedeoSection extends StatefulWidget {
  const TiempoSedeoSection({
    super.key,
    required this.galpones,
    this.detalle,
  });

  final List<String> galpones;

  /// Recolector del detalle; la sección se registra sola al montarse.
  final VacunacionDetalleController? detalle;

  @override
  State<TiempoSedeoSection> createState() => _TiempoSedeoSectionState();
}

class _TiempoSedeoSectionState extends State<TiempoSedeoSection> {
  /// Duración de sedeó por galpón (`HH:mm`), elegida con el selector de duración.
  final Map<String, String> _horas = {};

  /// Fuente estable: los tear-off de un método devuelven instancias distintas
  /// en cada acceso, y el registro necesita la misma referencia para la baja.
  late final List<Map<String, dynamic>> Function() _fuente = _detalleFilas;

  @override
  void initState() {
    super.initState();
    _sincronizarHorasPorGalpon(widget.galpones, _horas);
    widget.detalle?.registrar(_fuente);
  }

  @override
  void didUpdateWidget(TiempoSedeoSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sincronizarHorasPorGalpon(widget.galpones, _horas);
    if (oldWidget.detalle != widget.detalle) {
      oldWidget.detalle?.quitar(_fuente);
      widget.detalle?.registrar(_fuente);
    }
  }

  @override
  void dispose() {
    widget.detalle?.quitar(_fuente);
    super.dispose();
  }

  void _sincronizarHorasPorGalpon(
    List<String> galpones,
    Map<String, String> actuales,
  ) {
    for (final g in galpones) {
      actuales.putIfAbsent(g, () => '');
    }
    for (final g in actuales.keys.toList()) {
      if (!galpones.contains(g)) {
        actuales.remove(g);
      }
    }
  }

  /// Convierte la duración `HH:mm` a horas decimales para el backend.
  double? _horasDecimales(String hhmm) {
    final minutos = _minutosDe(hhmm);
    if (minutos == null) return null;
    return minutos / 60.0;
  }

  /// Horas de sedeó cargadas, un renglón por galpón con valor.
  List<Map<String, dynamic>> _detalleFilas() {
    return [
      for (final g in widget.galpones)
        if (_horasDecimales(_horas[g] ?? '') != null)
          detalleFila(
            seccion: VacSeccion.sedeo,
            galpon: g,
            parametro: 'Horas',
            hora: _horas[g],
            valorTexto: _horas[g],
            valorNum: _horasDecimales(_horas[g]!),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.galpones.isEmpty) {
      return const BioInfoBanner(
        text: 'Seleccione los galpones en «Información de vacuna» para cargar el '
            'tiempo de sedeó.',
        icon: Icons.home_work_outlined,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
      ),
      child: BioTable(
        rowHeight: 48,
        expandir: true,
        columns: [
          for (final g in widget.galpones) BioColumn('Galpón $g', width: 80),
        ],
        rowCount: 1,
        rowBuilder: (context, _) => [
          for (final g in widget.galpones) _celdaHoraSedeo(g),
        ],
      ),
    );
  }

  Widget _celdaHoraSedeo(String galpon) {
    final valor = _horas[galpon] ?? '';
    return InkWell(
      onTap: () async {
        final h = await showBioDuracionDialog(context, valorActual: valor);
        if (h == null) return;
        setState(() => _horas[galpon] = h);
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          valor.isEmpty ? '--:--' : valor,
          style: TextStyle(
            fontSize: 12,
            fontWeight: valor.isEmpty ? FontWeight.w500 : FontWeight.w700,
            color: valor.isEmpty
                ? AppColors.textMuted
                : AppColors.horaText,
          ),
        ),
      ),
    );
  }
}

/// Sección 6: verificación del sistema de bebederos.
/// Dos bloques (llaves de la mesa de control y líneas del galpón) con un sí/no
/// por ítem, igual que el equipo de vacunación.
class VerificacionBebederosSection extends StatefulWidget {
  const VerificacionBebederosSection({super.key, this.detalle});

  /// Recolector del detalle; la sección se registra sola al montarse.
  final VacunacionDetalleController? detalle;

  @override
  State<VerificacionBebederosSection> createState() =>
      _VerificacionBebederosSectionState();
}

class _VerificacionBebederosSectionState
    extends State<VerificacionBebederosSection> {
  /// Encabezados de los dos bloques del formato. Son también el `grupo` de las
  /// filas del detalle, así que viven en un solo lugar.
  static const String _captionLlaves =
      'Operatividad de las llaves de manejo de agua en mesa de control';
  static const String _captionLineas =
      'Operatividad de las líneas de bebedero en galpón';

  static const List<String> _itemsLlaves = [
    'Fuga de agua en las llaves de manejo',
    'Medidor de agua inoperativo',
    'Medicador inoperativo',
    'Medidor de agua empañado',
    'Presencia de agua en líneas de bebederos',
    'Otro',
  ];

  static const List<String> _itemsLineas = [
    'Fuga de agua en unión de líneas de bebedero',
    'Malacates de las líneas de bebedero inoperativos',
    'Fuga de agua en los niples de las líneas de bebedero',
    'Inoperatividad de las llaves de control en las líneas de bebedero',
    'Inoperatividad de los reguladores de agua',
    'Otro',
  ];

  static const String _otro = 'Otro';

  /// `false` = NO (sin novedad, verde); `true` = SI (aplica la condición).
  final List<bool> _llaves = List.filled(_itemsLlaves.length, false);
  final List<bool> _lineas = List.filled(_itemsLineas.length, false);

  final TextEditingController _otroLlaves = TextEditingController();
  final TextEditingController _otroLineas = TextEditingController();

  late final List<Map<String, dynamic>> Function() _fuente = _detalleFilas;

  @override
  void initState() {
    super.initState();
    widget.detalle?.registrar(_fuente);
  }

  @override
  void didUpdateWidget(VerificacionBebederosSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detalle != widget.detalle) {
      oldWidget.detalle?.quitar(_fuente);
      widget.detalle?.registrar(_fuente);
    }
  }

  @override
  void dispose() {
    widget.detalle?.quitar(_fuente);
    _otroLlaves.dispose();
    _otroLineas.dispose();
    super.dispose();
  }

  /// Un renglón por ítem de los dos bloques, con su encabezado como `grupo`.
  List<Map<String, dynamic>> _detalleFilas() {
    final filas = <Map<String, dynamic>>[];
    void agregar(
      String grupo,
      List<String> items,
      List<bool> valores,
      TextEditingController otroCtrl,
    ) {
      for (var i = 0; i < items.length; i++) {
        final esOtro = items[i] == _otro;
        final si = valores[i];
        final detalleOtro = esOtro && si ? otroCtrl.text.trim() : '';
        filas.add(
          detalleFila(
            seccion: VacSeccion.bebederos,
            grupo: grupo,
            parametro: items[i],
            flag: si,
            valorTexto: detalleOtro.isEmpty ? null : detalleOtro,
          ),
        );
      }
    }

    agregar(_captionLlaves, _itemsLlaves, _llaves, _otroLlaves);
    agregar(_captionLineas, _itemsLineas, _lineas, _otroLineas);

    return filas;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabla(
          caption: _captionLlaves,
          items: _itemsLlaves,
          valores: _llaves,
          otroCtrl: _otroLlaves,
        ),
        const SizedBox(height: 14),
        _tabla(
          caption: _captionLineas,
          items: _itemsLineas,
          valores: _lineas,
          otroCtrl: _otroLineas,
        ),
      ],
    );
  }

  Widget _tabla({
    required String caption,
    required List<String> items,
    required List<bool> valores,
    required TextEditingController otroCtrl,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
      ),
      child: BioTable(
        caption: caption,
        rowHeight: 48,
        expandir: true,
        columns: const [
          BioColumn('Descripción', width: 176, align: TextAlign.left),
          BioColumn('SI / NO', width: 88),
          BioColumn('Detalle', width: 120, flex: 1),
        ],
        rowCount: items.length,
        rowBuilder: (context, i) {
          final esOtro = items[i] == _otro;
          final si = valores[i];
          return [
            BioText(items[i], align: TextAlign.left, bold: true, fontSize: 11.5),
            BioSwitchFallo(
              value: si,
              onChanged: (v) => setState(() {
                valores[i] = v;
                if (!v && esOtro) {
                  otroCtrl.clear();
                }
              }),
            ),
            esOtro
                ? BioTextField(
                    controller: otroCtrl,
                    enabled: si,
                    hint: si ? 'Describa' : '—',
                    maxLength: 80,
                  )
                : const BioText('—', fontSize: 11),
          ];
        },
      ),
    );
  }
}

/// Sección 7: preparación de solución vacunal.
/// Descripción contra galpones: lecturas del medidor, litros, marcador y
/// temperaturas a mano, y la cantidad de agua y el tiempo de vacunación
/// calculados a partir de lo cargado.
class PreparacionSolucionSection extends StatefulWidget {
  const PreparacionSolucionSection({
    super.key,
    required this.galpones,
    required this.edad,
    this.detalle,
  });

  final List<String> galpones;

  /// Edad de los pollos en días, calculada en «Información de vacuna».
  final int? edad;

  /// Recolector del detalle; la sección se registra sola al montarse.
  final VacunacionDetalleController? detalle;

  @override
  State<PreparacionSolucionSection> createState() =>
      _PreparacionSolucionSectionState();
}

class _PreparacionSolucionSectionState
    extends State<PreparacionSolucionSection> {
  /// Renglones de la tabla, en el orden del formato.
  static const List<String> _filas = [
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

  final Map<String, TextEditingController> _lecturaInicial = {};
  final Map<String, TextEditingController> _lecturaFinal = {};
  final Map<String, TextEditingController> _litros = {};
  final Map<String, TextEditingController> _marcador = {};
  final Map<String, TextEditingController> _tempMacho = {};
  final Map<String, TextEditingController> _tempHembra = {};
  final Map<String, String> _horaInicio = {};
  final Map<String, String> _horaFinal = {};

  late final List<Map<String, dynamic>> Function() _fuente = _detalleFilas;

  @override
  void initState() {
    super.initState();
    _sincronizar();
    widget.detalle?.registrar(_fuente);
  }

  @override
  void didUpdateWidget(PreparacionSolucionSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sincronizar();
    if (oldWidget.detalle != widget.detalle) {
      oldWidget.detalle?.quitar(_fuente);
      widget.detalle?.registrar(_fuente);
    }
  }

  @override
  void dispose() {
    widget.detalle?.quitar(_fuente);
    for (final mapa in [
      _lecturaInicial,
      _lecturaFinal,
      _litros,
      _marcador,
      _tempMacho,
      _tempHembra,
    ]) {
      for (final c in mapa.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _sincronizar() {
    _sincronizarPorGalpon(widget.galpones, _lecturaInicial);
    _sincronizarPorGalpon(widget.galpones, _lecturaFinal);
    _sincronizarPorGalpon(widget.galpones, _litros);
    _sincronizarPorGalpon(widget.galpones, _marcador);
    _sincronizarPorGalpon(widget.galpones, _tempMacho);
    _sincronizarPorGalpon(widget.galpones, _tempHembra);
    _horaInicio.removeWhere((g, _) => !widget.galpones.contains(g));
    _horaFinal.removeWhere((g, _) => !widget.galpones.contains(g));
  }

  /// Cantidad de agua del galpón: lectura final menos la inicial.
  double? _cantidadAgua(String galpon) {
    final inicial = _numeroDe(_lecturaInicial[galpon]!);
    final final_ = _numeroDe(_lecturaFinal[galpon]!);
    if (inicial == null || final_ == null) return null;
    final cantidad = final_ - inicial;
    return cantidad < 0 ? null : cantidad;
  }

  /// Minutos transcurridos entre la hora de inicio y la final, o `null` si
  /// falta alguna o la final quedó antes que la inicial.
  int? _minutosVacunacion(String galpon) {
    final inicio = _minutosDe(_horaInicio[galpon] ?? '');
    final fin = _minutosDe(_horaFinal[galpon] ?? '');
    if (inicio == null || fin == null || fin < inicio) return null;
    return fin - inicio;
  }

  /// Un renglón por dato cargado de cada galpón.
  /// Se incluyen también los renglones calculados (cantidad de agua y tiempo de
  /// vacunación) para que el registro guardado sea la foto de lo que se vio en
  /// pantalla: si después cambia la fórmula, lo ya registrado no se mueve. La
  /// edad no va acá porque es un dato de la cabecera.
  List<Map<String, dynamic>> _detalleFilas() {
    final filas = <Map<String, dynamic>>[];
    for (final g in widget.galpones) {
      void numero(String parametro, double? valor) {
        if (valor == null) return;
        filas.add(
          detalleFila(
            seccion: VacSeccion.solucion,
            galpon: g,
            parametro: parametro,
            valorNum: valor,
          ),
        );
      }

      void hora(String parametro, String valor) {
        if (valor.isEmpty) return;
        filas.add(
          detalleFila(
            seccion: VacSeccion.solucion,
            galpon: g,
            parametro: parametro,
            hora: valor,
          ),
        );
      }

      /// El tiempo de vacunación no es una hora del reloj sino una duración
      /// `hh:mm`: va como texto para que el informe lo muestre tal cual y no lo
      /// recorte al rango 00:00-23:59 de la columna `hora`.
      void texto(String parametro, String valor) {
        if (valor.isEmpty) return;
        filas.add(
          detalleFila(
            seccion: VacSeccion.solucion,
            galpon: g,
            parametro: parametro,
            valorTexto: valor,
          ),
        );
      }

      numero('Lectura inicial de medidor', _numeroDe(_lecturaInicial[g]!));
      numero('Lectura final de medidor', _numeroDe(_lecturaFinal[g]!));
      numero('Cantidad de agua (m3)', _cantidadAgua(g));
      numero('Litros de vacuna preparada', _numeroDe(_litros[g]!));
      numero('Marcador azul', _numeroDe(_marcador[g]!));
      numero('Temperatura Corral macho', _numeroDe(_tempMacho[g]!));
      numero('Temperatura Corral hembra', _numeroDe(_tempHembra[g]!));
      hora('Hora de inicio de vacunación', _horaInicio[g] ?? '');
      hora('Hora final de vacunación', _horaFinal[g] ?? '');
      final minutos = _minutosVacunacion(g);
      texto('Tiempo de vacunación', minutos == null ? '' : _hhmm(minutos));
    }

    return filas;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.galpones.isEmpty) {
      return const BioInfoBanner(
        text: 'Seleccione los galpones en «Información de vacuna» para cargar la '
            'preparación de la solución vacunal.',
        icon: Icons.science_outlined,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
      ),
      child: BioTable(
        rowHeight: 48,
        expandir: true,
        columns: [
          const BioColumn('Descripción', width: 168, align: TextAlign.left),
          for (final g in widget.galpones) BioColumn('Galpón $g', width: 84),
        ],
        rowCount: _filas.length,
        rowBuilder: (context, index) => [
          BioText(_filas[index], align: TextAlign.left, bold: true, fontSize: 11.5),
          for (final g in widget.galpones) _celda(index, g),
        ],
      ),
    );
  }

  Widget _celda(int fila, String galpon) {
    switch (fila) {
      // La edad sale de «Información de vacuna»; no se escribe acá.
      case 0:
        return BioText(
          widget.edad == null ? '—' : '${widget.edad} días',
          bold: true,
        );
      case 1:
        return _campo(_lecturaInicial[galpon]!, '0');
      case 2:
        return _campo(_lecturaFinal[galpon]!, '0');
      case 3:
        return BioText(_cantidad(_cantidadAgua(galpon)), bold: true);
      case 4:
        return _campo(_litros[galpon]!, '0');
      case 5:
        return _campo(_marcador[galpon]!, '0');
      case 6:
        return _campo(
          _tempMacho[galpon]!,
          '0.0',
          formatters: [_Temperatura2Decimales()],
        );
      case 7:
        return _campo(
          _tempHembra[galpon]!,
          '0.0',
          formatters: [_Temperatura2Decimales()],
        );
      case 8:
        return _celdaHora(galpon, esInicio: true);
      case 9:
        return _celdaHora(galpon, esInicio: false);
      default:
        final minutos = _minutosVacunacion(galpon);
        return BioText(
          minutos == null ? '--:--' : _hhmm(minutos),
          bold: true,
        );
    }
  }

  Widget _campo(
    TextEditingController controller,
    String hint, {
    List<TextInputFormatter>? formatters,
  }) {
    return BioTextField(
      controller: controller,
      hint: hint,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: formatters ?? [_Numero2Decimales()],
      // Los renglones calculados dependen de estas celdas, así que cualquier
      // cambio tiene que repintar la tabla.
      onChanged: (_) => setState(() {}),
      bold: true,
    );
  }

  Widget _celdaHora(String galpon, {required bool esInicio}) {
    final valor = (esInicio ? _horaInicio[galpon] : _horaFinal[galpon]) ?? '';
    return InkWell(
      onTap: () async {
        final h = await showBioHoraDialog(context, valorActual: valor);
        if (h == null) return;
        setState(() {
          if (esInicio) {
            _horaInicio[galpon] = h;
          } else {
            _horaFinal[galpon] = h;
          }
        });
      },
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          valor.isEmpty ? '--:--' : valor,
          style: TextStyle(
            fontSize: 12,
            fontWeight: valor.isEmpty ? FontWeight.w500 : FontWeight.w700,
            color: valor.isEmpty ? AppColors.textMuted : AppColors.horaText,
          ),
        ),
      ),
    );
  }
}

/// Sección 8: evaluación de la eficiencia de vacunación.
/// Un renglón por galpón. La cantidad total, los pollos sin vacuna y la
/// eficiencia se calculan; el resto se escribe.
class EvaluacionEficienciaSection extends StatefulWidget {
  const EvaluacionEficienciaSection({
    super.key,
    required this.galpones,
    this.detalle,
  });

  final List<String> galpones;

  /// Recolector del detalle; la sección se registra sola al montarse.
  final VacunacionDetalleController? detalle;

  @override
  State<EvaluacionEficienciaSection> createState() =>
      _EvaluacionEficienciaSectionState();
}

/// Contadores escritos de un galpón en la evaluación de eficiencia.
class _Contadores {
  final TextEditingController evaluadosMacho = TextEditingController();
  final TextEditingController evaluadosHembra = TextEditingController();
  final TextEditingController conVacunaMacho = TextEditingController();
  final TextEditingController conVacunaHembra = TextEditingController();

  void dispose() {
    evaluadosMacho.dispose();
    evaluadosHembra.dispose();
    conVacunaMacho.dispose();
    conVacunaHembra.dispose();
  }
}

class _EvaluacionEficienciaSectionState
    extends State<EvaluacionEficienciaSection> {
  final Map<String, _Contadores> _filas = {};

  late final List<Map<String, dynamic>> Function() _fuente = _detalleFilas;

  @override
  void initState() {
    super.initState();
    _sincronizar();
    widget.detalle?.registrar(_fuente);
  }

  @override
  void didUpdateWidget(EvaluacionEficienciaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sincronizar();
    if (oldWidget.detalle != widget.detalle) {
      oldWidget.detalle?.quitar(_fuente);
      widget.detalle?.registrar(_fuente);
    }
  }

  @override
  void dispose() {
    widget.detalle?.quitar(_fuente);
    for (final f in _filas.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _sincronizar() {
    for (final g in widget.galpones) {
      _filas.putIfAbsent(g, () => _Contadores());
    }
    for (final g in _filas.keys.toList()) {
      if (!widget.galpones.contains(g)) {
        _filas.remove(g)!.dispose();
      }
    }
  }

  /// Total de pollos evaluados del galpón (macho + hembra).
  int? _total(_Contadores f) {
    final m = _enteroDe(f.evaluadosMacho);
    final h = _enteroDe(f.evaluadosHembra);
    if (m == null && h == null) return null;
    return (m ?? 0) + (h ?? 0);
  }

  /// Pollos sin vacuna: los evaluados que no quedaron vacunados. Nunca baja de
  /// cero, para que un conteo mal cargado no muestre negativos.
  int? _sinVacuna(TextEditingController evaluados, TextEditingController con) {
    final total = _enteroDe(evaluados);
    final vacunados = _enteroDe(con);
    if (total == null && vacunados == null) return null;
    final resta = (total ?? 0) - (vacunados ?? 0);
    return resta < 0 ? 0 : resta;
  }

  /// Eficiencia de vacunación: vacunados sobre evaluados, en porcentaje.
  int? _eficiencia(_Contadores f) {
    final total = _total(f);
    if (total == null || total == 0) return null;
    final vacunados = (_enteroDe(f.conVacunaMacho) ?? 0) +
        (_enteroDe(f.conVacunaHembra) ?? 0);
    return ((vacunados / total) * 100).round();
  }

  /// Un renglón por dato de cada galpón, en el mismo orden que las columnas de
  /// la tabla. `grupo` es el encabezado agrupado (Pollos evaluados, Pollos con
  /// vacuna, Pollos sin vacuna) y queda vacío en las columnas sueltas.
  /// Igual que en la solución vacunal, los renglones calculados (cantidad
  /// total, pollos sin vacuna y eficiencia) se guardan tal como se vieron.
  List<Map<String, dynamic>> _detalleFilas() {
    final filas = <Map<String, dynamic>>[];
    for (final g in widget.galpones) {
      final c = _filas[g]!;

      void numero(String grupo, String parametro, int? valor) {
        if (valor == null) return;
        filas.add(
          detalleFila(
            seccion: VacSeccion.eficiencia,
            galpon: g,
            grupo: grupo,
            parametro: parametro,
            valorNum: valor.toDouble(),
          ),
        );
      }

      numero('Pollos evaluados', 'Macho', _enteroDe(c.evaluadosMacho));
      numero('Pollos evaluados', 'hembra', _enteroDe(c.evaluadosHembra));
      numero('', 'Cantidad total', _total(c));
      numero('Pollos con vacuna', 'Macho', _enteroDe(c.conVacunaMacho));
      numero('Pollos con vacuna', 'hembra', _enteroDe(c.conVacunaHembra));
      numero(
        'Pollos sin vacuna',
        'Macho',
        _sinVacuna(c.evaluadosMacho, c.conVacunaMacho),
      );
      numero(
        'Pollos sin vacuna',
        'hembra',
        _sinVacuna(c.evaluadosHembra, c.conVacunaHembra),
      );
      numero('', 'Eficiencia', _eficiencia(c));
    }

    return filas;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.galpones.isEmpty) {
      return const BioInfoBanner(
        text: 'Seleccione los galpones en «Información de vacuna» para cargar la '
            'evaluación de eficiencia.',
        icon: Icons.fact_check_outlined,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppColors.radiusSm),
      ),
      child: BioTable(
        rowHeight: 48,
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
        rowCount: widget.galpones.length,
        rowBuilder: (context, i) {
          final f = _filas[widget.galpones[i]]!;
          final eficiencia = _eficiencia(f);
          return [
            BioText(widget.galpones[i], bold: true),
            _contador(f.evaluadosMacho),
            _contador(f.evaluadosHembra),
            BioText(_total(f)?.toString() ?? '—', bold: true),
            _contador(f.conVacunaMacho),
            _contador(f.conVacunaHembra),
            BioText(
              _sinVacuna(f.evaluadosMacho, f.conVacunaMacho)?.toString() ?? '—',
            ),
            BioText(
              _sinVacuna(f.evaluadosHembra, f.conVacunaHembra)?.toString() ?? '—',
            ),
            BioText(
              eficiencia == null ? '—' : '$eficiencia%',
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

  Widget _contador(TextEditingController controller) {
    return BioTextField(
      controller: controller,
      hint: '0',
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      soloDigitos: true,
      maxLength: 6,
      // Total, sin vacuna y eficiencia se recalculan al escribir.
      onChanged: (_) => setState(() {}),
    );
  }
}
