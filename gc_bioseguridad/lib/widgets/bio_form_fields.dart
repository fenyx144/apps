import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/catalog_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';

/// Texto del aviso cuando falta descargar un catálogo de bioseguridad.
const String bioSinCatalogoMsg =
    'Faltan catálogos. Descárguelos desde el menú lateral y vuelva a intentar.';

/// Texto del aviso cuando todavía no se descargó la planificación de visitas.
///
/// Va junto con los catálogos (misma nube del menú lateral), así que el aviso
/// es el mismo viaje para el vigilante. Se muestra al tocar el atajo de las
/// planificadas del día; en pantalla el mismo dato va en el paréntesis del
/// botón («descargue en el panel lateral»), sin un segundo renglón de aviso.
const String bioSinPlanificacionMsg =
    'Sin planificación descargada. Descárguela desde el menú lateral '
    '(nube Descargar).';

/// Comprueba que el catálogo tenga opciones antes de abrir un selector.
///
/// Sin descarga (o con una tabla que el servidor todavía no envía) la lista
/// viene vacía. En vez de abrir un selector en blanco —o, peor, inventar
/// opciones en la app— se avisa de dónde sale el catálogo. Devuelve `true`
/// cuando se puede seguir.
bool bioHayCatalogo(BuildContext context, List<Object?> opciones) {
  if (opciones.isNotEmpty) return true;
  showWarningToast(context, bioSinCatalogoMsg);
  return false;
}

/// Abre un selector de opciones en hoja inferior y devuelve el elegido.
Future<T?> showBioOptionsSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
  /// Segunda línea de cada opción, para el dato que ayuda a distinguirlas
  /// (p. ej. de dónde viene una visita planificada). Vacía no se dibuja.
  String Function(T)? subtitleOf,
  T? selected,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Material(
        // Material y no Container: la lista de opciones son ListTile, que
        // pintan su fondo y su onda sobre el Material más cercano, y con un
        // Container con color el framework avisa de que no se verían.
        color: context.dialogSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 6),
              decoration: BoxDecoration(
                color: context.textThemeMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.textThemePrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final opt = options[i];
                  final isSel = selected == opt;
                  final sub = subtitleOf?.call(opt) ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(
                      labelOf(opt),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                        color: isSel
                            ? AppColors.primaryDark
                            : context.textThemePrimary,
                      ),
                    ),
                    subtitle: sub.isEmpty
                        ? null
                        : Text(
                            sub,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: context.textThemeSecondary,
                            ),
                          ),
                    trailing: isSel
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.primary,
                            size: 20,
                          )
                        : null,
                    onTap: () => Navigator.pop(context, opt),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Área de texto multilínea con etiqueta y contador.
