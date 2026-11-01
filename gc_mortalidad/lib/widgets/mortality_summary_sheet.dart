import 'package:flutter/material.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/text_utils.dart';
import '../utils/theme_extensions.dart';
import 'detail_group_card.dart';
import 'poultry_icon.dart';

class MortalitySummarySheet {
  static Future<bool?> show({
    required BuildContext context,
    required MortalityType type,
    required Map<String, dynamic> data,
    bool isEditing = false,
    bool readOnly = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.98,
        builder: (context, scrollController) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final cardBg = context.cardColor;
          final headerBg = cardBg;
          final detalles = _detallesFromData(data);
          final showCausa = mortalityShowsCausaInSummary(
            type,
            origenAnalisis: data['origen_analisis']?.toString(),
          );
          final obsRaw = data['observaciones']?.toString() ?? '';
          // Cada "detalle" agregado en el diálogo (grupo M/H de la misma
          // sesión) se muestra como una tarjeta compacta de solo lectura.
          final grupos = MortalityDetailGroup.fromList(detalles);

          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : AppColors.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
                  decoration: BoxDecoration(
                    color: headerBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkBorder
                              : AppColors.borderLight,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(
                                  alpha: isDark ? 0.2 : 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const PoultryIcon(
                              size: 24,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              readOnly
                                  ? 'Resumen de Mortalidad'
                                  : 'Resumen — ${isEditing ? 'Edición' : 'Nuevo registro'}',
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.textSecondary,
                            ),
                            onPressed: () => Navigator.pop(context, false),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _section(
                          isDark: isDark,
                          title: 'Información general',
                          leading: const Icon(
                            Icons.info_outline,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _item(
                                    'Fecha',
                                    _formatDate(data['fecha']?.toString()),
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _item('Tipo', type.title, isDark: isDark),
                                ),
                              ],
                            ),
                            if (type == MortalityType.incubacion) ...[
                              const SizedBox(height: 12),
                              _item(
                                'F. Llegada',
                                _formatDate(data['fecha_llegada']?.toString()),
                                isDark: isDark,
                              ),
                            ],
                            if (type == MortalityType.transporte) ...[
                              const SizedBox(height: 12),
                              _item(
                                'Subtipo',
                                _labelSubtipo(data['subtipo_transporte']?.toString()),
                                isDark: isDark,
                              ),
                            ],
                            if (type == MortalityType.produccion) ...[
                              const SizedBox(height: 12),
                              _item(
                                'Tipo de registro',
                                data['origen_analisis']?.toString() ?? '—',
                                isDark: isDark,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _item(
                                    'Granja',
                                    data['granja_nombre']?.toString() ?? '—',
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _item(
                                    'Campaña',
                                    data['campania']?.toString() ?? '—',
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _item(
                                    'Galpón',
                                    data['galpon']?.toString() ?? '—',
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        _section(
                          isDark: isDark,
                          title: 'Detalle de aves',
                          leading: const PoultryIcon(
                            size: 20,
                            color: AppColors.primary,
                          ),
                          children: [
                            _totalLine(
                              isDark,
                              _totalMachos(data, detalles) +
                                  _totalHembras(data, detalles),
                            ),
                            const SizedBox(height: 10),
                            if (grupos.isEmpty)
                              Text(
                                (_totalMachos(data, detalles) +
                                            _totalHembras(data, detalles) ==
                                        0)
                                    ? 'Sin mortalidad'
                                    : 'Sin aves registradas',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            else
                              for (var i = 0; i < grupos.length; i++) ...[
                                if (i > 0) const SizedBox(height: 8),
                                DetailGroupCard(
                                  index: i + 1,
                                  group: grupos[i],
                                  showCausa: showCausa,
                                  isDespacho: type == MortalityType.despacho,
                                  desgloseEtapas:
                                      type == MortalityType.despacho,
                                  causaAlInicio: true,
                                  readOnly: true,
                                ),
                              ],
                          ],
                        ),
                        _section(
                          isDark: isDark,
                          title: 'Observaciones',
                          leading: const Icon(
                            Icons.notes_rounded,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkBackground
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                obsRaw.trim().isEmpty
                                    ? kSinObservaciones
                                    : capitalizeText(obsRaw),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: obsRaw.trim().isEmpty
                                      ? AppColors.textMuted
                                      : context.primaryTextColor,
                                  fontWeight: FontWeight.w500,
                                  fontStyle: obsRaw.trim().isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: cardBg,
                  ),
                  child: SafeArea(
                    child: readOnly
                        ? SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Cerrar',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text(
                                  'Cancelar',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Confirmar y Guardar',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  static List<MortalityDetail> _detallesFromData(Map<String, dynamic> data) {
    return MortalityDetail.listFromRecord(data);
  }

  static int _intField(dynamic value, [int fallback = 0]) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static int _totalMachos(
      Map<String, dynamic> data, List<MortalityDetail> detalles) {
    final fromDetails = MortalityDetail.totalMachos(detalles);
    if (fromDetails > 0) return fromDetails;
    return _intField(data['cant_machos']);
  }

  static int _totalHembras(
      Map<String, dynamic> data, List<MortalityDetail> detalles) {
    final fromDetails = MortalityDetail.totalHembras(detalles);
    if (fromDetails > 0) return fromDetails;
    return _intField(data['cant_hembras']);
  }

  /// Línea superior del total de aves.
  static Widget _totalLine(bool isDark, int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Total de aves',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
        ),
        Text(
          '$total',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  static Widget _section({
    required bool isDark,
    required String title,
    required Widget leading,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.borderLight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              leading,
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  static Widget _item(String label, String value, {bool isDark = false}) {
    final display = value.trim().isEmpty ? kSinObservaciones : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            display,
            style: TextStyle(
              fontSize: 13,
              color: display == kSinObservaciones
                  ? AppColors.textMuted
                  : (isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary),
              fontWeight: FontWeight.w600,
              fontStyle: display == kSinObservaciones
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  static String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '—';
    try {
      final parts = raw.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return raw;
  }

  static String _labelSubtipo(String? v) {
    switch (v) {
      case 'evento':
        return 'Evento';
      case 'transporte':
        return 'Transporte';
      default:
        return '—';
    }
  }
}
