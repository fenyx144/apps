import 'package:flutter/material.dart';
import '../models/motivo_mortalidad.dart';
import '../utils/constants.dart';
import 'mortality_counter_field.dart';
import 'styled_select_field.dart';
import 'searchable_select_dialog.dart';

class MaleFemaleMortalitySection extends StatelessWidget {
  final int cantMachos;
  final int cantHembras;
  final String? causaMachos;
  final String? causaHembras;
  final String? causaMachosNombre;
  final String? causaHembrasNombre;
  final List<MotivoMortalidad> motivos;
  final ValueChanged<int> onCantMachosChanged;
  final ValueChanged<int> onCantHembrasChanged;
  final ValueChanged<MotivoMortalidad?> onCausaMachosChanged;
  final ValueChanged<MotivoMortalidad?> onCausaHembrasChanged;
  final String? errorMachos;
  final String? errorHembras;

  const MaleFemaleMortalitySection({
    super.key,
    required this.cantMachos,
    required this.cantHembras,
    required this.causaMachos,
    required this.causaHembras,
    required this.causaMachosNombre,
    required this.causaHembrasNombre,
    required this.motivos,
    required this.onCantMachosChanged,
    required this.onCantHembrasChanged,
    required this.onCausaMachosChanged,
    required this.onCausaHembrasChanged,
    this.errorMachos,
    this.errorHembras,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SexBlock(
          icon: Icons.male_rounded,
          label: 'Machos',
          accent: AppColors.maleDark,
          tint: AppColors.maleTint,
          cantidad: cantMachos,
          causaNombre: causaMachosNombre,
          causaError: errorMachos,
          selectedCausa: causaMachos,
          motivos: motivos,
          onCantChanged: onCantMachosChanged,
          onCausaChanged: onCausaMachosChanged,
        ),
        const SizedBox(height: 12),
        _SexBlock(
          icon: Icons.female_rounded,
          label: 'Hembras',
          accent: AppColors.femaleDark,
          tint: AppColors.femaleTint,
          cantidad: cantHembras,
          causaNombre: causaHembrasNombre,
          causaError: errorHembras,
          selectedCausa: causaHembras,
          motivos: motivos,
          onCantChanged: onCantHembrasChanged,
          onCausaChanged: onCausaHembrasChanged,
        ),
      ],
    );
  }
}

class _SexBlock extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final Color tint;
  final int cantidad;
  final String? causaNombre;
  final String? causaError;
  final String? selectedCausa;
  final List<MotivoMortalidad> motivos;
  final ValueChanged<int> onCantChanged;
  final ValueChanged<MotivoMortalidad?> onCausaChanged;

  const _SexBlock({
    required this.icon,
    required this.label,
    required this.accent,
    required this.tint,
    required this.cantidad,
    required this.causaNombre,
    required this.causaError,
    required this.selectedCausa,
    required this.motivos,
    required this.onCantChanged,
    required this.onCausaChanged,
  });

  Future<void> _openCausaDialog(BuildContext context) async {
    if (cantidad <= 0) return;
    await showSearchableSelectDialog<MotivoMortalidad>(
      context: context,
      title: 'Causa — $label',
      icon: Icons.medical_information_outlined,
      items: motivos,
      emptyMessage: 'No hay causas cargadas.\nUse Descargar en el menú lateral.',
      getLabel: (m) => m.nombre,
      selectedValue: selectedCausa,
      getValue: (m) => m.codigo,
      onSelected: (code) {
        if (code == null) return;
        MotivoMortalidad? found;
        for (final m in motivos) {
          if (m.codigo == code) {
            found = m;
            break;
          }
        }
        onCausaChanged(found ?? MotivoMortalidad(codigo: code, nombre: code));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? accent.withValues(alpha: 0.12) : tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          MortalityCounterField(value: cantidad, onChanged: onCantChanged),
          const SizedBox(height: 12),
          StyledSelectField(
            label: 'Causa de mortalidad',
            value: causaNombre,
            placeholder: cantidad > 0 ? 'Seleccionar causa...' : 'Indique cantidad primero',
            icon: Icons.medical_information_outlined,
            errorText: causaError,
            enabled: cantidad > 0,
            onTap: () => _openCausaDialog(context),
          ),
        ],
      ),
    );
  }
}
