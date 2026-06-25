import 'dart:io';

import 'package:flutter/material.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
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
          final cardBg = isDark ? AppColors.darkCard : AppColors.cardBackground;
          final headerBg = isDark ? AppColors.darkSurface : Colors.white;
          final detalles = _detallesFromData(data);
          final showCausa = mortalityShowsCausaInSummary(
            type,
            origenAnalisis: data['origen_analisis']?.toString(),
          );

          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkBackground : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                  decoration: BoxDecoration(
                    color: headerBg,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.textMuted.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.iconAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const PoultryIcon(
                              size: 24,
                              color: AppColors.iconAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              readOnly ? 'Resumen de Mortalidad' : 'Resumen — ${
                                isEditing ? 'Edición' : 'Nuevo registro'}',
                              style: TextStyle(
                                color: isDark ? Colors.white : AppColors.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: isDark ? Colors.white70 : AppColors.textSecondary,
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
                          cardBg: cardBg,
                          title: 'Información general',
                          leading: Icon(
                            Icons.info_outline,
                            color: AppColors.iconAccent,
                            size: 20,
                          ),
                          children: [
                            _item('Tipo', type.title),
                            const SizedBox(height: 12),
                            if (type == MortalityType.transporte) ...[
                              _item(
                                'Subtipo',
                                _labelSubtipo(data['subtipo_transporte']?.toString()),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (type == MortalityType.produccion) ...[
                              _item(
                                'Tipo de registro',
                                data['origen_analisis']?.toString() ?? '—',
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (type == MortalityType.incubacion) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _item(
                                      'F. Registro',
                                      _formatDate(data['fecha']?.toString()),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _item(
                                      'F. Llegada',
                                      _formatDate(data['fecha_llegada']?.toString()),
                                    ),
                                  ),
                                ],
                              ),
                            ] else
                              _item('Fecha', _formatDate(data['fecha']?.toString())),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _item(
                                    'Granja',
                                    data['granja_nombre']?.toString() ?? '—',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _item(
                                    'Campaña',
                                    data['campania']?.toString() ?? '—',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _item('Galpón', data['galpon']?.toString() ?? '—'),
                          ],
                        ),
                        _section(
                          isDark: isDark,
                          cardBg: cardBg,
                          title: 'Cantidad de aves',
                          leading: const PoultryIcon(
                            size: 20,
                            color: AppColors.iconAccent,
                          ),
                          children: [
                            _item(
                              'Total aves',
                              '${_totalMachos(data, detalles) + _totalHembras(data, detalles)}',
                            ),
                            const SizedBox(height: 16),
                            _sexSummaryBlock(
                              label: 'Machos',
                              icon: Icons.male_rounded,
                              accent: AppColors.primary,
                              items: detalles.where((d) => d.isMacho).toList(),
                              total: _totalMachos(data, detalles),
                              showCausa: showCausa,
                              isDark: isDark,
                            ),
                            const SizedBox(height: 12),
                            _sexSummaryBlock(
                              label: 'Hembras',
                              icon: Icons.female_rounded,
                              accent: AppColors.primary,
                              items: detalles.where((d) => d.isHembra).toList(),
                              total: _totalHembras(data, detalles),
                              showCausa: showCausa,
                              isDark: isDark,
                            ),
                          ],
                        ),
                        _section(
                          isDark: isDark,
                          cardBg: cardBg,
                          title: 'Observaciones',
                          leading: Icon(
                            Icons.notes_rounded,
                            color: AppColors.iconAccent,
                            size: 20,
                          ),
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkSurface
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Text(
                                _textOrEmpty(data['observaciones']?.toString()),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: (data['observaciones']?.toString() ?? '').isEmpty
                                      ? AppColors.textMuted
                                      : (isDark ? Colors.white : AppColors.textPrimary),
                                  fontWeight: FontWeight.w500,
                                  fontStyle: (data['observaciones']?.toString() ?? '').isEmpty
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
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
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

  static int _totalMachos(Map<String, dynamic> data, List<MortalityDetail> detalles) {
    final fromDetails = MortalityDetail.totalMachos(detalles);
    if (fromDetails > 0) return fromDetails;
    return _intField(data['cant_machos']);
  }

  static int _totalHembras(Map<String, dynamic> data, List<MortalityDetail> detalles) {
    final fromDetails = MortalityDetail.totalHembras(detalles);
    if (fromDetails > 0) return fromDetails;
    return _intField(data['cant_hembras']);
  }

  static Widget _sexSummaryBlock({
    required String label,
    required IconData icon,
    required Color accent,
    required List<MortalityDetail> items,
    required int total,
    required bool showCausa,
    required bool isDark,
  }) {
    final fotos = <String>[];
    for (final d in items) {
      fotos.addAll(d.fotos);
    }
    final causaUnica = items.length == 1
        ? mortalityCausaLineText(
            showCausa: showCausa,
            causaNombre: items.first.causaNombre,
            causaCodigo: items.first.causaCodigo,
          )
        : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
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
                  fontSize: 15,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (total <= 0 && items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'No registrado',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else ...[
            _item('Cantidad', '$total'),
            if (items.length > 1) ...[
              const SizedBox(height: 10),
              Text(
                'Detalles (${items.length}):',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              ...items.asMap().entries.map((e) {
                final causaTexto = mortalityCausaLineText(
                  showCausa: showCausa,
                  causaNombre: e.value.causaNombre,
                  causaCodigo: e.value.causaCodigo,
                );
                return Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '· Detalle ${e.key + 1}: ${e.value.cantidad} aves',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      if (causaTexto != null) ...[
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            'Causa: $causaTexto',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                      if (e.value.observacion?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 2),
                        Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Text(
                            'Obs.: ${e.value.observacion}',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: isDark ? Colors.white70 : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
            ] else if (causaUnica != null) ...[
              const SizedBox(height: 8),
              _item('Causa', causaUnica),
            ],
            if (items.length == 1 && items.first.observacion?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              _item('Observación', items.first.observacion!),
            ] else if (items.length > 1) ...[
              const SizedBox(height: 8),
              ...items.where((d) => d.observacion?.trim().isNotEmpty == true).map(
                    (d) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _item(
                        'Obs. detalle',
                        d.observacion!,
                      ),
                    ),
                  ),
            ],
            const SizedBox(height: 8),
            _photoThumbnails(fotos, isDark),
          ],
        ],
      ),
    );
  }

  static Widget _photoThumbnails(List<String> paths, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fotos${paths.isEmpty ? '' : ' (${paths.length})'}:',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        if (paths.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'Sin fotos adjuntas',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: paths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final path = paths[index];
                final isUrl =
                    path.startsWith('http://') || path.startsWith('https://');
                Widget image;
                if (isUrl) {
                  image = Image.network(
                    path,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    headers: {
                      'Authorization': 'Bearer ${AppConstants.apiToken}',
                    },
                    errorBuilder: (_, __, ___) => Container(
                      width: 80,
                      height: 80,
                      color: isDark ? AppColors.darkSurface : Colors.grey.shade100,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey.shade500,
                        size: 28,
                      ),
                    ),
                  );
                } else {
                  final file = File(path);
                  image = file.existsSync()
                      ? Image.file(
                          file,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 80,
                          height: 80,
                          color: isDark ? AppColors.darkSurface : Colors.grey.shade100,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.grey.shade500,
                            size: 28,
                          ),
                        );
                }
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.25),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: image,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  static Widget _section({
    required bool isDark,
    required Color cardBg,
    required String title,
    required Widget leading,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: isDark ? 0.15 : 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _item(String label, String value) {
    final display = value.trim().isEmpty ? 'No especificado' : value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            display,
            style: TextStyle(
              fontSize: 13,
              color: display == 'No especificado'
                  ? AppColors.textMuted
                  : AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontStyle: display == 'No especificado'
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

  static String _textOrEmpty(String? v) {
    final t = v?.trim() ?? '';
    return t.isEmpty ? 'No especificado' : t;
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