///
/// El ícono no se pone como `prefixIcon` de Material: ese se centra en el alto
/// del cuadro, así que en un campo de varias líneas se hunde hacia el medio en
/// lugar de quedar junto a la primera línea. Acá se dibuja encima del campo con
/// un [Stack], a la altura en que arranca el texto, para que caiga sobre la
/// primera línea (o sobre la etiqueta cuando el campo está vacío) sin importar
/// cuántas líneas tenga.
class BioTextArea extends StatelessWidget {
  const BioTextArea({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.maxLength = 200,
    this.minLines = 3,
    this.maxLines = 4,
    this.icon,
    this.textCapitalization = TextCapitalization.sentences,
    this.enabled = true,
    this.onChanged,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLength;
  final int minLines;
  final int maxLines;

  /// Ícono del campo. `null` lo omite, útil en campos angostos donde el ícono
  /// deja sin sitio al texto.
  final IconData? icon;
  final TextCapitalization textCapitalization;

  /// `false` deja el campo en solo lectura (el valor se sigue viendo).
  final bool enabled;

  /// Aviso de cada cambio de texto (la placa extra lo usa para reconsultar).
  final ValueChanged<String>? onChanged;

  /// Etiquetas compactas dentro del campo (p. ej. planificación de la placa).
  final Widget? suffix;

  /// Distancia del ícono al borde izquierdo del cuadro y ancho que se le
  /// reserva al texto (ícono + separación) para que no lo pise.
  static const double _iconLeft = 14;
  static const double _iconSize = 20;
  static const double _gutter = _iconLeft + _iconSize + 10;

  @override
  Widget build(BuildContext context) {
    // El relleno vertical del tema marca dónde arranca la primera línea de
    // texto (la etiqueta flotante no empuja el contenido hacia abajo). Se toma
    // de ahí para que el ícono quede a esa misma altura, y para no repetir el
    // número si el tema cambia.
    final base =
        Theme.of(context).inputDecorationTheme.contentPadding ??
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    final padding = base.resolve(Directionality.of(context));

    final field = TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      enabled: enabled,
      onChanged: onChanged,
      textCapitalization: textCapitalization,
      inputFormatters: [LengthLimitingTextInputFormatter(maxLength)],
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: context.textThemePrimary,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: true,
        // El ícono vive fuera del campo: se le deja su carril a la izquierda.
        contentPadding: icon == null
            ? null
            : EdgeInsets.only(
                left: _gutter,
                right: padding.right,
                top: padding.top,
                bottom: padding.bottom,
              ),
        // Sin contador «0/200»: el límite ya lo aplica el formateador y el
        // contador solo robaba alto y ruido visual.
        counterText: '',
        suffix: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );

    if (icon == null) return field;

    return Stack(
      children: [
        field,
        // Sin gestos: el toque en el ícono tiene que seguir abriendo el campo.
        Positioned(
          left: _iconLeft,
          top: padding.top,
          child: IgnorePointer(
            child: Icon(icon, size: _iconSize, color: context.textThemeMuted),
          ),
        ),
      ],
    );
  }
}

/// Separa el texto en hora y minuto, sin validar todavía el rango.
(int, int)? _partesHora(String texto) {
  if (texto.contains(':')) {
    final partes = texto.split(':');
    // Se acepta «6:30» y también «06:30:00»: la base guarda segundos, así que
    // ese formato llega desde registros ya guardados. Los segundos se ignoran
    // porque la app trabaja en minutos.
    if (partes.length < 2 || partes.length > 3) return null;
    final h = int.tryParse(partes[0].trim());
    final m = int.tryParse(partes[1].trim());
    return (h == null || m == null) ? null : (h, m);
  }

  // Sin dos puntos: se interpreta el bloque de dígitos. «630» es 6:30 y
  // «0630» también; «18» es 18:00.
  final digitos = texto.replaceAll(RegExp(r'\D'), '');
  switch (digitos.length) {
    case 1:
    case 2:
      final h = int.tryParse(digitos);
      return h == null ? null : (h, 0);
    case 3:
      final h = int.tryParse(digitos.substring(0, 1));
      final m = int.tryParse(digitos.substring(1));
      return (h == null || m == null) ? null : (h, m);
    case 4:
      final h = int.tryParse(digitos.substring(0, 2));
      final m = int.tryParse(digitos.substring(2));
      return (h == null || m == null) ? null : (h, m);
    default:
      return null;
  }
}

/// Normaliza lo que el usuario escribió a `HH:mm`, o `null` si no es una hora
/// válida.
///
/// Acepta las formas que la gente usa en campo: `0630`, `06:30`, `6:30`, `18`.
String? bioParseHora(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;

  final partes = _partesHora(t);
  if (partes == null) return null;

  final (hora, minuto) = partes;
  if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) return null;

  return '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
}

/// Máximo de horas en una duración `hh:mm`.
const int bioMaxHorasDuracion = 99;

/// Normaliza una duración `hh:mm` (horas 0–99, minutos 0–59).
String? bioParseDuracion(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;

  final partes = _partesHora(t);
  if (partes == null) return null;

  final (hora, minuto) = partes;
  if (hora < 0 ||
      hora > bioMaxHorasDuracion ||
      minuto < 0 ||
      minuto > 59) {
    return null;
  }

  return '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
}

/// Convierte una hora de 24 a la hora del reloj (1..12). Las 00 y las 12 son
/// las doce.
int bioHora12(int hora24) {
  final h = hora24 % 12;
  return h == 0 ? 12 : h;
}

/// Convierte una hora del reloj (1..12) y su meridiano a una hora de 24.
///
/// Las 12 de la mañana son las 00: el reloj no tiene cero, así que la hora 12
/// vuelve a empezar en cada meridiano.
int bioHora24(int hora12, bool esPm) {
  final h = hora12 % 12;
  return esPm ? h + 12 : h;
}

/// Pide una hora con tres listas al estilo Cupertino (hora, minutos y AM/PM).
///
/// Las listas eligen sobre doce horas más el meridiano, que es como se lee un
/// reloj de aguja, pero el valor que sale de acá siempre es de 24 (`HH:mm`),
/// que es lo que esperan la base y el backend.
Future<String?> showBioHoraDialog(
  BuildContext context, {
  String valorActual = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _BioHoraDialog(valorInicial: valorActual),
  );
}

