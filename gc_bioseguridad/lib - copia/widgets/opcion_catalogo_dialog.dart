import 'package:flutter/material.dart';

import '../services/catalog_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Opción de catálogo elegida en [showOpcionCatalogoDialog].
///
/// Son tres datos y no uno: el texto que se guarda ([valor]), el código del
/// catálogo del que salió ([codigo], vacío si se escribió a mano) y el
/// complemento de las opciones que lo piden ([detalle], ver «A la altura del
/// galpón»). El código se conserva porque los formularios deciden con él (p. ej.
/// la garita es `1` y solo ella muestra el filtro), y el texto libre no tiene
/// código.
class OpcionCatalogo {
  const OpcionCatalogo({
    required this.valor,
    this.codigo = '',
    this.detalle = '',
  });

  /// Lo que se guarda: la etiqueta del catálogo o, si se eligió «Otros», el
  /// texto escrito a mano.
  final String valor;

  /// Código del catálogo (`''` cuando viene de «Otros»).
  final String codigo;

  /// Complemento escrito para las opciones que piden un dato aparte.
  final String detalle;

  /// Nada elegido todavía.
  static const OpcionCatalogo vacia = OpcionCatalogo(valor: '');

  bool get estaVacia => valor.trim().isEmpty;

  /// Texto del campo del formulario: «valor» o «valor · detalle» cuando la
  /// opción pide complemento.
  String get etiqueta {
    final d = detalle.trim();
    return d.isEmpty ? valor : '$valor · $d';
  }
}

/// Pide una opción del catálogo y, cuando hace falta, el texto que la completa.
///
/// Cubre dos casos que el selector simple ([showBioOptionsSheet]) dejaba
/// afuera:
///
///  - **«Otros»**: la fila del catálogo (o una que se agrega acá cuando el
///    servidor todavía no la trae) que obliga a escribir el valor, porque no
///    está en la lista. Al elegirla se pide el texto en un campo.
///  - **Opciones con complemento**: las que [pideDetalle] marque (p. ej. «A la
///    altura del galpón») piden un segundo dato, que viaja en
///    [OpcionCatalogo.detalle].
///
/// Devuelve `null` si se cancela.
Future<OpcionCatalogo?> showOpcionCatalogoDialog({
  required BuildContext context,
  required String title,
  required List<Map<String, String>> opciones,
  required OpcionCatalogo actual,
  IconData icon = Icons.list_alt_rounded,

  /// Etiqueta de la fila que pide el texto a mano. Se agrega al final cuando el
  /// catálogo no la trae y [agregarOtro] es `true`.
  String etiquetaOtro = 'Otros',
  String otroLabel = 'Especifique',
  String? otroHint,
  int otroMaxLength = 40,

  /// Opciones que además piden el complemento de [detalleLabel].
  bool Function(String descripcion)? pideDetalle,
  String detalleLabel = 'Detalle',
  String? detalleHint,
  int detalleMaxLength = 40,

  /// Agrega la fila «Otros» cuando el catálogo no la envía.
  bool agregarOtro = true,
}) {
  return showDialog<OpcionCatalogo>(
    context: context,
    builder: (_) => _OpcionCatalogoDialog(
      title: title,
      opciones: opciones,
      actual: actual,
      icon: icon,
      etiquetaOtro: etiquetaOtro,
      otroLabel: otroLabel,
      otroHint: otroHint,
      otroMaxLength: otroMaxLength,
      pideDetalle: pideDetalle,
      detalleLabel: detalleLabel,
      detalleHint: detalleHint,
      detalleMaxLength: detalleMaxLength,
      agregarOtro: agregarOtro,
    ),
  );
}

class _OpcionCatalogoDialog extends StatefulWidget {
  const _OpcionCatalogoDialog({
    required this.title,
    required this.opciones,
    required this.actual,
    required this.icon,
    required this.etiquetaOtro,
    required this.otroLabel,
    required this.otroHint,
    required this.otroMaxLength,
    required this.pideDetalle,
    required this.detalleLabel,
    required this.detalleHint,
    required this.detalleMaxLength,
    required this.agregarOtro,
  });

  final String title;
  final List<Map<String, String>> opciones;
  final OpcionCatalogo actual;
  final IconData icon;
  final String etiquetaOtro;
  final String otroLabel;
  final String? otroHint;
  final int otroMaxLength;
  final bool Function(String descripcion)? pideDetalle;
  final String detalleLabel;
  final String? detalleHint;
  final int detalleMaxLength;
  final bool agregarOtro;

  @override
  State<_OpcionCatalogoDialog> createState() => _OpcionCatalogoDialogState();
}

class _OpcionCatalogoDialogState extends State<_OpcionCatalogoDialog> {
  /// Opciones a mostrar, con «Otros» agregado si el catálogo no lo trae.
  late final List<Map<String, String>> _opciones = _conOtros();

  /// Descripción elegida (`''` = sin elegir).
  late String _seleccion = _seleccionInicial();

