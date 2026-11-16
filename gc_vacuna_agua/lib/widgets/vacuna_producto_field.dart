import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import 'evidencia_select_field.dart';

/// Nombre de vacuna: se elige del maestro de productos (la línea de vacunas),
/// igual que Planificación al armar un programa.
/// No se escribe a mano: el maestro (`mitm`) es el que manda el nombre, así que
/// el informe muestra siempre la misma descripción para el mismo producto y no
/// conviven «Newcastle», «new castle» y «NC» como si fueran tres vacunas.
class VacunaProductoField extends StatelessWidget {
  const VacunaProductoField({
    super.key,
    required this.value,
    required this.options,
    required this.onSelected,
    this.enabled = true,
  });

  /// Descripción de la vacuna elegida ('' cuando todavía no se eligió).
  final String value;

  /// Productos del catálogo: `codigo` y `descripcion`.
  final List<Map<String, String>> options;

  final ValueChanged<String> onSelected;
  final bool enabled;

  Future<void> _openPicker(BuildContext context) async {
    if (!enabled) return;
    if (options.isEmpty) {
      showErrorToast(
        context,
        'No hay vacunas en el catálogo. Descargue catálogos desde el menú.',
      );
      return;
    }
    final sel = await showAppDialog<String>(
      context: context,
      builder: (ctx) => _VacunaPickerDialog(options: options, selected: value),
    );
    if (sel != null) {
      onSelected(sel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return EvidenciaSelectField(
      label: 'Nombre de vacuna',
      value: value,
      placeholder: 'Seleccione',
      icon: Icons.vaccines_outlined,
      enabled: enabled,
      onTap: () => _openPicker(context),
    );
  }
}

/// Lista buscable de vacunas: se toca una y se elige.
class _VacunaPickerDialog extends StatefulWidget {
  const _VacunaPickerDialog({required this.options, required this.selected});

  final List<Map<String, String>> options;
  final String selected;

  @override
  State<_VacunaPickerDialog> createState() => _VacunaPickerDialogState();
}

class _VacunaPickerDialogState extends State<_VacunaPickerDialog> {
  String _filter = '';

  /// Texto que se busca: código y descripción juntos, para que sirva tanto
  /// escribir el nombre como pegar el código del frasco.
  String _texto(Map<String, String> o) =>
      '${o['codigo'] ?? ''} ${o['descripcion'] ?? ''}'.toLowerCase();

  @override
  Widget build(BuildContext context) {
    final q = _filter.trim().toLowerCase();
    final filtered = widget.options
        .where((o) => q.isEmpty || _texto(o).contains(q))
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
            appDialogHeader(context, title: 'Seleccionar vacuna'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                style: TextStyle(color: context.textThemePrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre o código...',
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
                        final item = filtered[i];
                        final codigo = (item['codigo'] ?? '').trim();
                        final descripcion = (item['descripcion'] ?? '').trim();
                        final marcado = descripcion == widget.selected;
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            marcado
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            color: marcado
                                ? AppColors.primary
                                : context.textThemeMuted,
                          ),
                          title: Text(
                            descripcion.isEmpty ? codigo : descripcion,
                            style: TextStyle(
                              color: context.textThemePrimary,
                              fontWeight: marcado
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                          subtitle: codigo.isEmpty
                              ? null
                              : Text(
                                  codigo,
                                  style: TextStyle(
                                    color: context.textThemeMuted,
                                    fontSize: 12,
                                  ),
                                ),
                          onTap: () => Navigator.pop(
                            context,
                            descripcion.isEmpty ? codigo : descripcion,
                          ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
