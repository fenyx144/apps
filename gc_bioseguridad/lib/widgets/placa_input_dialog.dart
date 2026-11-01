import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../screens/placa_camera_screen.dart';
import '../services/plan_visitas_service.dart';
import '../utils/placa_ocr_parser.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Captura la placa física del vehículo (ej. ABC-123), no código de barras.
class PlacaInputDialog {
  PlacaInputDialog._();

  static const int minCaracteres = 5;

  /// Cámara + ML Kit; desde ahí se puede pasar a teclado.
  static Future<String?> capture(BuildContext context) {
    return PlacaCameraScreen.open(context);
  }

  /// Solo teclado (desde el ícono en la pantalla de cámara).
  static Future<String?> show(
    BuildContext context, {
    String initial = '',
  }) {
    return showDialog<String?>(
      context: context,
      builder: (ctx) => _PlacaInputDialogBody(initial: initial),
    );
  }
}

class _PlacaInputDialogBody extends StatefulWidget {
  const _PlacaInputDialogBody({this.initial = ''});

  final String initial;

  @override
  State<_PlacaInputDialogBody> createState() => _PlacaInputDialogBodyState();
}

class _PlacaInputDialogBodyState extends State<_PlacaInputDialogBody> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _aceptar() {
    if (_formKey.currentState?.validate() ?? false) {
      final legible = PlacaOcrParser.paraCampo(_controller.text);
      if (PlanDescarga.normPlaca(legible).length <
          PlacaInputDialog.minCaracteres) {
        return;
      }
      Navigator.of(context).pop(legible);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      title: const Text('Placa del vehículo'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\- ]')),
          ],
          decoration: const InputDecoration(
            hintText: 'ABC-123',
            labelText: 'Placa',
          ),
          validator: (v) {
            final norm = PlanDescarga.normPlaca(v ?? '');
            if (norm.length < PlacaInputDialog.minCaracteres) {
              return 'Mínimo ${PlacaInputDialog.minCaracteres} caracteres (letras o números).';
            }
            return null;
          },
          onFieldSubmitted: (_) => _aceptar(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDark,
          ),
          onPressed: _aceptar,
          child: const Text('Aceptar'),
        ),
      ],
    );
  }
}
