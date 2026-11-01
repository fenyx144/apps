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
    this.onTap,
    this.enabled = true,
    this.showIcon = true,
    this.iconColor,
  });

  final String label;
  final String value;
  final String placeholder;
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  final bool showIcon;
  final Color? iconColor;

  bool get _hasValue => value.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colors = context.formColors;
    final inputTheme = Theme.of(context).inputDecorationTheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: inputTheme.labelStyle?.copyWith(color: colors.labelMuted),
          floatingLabelStyle: inputTheme.floatingLabelStyle,
          suffixIcon: showIcon
              ? Icon(
                  icon,
                  color: iconColor ??
                      (enabled
                          ? colors.iconAccent
                          : colors.valuePlaceholder),
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
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

/// Galpón: mismo alto y estilo; abre diálogo de lista al tocar.
class EvidenciaGalponField extends StatelessWidget {
  const EvidenciaGalponField({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.enabled = true,
  });

  final String value;
  final List<String> options;
  final ValueChanged<String> onSelected;
  final bool enabled;

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;
    if (options.isEmpty) {
      showErrorToast(
        context,
        'No hay galpones para esta granja. Descargue catálogos desde el menú.',
      );
      return;
    }
    final sel = await showAppDialog<String>(
      context: context,
      builder: (ctx) => _GalponPickerDialog(options: options),
    );
    if (sel != null && sel.isNotEmpty) {
      onSelected(sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.formColors;
    return EvidenciaSelectField(
      label: 'Galpón',
      value: value,
      placeholder: 'Seleccione',
      icon: Icons.home_work_outlined,
      iconColor: colors.iconAccent,
      enabled: enabled,
      onTap: () => _openPicker(context),
    );
  }
}

class _GalponPickerDialog extends StatefulWidget {
  const _GalponPickerDialog({required this.options});

  final List<String> options;

  @override
  State<_GalponPickerDialog> createState() => _GalponPickerDialogState();
}

class _GalponPickerDialogState extends State<_GalponPickerDialog> {
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
            appDialogHeader(context, title: 'Seleccionar galpón'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar galpón...',
                  prefixIcon: Icon(Icons.search),
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
                            style: const TextStyle(
                              color: AppColors.textSelectedValue,
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
