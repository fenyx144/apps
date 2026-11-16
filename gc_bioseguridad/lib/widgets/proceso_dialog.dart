import 'package:flutter/material.dart';

import '../services/catalog_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Pide el proceso del proveedor: una fila del catálogo o el texto de «Otro».
/// Es la lista de proveedores que envía el servidor
/// (`bio_areaproveedor_catalogo()['PROVEEDOR']`), la misma que la web usa para
/// planificar. Lo elegido se guarda en `san_fact_ingresogranja_cab.motivo`.
Future<String?> showProcesoDialog({
  required BuildContext context,
  required String actual,
  required List<Map<String, String>> procesos,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ProcesoDialog(actual: actual, procesos: procesos),
  );
}

class _ProcesoDialog extends StatefulWidget {
  const _ProcesoDialog({required this.actual, required this.procesos});

  final String actual;
  final List<Map<String, String>> procesos;

  @override
  State<_ProcesoDialog> createState() => _ProcesoDialogState();
}

class _ProcesoDialogState extends State<_ProcesoDialog> {
  /// Descripción elegida de la lista (`''` = sin elegir).
  late String _seleccion = widget.actual.trim();

  /// Texto de «Otro». Se precarga con lo elegido para que reabrir el diálogo
  /// sobre un valor escrito a mano no lo pierda.
  late final TextEditingController _otroController = TextEditingController(
    text: CatalogService.esOtro(widget.actual) ? widget.actual : '',
  );

  /// `true` cuando la fila «Otro» es la elegida.
  bool get _esOtro => CatalogService.esOtro(_seleccion);

  /// Lo que se devuelve: la etiqueta o el texto escrito.
  String get _valor => _esOtro ? _otroController.text.trim() : _seleccion;

  bool get _puedeAceptar =>
      _seleccion.isNotEmpty && (!_esOtro || _otroController.text.trim().isNotEmpty);

  @override
  void dispose() {
    _otroController.dispose();
    super.dispose();
  }

  void _aceptar() => Navigator.pop(context, _valor);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      title: Row(
        children: [
          const Icon(
            Icons.account_tree_rounded,
            color: AppColors.iconAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Proceso',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: context.textThemePrimary,
            ),
          ),
        ],
      ),
      // Alto fijo: la lista tiene quince filas y sin tope el diálogo se saldría
      // de la pantalla.
      content: SizedBox(
        width: double.maxFinite,
        height: 340,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _opcionesList()),
            // «Otro» es una fila más de la lista: al elegirla se pide el texto,
            // porque el proceso no está en el catálogo.
            if (_esOtro) ...[
              const SizedBox(height: 10),
              _campoOtro(),
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
        itemCount: widget.procesos.length,
        itemBuilder: (context, i) {
          final descripcion = widget.procesos[i]['descripcion'] ?? '';
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
                    elegida ? Icons.check_circle_rounded : Icons.circle_outlined,
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
      controller: _otroController,
      autofocus: true,
      maxLength: 60,
      textCapitalization: TextCapitalization.sentences,
      onChanged: (_) => setState(() {}),
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: context.textThemePrimary,
      ),
      decoration: const InputDecoration(
        labelText: 'Especifique',
        hintText: 'Escriba el proceso',
        counterText: '',
      ),
    );
  }
}
