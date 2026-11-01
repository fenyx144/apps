import 'package:flutter/material.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/theme_extensions.dart';
import 'detail_group_card.dart';

class MortalityDetailsSection extends StatelessWidget {
  final List<MortalityDetail> detalles;
  final MortalityType type;

  /// Tipos/orígenes que admiten "registro en cero".
  /// Producción con origen Necropsia/Laboratorio siempre exige aves.
  final bool permiteRegistroCero;

  /// El usuario marcó explícitamente que no hubo mortalidad.
  final bool sinMortalidad;

  final String? agregarError;
  final VoidCallback onAdd;
  final void Function(MortalityDetailGroup group) onEditGroup;
  final void Function(String grupoId) onDeleteGroup;

  const MortalityDetailsSection({
    super.key,
    required this.detalles,
    required this.type,
    required this.onAdd,
    required this.onEditGroup,
    required this.onDeleteGroup,
    this.permiteRegistroCero = true,
    this.sinMortalidad = false,
    this.agregarError,
  });

  bool get _showCausa => mortalityShowsCausaInSummary(type);

  bool get _hasDetalles => detalles.any((d) => d.hasContent);

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;
    final groups = MortalityDetailGroup.fromList(detalles);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_hasDetalles)
          ...groups.asMap().entries.map(
                (e) => Padding(
                  padding: EdgeInsets.only(
                      bottom: e.key < groups.length - 1 ? 6 : 0),
                  child: DetailGroupCard(
                    index: e.key + 1,
                    group: e.value,
                    showCausa: _showCausa,
                    isDespacho: type == MortalityType.despacho,
                    onEdit: () => onEditGroup(e.value),
                    onDelete: () => onDeleteGroup(e.value.grupoId),
                  ),
                ),
              )
        else
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: agregarError != null
                    ? AppColors.error
                    : AppColors.primary.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 32,
                  color: isDark ? Colors.white38 : Colors.grey.shade400,
                ),
                const SizedBox(height: 8),
                if (sinMortalidad) ...[
                  Text(
                    'Sin mortalidad',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Puedes agregar observaciones y fotos\ncon el botón +, o guardar el registro así.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ] else if (permiteRegistroCero) ...[
                  Text(
                    'Sin detalles registrados',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                  /*const SizedBox(height: 4),
                  Text(
                    type == MortalityType.despacho
                        ? 'Marca “Sin mortalidad” si el despacho no tuvo bajas,\no pulse + para registrar etapas y fotos'
                        : 'Marca “Sin mortalidad” si no murieron aves,\no pulse + para agregar un detalle',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),*/
                ] else ...[
                  Text(
                    'Sin detalles registrados',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    type == MortalityType.despacho
                        ? 'Pulse + para registrar las etapas del proceso y fotos'
                        : (mortalityShowsCausa(type)
                            ? 'Pulse + para agregar cantidad, causa y fotos'
                            : 'Pulse + para agregar cantidad y fotos'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: Icon(Icons.add_rounded, color: type.accentColor),
            label: Text(
              'Agregar detalle',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: type.accentColor,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: type.accentColor.withValues(alpha: 0.5)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        AppFieldError(agregarError),
      ],
    );
  }
}
