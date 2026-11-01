import 'package:flutter/material.dart';

import '../services/catalog_service.dart';
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
    this.maxLines = 2,
    this.hint,
  });

  final String label;
  final String value;
  final String placeholder;
  final IconData icon;
  final Color? iconColor;
  final bool showIcon;
  final VoidCallback? onTap;
  final bool enabled;

  /// Renglones del valor. Los campos de nombre largo (la granja) van con uno
  /// solo y puntos suspensivos, para que el alto no se estire y empuje a los
  /// que van al lado.
  final int maxLines;

  /// Aclaración corta bajo el campo. Se usa en los campos de solo lectura
  /// («Lo define el menú») para que no parezcan un selector que no responde.
  final String? hint;

  bool get _hasValue => value.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.formColors;
    final field = InkWell(
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
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: _hasValue ? FontWeight.w700 : FontWeight.w500,
            color: _hasValue ? colors.valueSelected : colors.valuePlaceholder,
          ),
        ),
      ),
    );
    if (hint == null) return field;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field,
        Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            hint!,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: context.textThemeMuted,
            ),
          ),
        ),
      ],
    );
  }
}

/// Resultado del diálogo multi-galpón (catálogo + opción «Otro» aparte).
class GalponMultiPickResult {
  const GalponMultiPickResult({
    required this.seleccionados,
    required this.otro,
  });

  final List<String> seleccionados;
  final bool otro;
}

/// Galpón: mismo alto y estilo; abre diálogo multi-selección al tocar.
class EvidenciaGalponField extends StatelessWidget {
  const EvidenciaGalponField({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.incluirOtro = true,
    this.otroSeleccionado = false,
    this.otroEtiqueta = 'Otro',
    this.textoOtro = '',
    this.enabled = true,
  });

  final List<String> value;
  final List<String> options;
  final ValueChanged<GalponMultiPickResult> onSelected;
  final bool incluirOtro;
  final bool otroSeleccionado;
  final String otroEtiqueta;
  final String textoOtro;
  final bool enabled;

  String get _displayValue {
    final parts = <String>[...value];
    if (incluirOtro && otroSeleccionado) {
      final t = textoOtro.trim();
      parts.add(t.isNotEmpty ? t : otroEtiqueta);
    }
    if (parts.isEmpty) return '';
    if (options.isNotEmpty &&
        !otroSeleccionado &&
        value.length == options.length) {
      return 'Todos (${options.length})';
    }
    return parts.join(', ');
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
    final sel = await showAppDialog<GalponMultiPickResult>(
      context: context,
      builder: (ctx) => _GalponPickerDialog(
        options: options,
        selected: value,
        incluirOtro: incluirOtro,
        otroSeleccionado: otroSeleccionado,
        otroEtiqueta: otroEtiqueta,
      ),
    );
    if (sel != null) {
      onSelected(sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EvidenciaSelectField(
      label: 'Galpón',
      value: _displayValue,
      placeholder: 'Seleccione',
      icon: Icons.home_work_outlined,
      enabled: enabled,
      onTap: () => _openPicker(context),
    );
  }
}

class _GalponPickerDialog extends StatefulWidget {
  const _GalponPickerDialog({
    required this.options,
    required this.selected,
    this.incluirOtro = true,
    this.otroSeleccionado = false,
    this.otroEtiqueta = 'Otro',
  });

  final List<String> options;
  final List<String> selected;
  final bool incluirOtro;
  final bool otroSeleccionado;
  final String otroEtiqueta;

  @override
  State<_GalponPickerDialog> createState() => _GalponPickerDialogState();
}

class _GalponPickerDialogState extends State<_GalponPickerDialog> {
  late List<String> _selected;
  late bool _otro;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.selected);
    _otro = widget.otroSeleccionado;
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
            if (widget.incluirOtro) ...[
              CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  widget.otroEtiqueta,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: context.textThemePrimary,
                  ),
                ),
                value: _otro,
                onChanged: (v) => setState(() => _otro = v ?? false),
              ),
            ],
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
                    onPressed: () {
                      if (_selected.isEmpty && !_otro) {
                        showErrorToast(
                          context,
                          'Marque al menos un galpón o «${widget.otroEtiqueta}».',
                        );
                        return;
                      }
                      Navigator.pop(
                        context,
                        GalponMultiPickResult(
                          seleccionados: List<String>.from(_selected),
                          otro: _otro,
                        ),
                      );
                    },
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

/// Un galpón del catálogo o la fila «Otro» (texto aparte en el formulario).
class EvidenciaGalponSingleField extends StatelessWidget {
  const EvidenciaGalponSingleField({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.incluirOtro = true,
    this.otroEtiqueta = 'Otro',
    this.textoOtro = '',
    this.enabled = true,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final bool incluirOtro;
  final String otroEtiqueta;
  final String textoOtro;
  final bool enabled;

  String get _displayValue {
    if (CatalogService.esOtro(value)) {
      final t = textoOtro.trim();
      return t.isNotEmpty ? t : otroEtiqueta;
    }
    return value;
  }

  List<String> get _dialogOptions {
    final out = List<String>.from(options);
    if (incluirOtro && !out.any(CatalogService.esOtro)) {
      out.add(otroEtiqueta);
    }
    return out;
  }

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;
    final opts = _dialogOptions;
    if (opts.isEmpty) {
      onSelected(otroEtiqueta);
      return;
    }
    if (opts.length == 1) {
      onSelected(opts.first);
      return;
    }
    final sel = await showAppDialog<String>(
      context: context,
      builder: (ctx) => _GalponSinglePickerDialog(options: opts),
    );
    if (sel != null && sel.isNotEmpty) {
      onSelected(sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EvidenciaSelectField(
      label: 'Galpón',
      value: _displayValue,
      placeholder: 'Seleccione',
      icon: Icons.home_work_outlined,
      enabled: enabled,
      onTap: () => _openPicker(context),
    );
  }
}

class _GalponSinglePickerDialog extends StatefulWidget {
  const _GalponSinglePickerDialog({required this.options});

  final List<String> options;

  @override
  State<_GalponSinglePickerDialog> createState() =>
      _GalponSinglePickerDialogState();
}

class _GalponSinglePickerDialogState extends State<_GalponSinglePickerDialog> {
  String _filter = '';

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
        height: MediaQuery.of(context).size.height * 0.48,
        child: Column(
          children: [
            appDialogHeader(context, title: 'Galpón'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                style: TextStyle(color: context.textThemePrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar…',
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
                        return ListTile(
                          title: Text(
                            code,
                            style: TextStyle(
                              color: context.textThemePrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, code),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
