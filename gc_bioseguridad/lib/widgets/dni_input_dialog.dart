import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/constants.dart';
import '../utils/documento_persona.dart';
import '../utils/dni_utils.dart';
import '../utils/theme_colors.dart';

/// DNI o carné de extranjería sin escáner.
class DniInputDialog {
  DniInputDialog._();

  static Future<String?> show(BuildContext context) {
    return showDialog<String?>(
      context: context,
      builder: (ctx) => const _DniInputDialogBody(),
    );
  }
}

class _DniInputDialogBody extends StatefulWidget {
  const _DniInputDialogBody();

  @override
  State<_DniInputDialogBody> createState() => _DniInputDialogBodyState();
}

class _DniInputDialogBodyState extends State<_DniInputDialogBody> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _aceptar() {
    if (_formKey.currentState?.validate() ?? false) {
      final doc = DocumentoPersona.parse(_controller.text) ??
          DocumentoPersona.parse(DniCodeParser.parse(_controller.text));
      Navigator.of(context).pop(doc?.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.dialogSurface,
      title: const Text('DNI o carné de extranjería'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.text,
          maxLength: DocumentoPersona.maxLength,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\s-]')),
          ],
          decoration: const InputDecoration(
            labelText: 'DNI o carné',
            hintText: '12345678 o CEE (9 dígitos)',
            counterText: '',
          ),
          validator: (v) {
            final doc = DocumentoPersona.parse(v) ?? DocumentoPersona.parse(
              DniCodeParser.parse(v),
            );
            if (doc == null) {
              return 'DNI (8 dígitos) o CEE (6–15 caracteres).';
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
