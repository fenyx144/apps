import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Abre un selector de opciones en hoja inferior y devuelve el elegido.
Future<T?> showBioOptionsSheet<T>({
  required BuildContext context,
  required String title,
  required List<T> options,
  required String Function(T) labelOf,
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

/// Máximo de horas en una duración `hh:mm` (p. ej. tiempo de sedeó).
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
/// Las 12 de la mañana son las 00: el reloj no tiene cero, así que la hora 12
/// vuelve a empezar en cada meridiano.
int bioHora24(int hora12, bool esPm) {
  final h = hora12 % 12;
  return esPm ? h + 12 : h;
}

/// Pide una hora con tres listas al estilo Cupertino (hora, minutos y AM/PM),
/// con la opción de escribirla con el teclado.
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
/// Las listas eligen sobre doce horas más el meridiano, que es como se lee un
/// reloj de aguja; el valor que devuelve el diálogo sigue siendo de 24
/// (`HH:mm`), que es lo que esperan la base y el backend. La conversión vive en
/// [bioHora24] y [bioHora12], para que las listas y el teclado no puedan
/// discrepar.
class _BioHoraDialogState extends State<_BioHoraDialog> {
  /// `true` cuando se está escribiendo la hora con el teclado.
  bool _teclado = false;

  /// Hora en formato de 24. Es la fuente de verdad del diálogo: las listas y el
  /// teclado solo la leen y la escriben.
  late int _hora;

  late int _minuto;

  late final TextEditingController _controller = TextEditingController(
    text: bioParseHora(widget.valorInicial) ?? '',
  );

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
    _controller.dispose();
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

  /// Alterna entre las listas y el teclado, llevándose el valor de un lado al
  /// otro para no perder lo elegido.
  void _alternarModo() {
    setState(() {
      if (_teclado) {
        final escrito = bioParseHora(_controller.text);
        if (escrito != null) {
          _hora = int.parse(escrito.substring(0, 2));
          _minuto = int.parse(escrito.substring(3, 5));
        }
        // Las listas se montan recién en el próximo cuadro, así que recién ahí
        // se las puede dejar apuntando a lo que se escribió.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _sincronizarRuedas(),
        );
      } else {
        _controller.text = _valor;
      }
      _teclado = !_teclado;
    });
  }

  /// Deja las tres listas apuntando a la hora que tiene el diálogo.
  void _sincronizarRuedas() {
    if (!mounted) return;
    if (_ruedaHora.hasClients) _ruedaHora.jumpToItem(bioHora12(_hora) - 1);
    if (_ruedaMinuto.hasClients) _ruedaMinuto.jumpToItem(_minuto);
    if (_ruedaMeridiano.hasClients) _ruedaMeridiano.jumpToItem(_esPm ? 1 : 0);
  }

  void _aceptar() {
    if (_teclado) {
      final valor = bioParseHora(_controller.text);
      if (valor != null) Navigator.pop(context, valor);
      return;
    }
    Navigator.pop(context, _valor);
  }

  @override
  Widget build(BuildContext context) {
    final escrito = _controller.text.trim();
    final valor = bioParseHora(escrito);
    final error =
        escrito.isNotEmpty && valor == null ? 'Hora no válida' : null;
    final puedeAceptar = _teclado ? valor != null : true;

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
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: AppColors.iconAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Hora',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.textThemePrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: _teclado ? 'Elegir en las listas' : 'Escribir la hora',
            onPressed: _alternarModo,
            icon: Icon(
              _teclado
                  ? Icons.access_time_rounded
                  : Icons.keyboard_alt_outlined,
              color: AppColors.iconAccent,
            ),
          ),
        ],
      ),
      content: Center(
        child: _teclado ? _campoTexto(error) : _listas(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: puedeAceptar ? _aceptar : null,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }

  /// Ancho de las tres listas.
  /// Se estira hasta [_kAnchoListasHora], que es donde las ruedas se ven
  /// cómodas, pero nunca más allá de lo que entra en la pantalla: los márgenes
  /// del diálogo se descuentan o en un teléfono chico las listas se salen.
  double _anchoListas(BuildContext context) {
    const margenesDialogo = 96.0;
    final disponible = MediaQuery.sizeOf(context).width - margenesDialogo;
    return disponible < _kAnchoListasHora ? disponible : _kAnchoListasHora;
  }

  /// Las tres listas del reloj: hora, minutos y AM/PM.
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

  Widget _campoTexto(String? error) {
    return TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _aceptar(),
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: AppColors.horaText,
      ),
      decoration: InputDecoration(
        hintText: 'HH:MM',
        errorText: error,
        helperText: 'Escriba 1830 para las 18:30 (24 h)',
        helperStyle: TextStyle(
          fontSize: 11,
          color: context.textThemeMuted,
        ),
      ),
    );
  }
}

