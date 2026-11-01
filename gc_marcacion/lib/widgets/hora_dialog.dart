import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import '../utils/theme_colors.dart';

(int, int)? _partesHora(String texto) {
  if (texto.contains(':')) {
    final partes = texto.split(':');
    if (partes.length < 2 || partes.length > 3) return null;
    final h = int.tryParse(partes[0].trim());
    final m = int.tryParse(partes[1].trim());
    return (h == null || m == null) ? null : (h, m);
  }

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

String? bioParseHora(String texto) {
  final t = texto.trim();
  if (t.isEmpty) return null;
  final partes = _partesHora(t);
  if (partes == null) return null;
  final (hora, minuto) = partes;
  if (hora < 0 || hora > 23 || minuto < 0 || minuto > 59) return null;
  return '${hora.toString().padLeft(2, '0')}:${minuto.toString().padLeft(2, '0')}';
}

int bioHora12(int hora24) {
  final h = hora24 % 12;
  return h == 0 ? 12 : h;
}

int bioHora24(int hora12, bool esPm) {
  final h = hora12 % 12;
  return esPm ? h + 12 : h;
}

const double _kAltoFilaHora = 44.0;
const double _kAnchoListasHora = 320.0;

Future<String?> showHoraDialog(
  BuildContext context, {
  String valorActual = '',
  String titulo = 'Hora',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _HoraDialog(valorInicial: valorActual, titulo: titulo),
  );
}

class _HoraDialog extends StatefulWidget {
  const _HoraDialog({required this.valorInicial, required this.titulo});

  final String valorInicial;
  final String titulo;

  @override
  State<_HoraDialog> createState() => _HoraDialogState();
}

class _HoraDialogState extends State<_HoraDialog> {
  bool _teclado = false;
  late int _hora;
  late int _minuto;

  late final TextEditingController _controller = TextEditingController(
    text: bioParseHora(widget.valorInicial) ?? '',
  );
  late final FixedExtentScrollController _ruedaHora;
  late final FixedExtentScrollController _ruedaMinuto;
  late final FixedExtentScrollController _ruedaMeridiano;

  @override
  void initState() {
    super.initState();
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

  String get _valor => '${_hora.toString().padLeft(2, '0')}:'
      '${_minuto.toString().padLeft(2, '0')}';

  bool get _esPm => _hora >= 12;

  void _cambiarHora(int posicion) {
    setState(() => _hora = bioHora24(posicion + 1, _esPm));
  }

  void _cambiarMeridiano(int posicion) {
    setState(() => _hora = bioHora24(bioHora12(_hora), posicion == 1));
  }

  void _alternarModo() {
    setState(() {
      if (_teclado) {
        final escrito = bioParseHora(_controller.text);
        if (escrito != null) {
          _hora = int.parse(escrito.substring(0, 2));
          _minuto = int.parse(escrito.substring(3, 5));
        }
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _sincronizarRuedas(),
        );
      } else {
        _controller.text = _valor;
      }
      _teclado = !_teclado;
    });
  }

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
    final error = escrito.isNotEmpty && valor == null ? 'Hora no válida' : null;
    final puedeAceptar = _teclado ? valor != null : true;

    return AlertDialog(
      backgroundColor: context.dialogSurface,
      scrollable: true,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          const Icon(Icons.schedule_rounded, color: AppColors.iconAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.titulo,
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
              _teclado ? Icons.access_time_rounded : Icons.keyboard_alt_outlined,
              color: AppColors.iconAccent,
            ),
          ),
        ],
      ),
      content: Center(child: _teclado ? _campoTexto(error) : _listas()),
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
      width: _anchoListas(context),
      height: _kAltoFilaHora * 5,
      child: Row(
        children: [
          Expanded(
            flex: 84,
            child: _rueda(
              controller: _ruedaHora,
              itemCount: 12,
              textoDe: (i) => (i + 1).toString().padLeft(2, '0'),
              onSelected: _cambiarHora,
            ),
          ),
          _dosPuntos(),
          Expanded(
            flex: 84,
            child: _rueda(
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
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) textoDe,
    required ValueChanged<int> onSelected,
  }) {
    return SizedBox.expand(
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
      ),
    );
  }
}