/// Pide una duración en `hh:mm` (horas + minutos, sin AM/PM).
Future<String?> showBioDuracionDialog(
  BuildContext context, {
  String valorActual = '',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _BioDuracionDialog(valorInicial: valorActual),
  );
}

/// Alto de una fila de las listas del reloj.
///
/// Más alto que el de otras listas de la app a propósito: la hora se elige de
/// un vistazo y con los números chicos se erraba la fila. Lo usan las tres
/// ruedas y el recuadro que marca la fila elegida, así que tiene que ser uno
/// solo.
const double _kAltoFilaHora = 44.0;

/// Ancho que buscan las tres listas del reloj. Es el ancho al que los números
/// grandes se leen cómodos; en pantallas más chicas las ruedas se achican
/// repartiéndose el espacio que hay.
const double _kAnchoListasHora = 320.0;

class _BioHoraDialog extends StatefulWidget {
  const _BioHoraDialog({required this.valorInicial});

  final String valorInicial;

  @override
  State<_BioHoraDialog> createState() => _BioHoraDialogState();
}

/// Diálogo de hora: tres listas al estilo Cupertino (hora, minutos y AM/PM).
///
/// Las listas eligen sobre doce horas más el meridiano, que es como se lee un
/// reloj de aguja; el valor que devuelve el diálogo sigue siendo de 24
/// (`HH:mm`), que es lo que esperan la base y el backend. La conversión vive en
/// [bioHora24] y [bioHora12].
class _BioHoraDialogState extends State<_BioHoraDialog> {
  /// Hora en formato de 24. Es la fuente de verdad del diálogo: las listas solo
  /// la leen y la escriben.
  late int _hora;

  late int _minuto;

  /// Posicionan las listas en el valor de partida; sin esto abrirían siempre en
  /// el primer elemento.
  late final FixedExtentScrollController _ruedaHora;
  late final FixedExtentScrollController _ruedaMinuto;
  late final FixedExtentScrollController _ruedaMeridiano;

  @override
  void initState() {
    super.initState();
    // Sin un valor de partida reconocible se abre en la hora actual, como
    // cualquier reloj.
    final inicial = bioParseHora(widget.valorInicial);
    final ahora = TimeOfDay.now();
    _hora = inicial == null ? ahora.hour : int.parse(inicial.substring(0, 2));
    _minuto =
        inicial == null ? ahora.minute : int.parse(inicial.substring(3, 5));
    _ruedaHora = FixedExtentScrollController(initialItem: bioHora12(_hora) - 1);
    _ruedaMinuto = FixedExtentScrollController(initialItem: _minuto);
    _ruedaMeridiano = FixedExtentScrollController(initialItem: _esPm ? 1 : 0);
  }

  @override
  void dispose() {
    _ruedaHora.dispose();
    _ruedaMinuto.dispose();
    _ruedaMeridiano.dispose();
    super.dispose();
  }

  /// Valor que se guarda y se devuelve: siempre en 24 horas (`HH:mm`), aunque
  /// las listas muestren 12.
  String get _valor => '${_hora.toString().padLeft(2, '0')}:'
      '${_minuto.toString().padLeft(2, '0')}';

  /// `true` si la hora es de la tarde o de la noche.
  bool get _esPm => _hora >= 12;

  /// Rueda de la hora. Recibe la posición de la lista (0 = la 1) y conserva el
  /// AM/PM que ya estaba elegido: el meridiano tiene su propia lista.
  void _cambiarHora(int posicion) {
    setState(() => _hora = bioHora24(posicion + 1, _esPm));
  }

  /// Rueda del meridiano. Conserva la hora: las 9 de la mañana pasan a las 21.
  void _cambiarMeridiano(int posicion) {
    setState(() => _hora = bioHora24(bioHora12(_hora), posicion == 1));
  }