/// Diálogo de duración: dos listas (horas 0–99 y minutos), sin meridiano.
class _BioDuracionDialog extends StatefulWidget {
  const _BioDuracionDialog({required this.valorInicial});

  final String valorInicial;

  @override
  State<_BioDuracionDialog> createState() => _BioDuracionDialogState();
}

class _BioDuracionDialogState extends State<_BioDuracionDialog> {
  bool _teclado = false;
  late int _hora;
  late int _minuto;

  late final TextEditingController _controller = TextEditingController(
    text: bioParseDuracion(widget.valorInicial) ?? '',
  );

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
    _controller.dispose();
    _ruedaHora.dispose();
    _ruedaMinuto.dispose();
    super.dispose();
  }

  String get _valor => '${_hora.toString().padLeft(2, '0')}:'
      '${_minuto.toString().padLeft(2, '0')}';

  void _alternarModo() {
    setState(() {
      if (_teclado) {
        final escrito = bioParseDuracion(_controller.text);
        if (escrito != null) {
          _hora = int.parse(escrito.substring(0, 2));
          _minuto = int.parse(escrito.substring(3, 5));
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_ruedaHora.hasClients) _ruedaHora.jumpToItem(_hora);
          if (_ruedaMinuto.hasClients) _ruedaMinuto.jumpToItem(_minuto);
        });
      } else {
        _controller.text = _valor;
      }
      _teclado = !_teclado;
    });
  }

  void _aceptar() {
    if (_teclado) {
      final valor = bioParseDuracion(_controller.text);
      if (valor != null) Navigator.pop(context, valor);
      return;
    }
    Navigator.pop(context, _valor);
  }

  @override
  Widget build(BuildContext context) {
    final escrito = _controller.text.trim();
    final valor = bioParseDuracion(escrito);
    final error =
        escrito.isNotEmpty && valor == null ? 'Duración no válida' : null;
    final puedeAceptar = _teclado ? valor != null : true;

    return AlertDialog(
      backgroundColor: context.dialogSurface,
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          const Icon(
            Icons.timelapse_rounded,
            color: AppColors.iconAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Duración',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.textThemePrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: _teclado ? 'Elegir en las listas' : 'Escribir la duración',
            onPressed: _alternarModo,
            icon: Icon(
              _teclado
                  ? Icons.timelapse_rounded
                  : Icons.keyboard_alt_outlined,
              color: AppColors.iconAccent,
            ),
          ),
        ],
      ),
      content: Center(
        child: _teclado ? _campoTexto(error) : _listas(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: puedeAceptar ? _aceptar : null,
          child: const Text('Aceptar'),
        ),
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

  Widget _campoTexto(String? error) {
    return TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
        LengthLimitingTextInputFormatter(5),
      ],
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _aceptar(),
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: AppColors.horaText,
      ),
      decoration: InputDecoration(
        hintText: 'HH:MM',
        errorText: error,
        helperText: 'Escriba 130 para 1 h 30 min, 0800 para 8 h',
        helperStyle: TextStyle(
          fontSize: 11,
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

/// Banner informativo suave.
class BioInfoBanner extends StatelessWidget {
  const BioInfoBanner({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon ?? Icons.info_outline_rounded,
            size: 18,
            color: AppColors.primaryDark,
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