  /// Texto de «Otros». Se precarga con lo escrito a mano para no perderlo al
  /// reabrir el diálogo.
  late final TextEditingController _otroCtrl = TextEditingController(
    text: _esTextoLibre(widget.actual.valor) ? widget.actual.valor : '',
  );

  /// Complemento de la opción que lo pide.
  late final TextEditingController _detalleCtrl = TextEditingController(
    text: widget.actual.detalle,
  );

  bool _esTextoLibre(String valor) {
    final v = valor.trim();
    if (v.isEmpty) return false;
    final enCatalogo = widget.opciones.any(
      (o) => (o['descripcion'] ?? '').trim() == v,
    );
    return !enCatalogo || CatalogService.esOtro(v);
  }

  String _seleccionInicial() {
    if (widget.actual.estaVacia) return '';
    return _esTextoLibre(widget.actual.valor) ? widget.etiquetaOtro : widget.actual.valor.trim();
  }

  List<Map<String, String>> _conOtros() {
    final base = widget.opciones;
    if (!widget.agregarOtro) return base;
    final yaEsta = base.any(
      (o) => CatalogService.esOtro((o['descripcion'] ?? '').trim()),
    );
    if (yaEsta) return base;
    return [
      ...base,
      {'codigo': '0', 'descripcion': widget.etiquetaOtro},
    ];
  }

  Map<String, String>? get _opcionElegida {
    for (final o in _opciones) {
      if ((o['descripcion'] ?? '').trim() == _seleccion) return o;
    }
    return null;
  }

  /// `true` cuando la opción elegida es «Otros».
  bool get _esOtro => CatalogService.esOtro(_seleccion);

  /// `true` cuando la opción elegida pide el complemento.
  bool get _pideDetalle =>
      !_esOtro &&
      _seleccion.isNotEmpty &&
      (widget.pideDetalle?.call(_seleccion) ?? false);

  /// Lo que se guarda: la etiqueta o el texto escrito.
  String get _valor => _esOtro ? _otroCtrl.text.trim() : _seleccion;

  bool get _puedeAceptar {
    if (_seleccion.isEmpty) return false;
    if (_esOtro) return _otroCtrl.text.trim().isNotEmpty;
    if (_pideDetalle) return _detalleCtrl.text.trim().isNotEmpty;
    return true;
  }

  @override
  void dispose() {
    _otroCtrl.dispose();
    _detalleCtrl.dispose();
    super.dispose();
  }

  void _aceptar() {
    Navigator.pop(
      context,
      OpcionCatalogo(
        valor: _valor,
        codigo: _esOtro ? '' : (_opcionElegida?['codigo'] ?? ''),
        detalle: _pideDetalle ? _detalleCtrl.text.trim() : '',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          Icon(widget.icon, color: AppColors.iconAccent, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.textThemePrimary,
              ),
            ),
          ),
        ],
      ),
      // Alto fijo: las listas de catálogo tienen varias filas y sin tope el
      // diálogo se saldría de la pantalla.
      content: SizedBox(
        width: double.maxFinite,
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _opcionesList()),
            // «Otros» es una fila más de la lista: al elegirla se pide el texto,
            // porque el valor no está en el catálogo.
            if (_esOtro) ...[
              const SizedBox(height: 10),
              _campoOtro(),
            ],
            // Opciones que piden un complemento (p. ej. «A la altura del
            // galpón»): un segundo campo con el dato adicional.
            if (_pideDetalle) ...[
              const SizedBox(height: 10),
              _campoDetalle(),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _puedeAceptar ? _aceptar : null,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }

  Widget _opcionesList() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
      ),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: _opciones.length,
        itemBuilder: (context, i) {
          final descripcion = _opciones[i]['descripcion'] ?? '';
          final elegida = descripcion == _seleccion;
          return InkWell(
            onTap: () => setState(() => _seleccion = descripcion),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: elegida
                  ? AppColors.primary.withValues(alpha: 0.10)
                  : Colors.transparent,
              child: Row(
                children: [
                  Icon(
                    elegida
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 18,
                    color: elegida
                        ? AppColors.primary
                        : context.textThemeMuted.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      descripcion,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: elegida ? FontWeight.w800 : FontWeight.w500,
                        color: elegida
                            ? AppColors.primaryDark
                            : context.textThemePrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _campoOtro() {
    return TextField(
      controller: _otroCtrl,
      autofocus: true,
      maxLength: widget.otroMaxLength,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: context.textThemePrimary,
      ),
      decoration: InputDecoration(
        labelText: widget.otroLabel,
        hintText: widget.otroHint,
        counterText: '',
      ),
    );
  }

  Widget _campoDetalle() {
    return TextField(
      controller: _detalleCtrl,
      autofocus: true,
      maxLength: widget.detalleMaxLength,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: context.textThemePrimary,
      ),
      decoration: InputDecoration(
        labelText: widget.detalleLabel,
        hintText: widget.detalleHint,
        counterText: '',
      ),
    );
  }
}