  void _aceptar() {
    Navigator.pop(context, _valor);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      scrollable: true,
      // Menos margen que el resto de los diálogos: las tres listas necesitan
      // ancho para que los números se vean grandes, y con el margen por
      // defecto quedaban apretadas en un teléfono chico.
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Text(
        'Hora',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: context.textThemePrimary,
        ),
      ),
      content: Center(child: _listas()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _aceptar, child: const Text('Aceptar')),
      ],
    );
  }

  /// Ancho de las tres listas.
  ///
  /// Se estira hasta [_kAnchoListasHora], que es donde las ruedas se ven
  /// cómodas, pero nunca más allá de lo que entra en la pantalla: los márgenes
  /// del diálogo se descuentan o en un teléfono chico las listas se salen.
  double _anchoListas(BuildContext context) {
    const margenesDialogo = 96.0;
    final disponible = MediaQuery.sizeOf(context).width - margenesDialogo;
    return disponible < _kAnchoListasHora ? disponible : _kAnchoListasHora;
  }

  /// Las tres listas del reloj: hora, minutos y AM/PM.
  ///
  /// Las ruedas se reparten el ancho en vez de tener uno fijo: así el mismo
  /// diálogo sirve en un teléfono grande y en uno chico sin recortar nada.
  Widget _listas() {
    return SizedBox(
      key: const ValueKey('bioHoraListas'),
      width: _anchoListas(context),
      height: _kAltoFilaHora * 5,
      child: Row(
        children: [
          Expanded(
            flex: 84,
            child: _rueda(
              key: const ValueKey('bioHoraRuedaHora'),
              controller: _ruedaHora,
              itemCount: 12,
              // Las doce posiciones son las horas del reloj, de la 1 a la 12
              // (no de la 0 a la 11): la lista se lee como un reloj.
              textoDe: (i) => (i + 1).toString().padLeft(2, '0'),
              onSelected: _cambiarHora,
            ),
          ),
          _dosPuntos(),
          Expanded(
            flex: 84,
            child: _rueda(
              key: const ValueKey('bioHoraRuedaMinuto'),
              controller: _ruedaMinuto,
              itemCount: 60,
              textoDe: (i) => i.toString().padLeft(2, '0'),
              onSelected: (i) => setState(() => _minuto = i),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            flex: 76,
            child: _rueda(
              key: const ValueKey('bioHoraRuedaMeridiano'),
              controller: _ruedaMeridiano,
              itemCount: 2,
              textoDe: (i) => i == 0 ? 'AM' : 'PM',
              onSelected: _cambiarMeridiano,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rueda({
    required Key key,
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) textoDe,
    required ValueChanged<int> onSelected,
  }) {
    return SizedBox.expand(
      key: key,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: _kAltoFilaHora,
        onSelectedItemChanged: onSelected,
        children: [
          for (var i = 0; i < itemCount; i++)
            Center(
              child: Text(
                textoDe(i),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: context.textThemePrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dosPuntos() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: context.textThemeMuted,
        ),
      ),
    );
  }
}

class _BioDuracionDialog extends StatefulWidget {
  const _BioDuracionDialog({required this.valorInicial});

  final String valorInicial;

  @override
  State<_BioDuracionDialog> createState() => _BioDuracionDialogState();
}

class _BioDuracionDialogState extends State<_BioDuracionDialog> {
  late int _hora;
  late int _minuto;
  late final FixedExtentScrollController _ruedaHora;
  late final FixedExtentScrollController _ruedaMinuto;

  @override
  void initState() {
    super.initState();
    final inicial = bioParseDuracion(widget.valorInicial);
    _hora = inicial == null ? 0 : int.parse(inicial.substring(0, 2));
    _minuto =
        inicial == null ? 0 : int.parse(inicial.substring(3, 5));
    _ruedaHora = FixedExtentScrollController(initialItem: _hora);
    _ruedaMinuto = FixedExtentScrollController(initialItem: _minuto);
  }

  @override
  void dispose() {
    _ruedaHora.dispose();
    _ruedaMinuto.dispose();
    super.dispose();
  }

  String get _valor => '${_hora.toString().padLeft(2, '0')}:'
      '${_minuto.toString().padLeft(2, '0')}';

  void _aceptar() => Navigator.pop(context, _valor);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Text(
        'Duración',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: context.textThemePrimary,
        ),
      ),
      content: Center(child: _listas()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(onPressed: _aceptar, child: const Text('Aceptar')),
      ],
    );
  }

  double _anchoListas(BuildContext context) {
    const margenesDialogo = 96.0;
    final disponible = MediaQuery.sizeOf(context).width - margenesDialogo;
    return disponible < _kAnchoListasHora ? disponible : _kAnchoListasHora;
  }

  Widget _listas() {
    return SizedBox(
      key: const ValueKey('bioDuracionListas'),
      width: _anchoListas(context),
      height: _kAltoFilaHora * 5,
      child: Row(
        children: [
          Expanded(
            child: _rueda(
              key: const ValueKey('bioDuracionRuedaHora'),
              controller: _ruedaHora,
              itemCount: bioMaxHorasDuracion + 1,
              textoDe: (i) => i.toString().padLeft(2, '0'),
              onSelected: (i) => setState(() => _hora = i),
            ),
          ),
          _dosPuntos(),
          Expanded(
            child: _rueda(
              key: const ValueKey('bioDuracionRuedaMinuto'),
              controller: _ruedaMinuto,
              itemCount: 60,
              textoDe: (i) => i.toString().padLeft(2, '0'),
              onSelected: (i) => setState(() => _minuto = i),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rueda({
    required Key key,
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) textoDe,
    required ValueChanged<int> onSelected,
  }) {
    return SizedBox.expand(
      key: key,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: _kAltoFilaHora,
        onSelectedItemChanged: onSelected,
        children: [
          for (var i = 0; i < itemCount; i++)
            Center(
              child: Text(
                textoDe(i),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: context.textThemePrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dosPuntos() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        ':',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          color: context.textThemeMuted,
        ),
      ),
    );
  }
}

/// Campo de hora tocable.
class BioTimeField extends StatelessWidget {
  const BioTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onPicked,
    this.enabled = true,
    this.esDuracion = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onPicked;
  final bool enabled;

  /// Si es `true`, abre el selector de duración (`hh:mm`) sin AM/PM.
  final bool esDuracion;

  Future<void> _pick(BuildContext context) async {
    final elegida = esDuracion
        ? await showBioDuracionDialog(context, valorActual: value)
        : await showBioHoraDialog(context, valorActual: value);
    if (elegida == null) return;
    onPicked(elegida);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(
            esDuracion ? Icons.timelapse_rounded : Icons.schedule_rounded,
            color: AppColors.iconAccent,
          ),
        ),
        child: Text(
          value.isEmpty ? '--:--' : value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: value.isEmpty ? FontWeight.w500 : FontWeight.w700,
            color: value.isEmpty
                ? context.textThemeMuted
                : AppColors.horaText,
          ),
        ),
      ),
    );
  }
}

/// Encabezado de bloque dentro de un formulario.
class BioFormSection extends StatelessWidget {
  const BioFormSection({
    super.key,
    required this.title,
    required this.children,
    this.icon,
  });

  final String title;
  final List<Widget> children;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.primaryDark),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: context.textThemeSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    );
  }
}

/// Campo de solo lectura con el mismo estilo que los selectores del formulario.
class BioReadOnlyField extends StatelessWidget {
  const BioReadOnlyField({
    super.key,
    required this.label,
    required this.value,
    this.placeholder = '—',
    this.icon,
    this.maxLines = 2,
  });

  final String label;
  final String value;
  final String placeholder;
  final IconData? icon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final hasValue = value.trim().isNotEmpty;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: icon == null
            ? null
            : Icon(icon, color: AppColors.iconAccent, size: 22),
      ),
      child: Text(
        hasValue ? value : placeholder,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: hasValue ? FontWeight.w700 : FontWeight.w500,
          color: hasValue
              ? context.textThemePrimary
              : context.textThemeMuted,
          fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
        ),
      ),
    );
  }
}

