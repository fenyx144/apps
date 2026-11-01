import 'package:flutter/material.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';

/// Campo tipo selector (borde, etiqueta verde, valor e icono celeste).
class EvidenciaSelectField extends StatelessWidget {
  const EvidenciaSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.icon,
    this.iconColor,
    this.showIcon = true,
    this.onTap,
    this.enabled = true,
  });

  final String label;
  final String value;
  final String placeholder;
  final IconData icon;
  final Color? iconColor;
  final bool showIcon;
  final VoidCallback? onTap;
  final bool enabled;

  bool get _hasValue => value.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.formColors;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppColors.radiusMd),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: showIcon
              ? Icon(
                  icon,
                  color: iconColor ?? colors.iconAccent,
                )
              : null,
        ),
        child: Text(
          _hasValue ? value : placeholder,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: _hasValue ? FontWeight.w700 : FontWeight.w500,
            color: _hasValue ? colors.valueSelected : colors.valuePlaceholder,
          ),
        ),
      ),
    );
  }
}

/// Galpón: mismo alto y estilo; abre diálogo multi-selección al tocar.
class EvidenciaGalponField extends StatelessWidget {
  const EvidenciaGalponField({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.enabled = true,
    this.label = 'Galpón',
  });

  final List<String> value;
  final List<String> options;
  final ValueChanged<List<String>> onSelected;
  final bool enabled;
  final String label;

  String get _displayValue {
    if (value.isEmpty) return '';
    if (options.isNotEmpty && value.length == options.length) {
      return 'Todos (${options.length})';
    }
    return value.join(', ');
  }

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;
    if (options.isEmpty) {
      showErrorToast(
        context,
        'No hay galpones para esta granja. Descargue catálogos desde el menú.',
      );
      return;
    }
    final sel = await showAppDialog<List<String>>(
      context: context,
      builder: (ctx) =>
          _GalponPickerDialog(options: options, selected: value),
    );
    if (sel != null) {
      onSelected(sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EvidenciaSelectField(
      label: label,
      value: _displayValue,
      placeholder: 'Seleccione',
      icon: Icons.home_work_outlined,
      enabled: enabled,
      onTap: () => _openPicker(context),
    );
  }
}

class _GalponPickerDialog extends StatefulWidget {
  const _GalponPickerDialog({required this.options, required this.selected});

  final List<String> options;
  final List<String> selected;

  @override
  State<_GalponPickerDialog> createState() => _GalponPickerDialogState();
}

class _GalponPickerDialogState extends State<_GalponPickerDialog> {
  late List<String> _selected;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
  }

  bool get _todosMarcados =>
      widget.options.isNotEmpty && _selected.length == widget.options.length;

  void _toggleTodos(bool checked) {
    setState(() {
      _selected = checked ? List<String>.from(widget.options) : [];
    });
  }

  void _toggle(String code, bool checked) {
    setState(() {
      if (checked) {
        if (!_selected.contains(code)) _selected.add(code);
      } else {
        _selected.remove(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _filter.toLowerCase();
    final filtered = widget.options
        .where((o) => q.isEmpty || o.toLowerCase().contains(q))
        .toList();

    return Dialog(
      backgroundColor: context.dialogSurface,
      insetPadding: context.dialogInsetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 24,
        height: MediaQuery.of(context).size.height * 0.58,
        child: Column(
          children: [
            appDialogHeader(context, title: 'Seleccionar galpones'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                style: TextStyle(color: context.textThemePrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar galpón...',
                  hintStyle: TextStyle(color: context.textThemeMuted),
                  prefixIcon: Icon(
                    Icons.search,
                    color: context.textThemeMuted,
                  ),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Todos',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: context.textThemePrimary,
                ),
              ),
              value: _todosMarcados,
              onChanged: (v) => _toggleTodos(v ?? false),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'Sin resultados',
                        style: TextStyle(color: context.textThemeMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final code = filtered[i];
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            code,
                            style: TextStyle(
                              color: context.textThemePrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          value: _selected.contains(code),
                          onChanged: (v) => _toggle(code, v ?? false),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Aceptar',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