/// Lista marcable dentro de un recuadro tipo formulario.
class BioCheckListCard extends StatelessWidget {
  const BioCheckListCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.emptyText,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final String? emptyText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 17, color: AppColors.primaryDark),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.textThemeSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: context.surfaceCard,
            borderRadius: BorderRadius.circular(AppColors.radiusMd),
            border: Border.all(color: context.borderSubtle),
          ),
          child: children.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    emptyText ?? 'Sin registros',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: context.textThemeMuted,
                    ),
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < children.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: context.borderSubtle.withValues(alpha: 0.7),
                        ),
                      children[i],
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// Banner informativo suave.
class BioInfoBanner extends StatelessWidget {
  const BioInfoBanner({
    super.key,
    required this.text,
    this.icon,
    this.warning = false,
  });

  final String text;
  final IconData? icon;

  /// Pinta el aviso en ámbar: para «falta hacer algo», no para informar.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.warning : AppColors.primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? Icons.info_outline_rounded,
            size: 18,
            color: warning ? AppColors.warning : AppColors.primaryDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: context.textThemeSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso de «faltan catálogos» para la cabecera de un formulario.
///
/// Se dibuja solo mientras no haya descarga, así no ocupa lugar en un equipo
/// que ya bajó el catálogo. Usa `watch`, de modo que al descargar desde el menú
/// lateral el aviso desaparece sin reabrir la pantalla.
class BioCatalogoAviso extends StatelessWidget {
  const BioCatalogoAviso({super.key});

  @override
  Widget build(BuildContext context) {
    if (!context.watch<CatalogService>().sinDescargar) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: BioInfoBanner(
        icon: Icons.cloud_off_rounded,
        text: bioSinCatalogoMsg,
        warning: true,
      ),
    );
  }
}
