import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/constants.dart';
import '../utils/mortality_design.dart';

class AuditoriaGrupoResumen {
  const AuditoriaGrupoResumen({
    required this.clave,
    required this.label,
    required this.totalRegistros,
    required this.totalAves,
    required this.observaciones,
    required this.fotos,
    this.granja,
    this.granjaNombre,
    this.campania,
    this.galpon,
    this.cantMachos,
    this.cantHembras,
  });

  final String clave;
  final String label;
  final int totalRegistros;
  final int totalAves;
  final String observaciones;
  final List<String> fotos;
  final String? granja;
  final String? granjaNombre;
  final String? campania;
  final String? galpon;
  final int? cantMachos;
  final int? cantHembras;
}

class AuditoriaSummarySheet {
  static Future<bool?> show({
    required BuildContext context,
    required String usuario,
    required List<AuditoriaGrupoResumen> grupos,
    required int totalRegistros,
    required int totalAves,
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
          final fecha = DateFormat('dd/MM/yyyy').format(DateTime.now());

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
                            child: const Icon(
                              Icons.fact_check_outlined,
                              size: 24,
                              color: AppColors.iconAccent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Resumen de auditoría',
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
                          leading: const Icon(
                            Icons.info_outline,
                            color: AppColors.iconAccent,
                            size: 20,
                          ),
                          children: [
                            _item('Fecha', fecha),
                            const SizedBox(height: 12),
                            _item('Usuario auditor', usuario),
                            
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _item('Registros', '$totalRegistros'),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _item('Total aves', '$totalAves'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        _section(
                          isDark: isDark,
                          cardBg: cardBg,
                          title: 'Mortalidades',
                          leading: const Icon(
                            Icons.layers_outlined,
                            color: AppColors.iconAccent,
                            size: 20,
                          ),
                          children: [
                            ...grupos.map(
                              (g) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _grupoBlock(g, isDark),
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
                    child: Row(
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

  static Widget _grupoBlock(AuditoriaGrupoResumen grupo, bool isDark) {
    final partes = grupo.clave.split(':');
    final type = MortalityTypeExt.fromId(partes.first);

    final granjaDisplay = [
      if (grupo.granjaNombre != null && grupo.granjaNombre!.trim().isNotEmpty)
        grupo.granjaNombre!.trim()
      else if (grupo.granja != null && grupo.granja!.trim().isNotEmpty)
        grupo.granja!.trim(),
      if (grupo.campania != null && grupo.campania!.trim().isNotEmpty)
        grupo.campania!.trim(),
      if (grupo.galpon != null && grupo.galpon!.trim().isNotEmpty)
        'Galpón ${grupo.galpon!.trim()}',
    ].join(' - ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: icon + type label
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (type != null)
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    gradient: type.iconGradient,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(type.icon, color: Colors.white, size: 18),
                ),
              if (type != null) const SizedBox(width: 10),
              Expanded(
                child: Text(
                  grupo.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Granja / Campaña
          if (granjaDisplay.isNotEmpty) ...[
            _item('Granja / Campa\u00f1a', granjaDisplay),
            const SizedBox(height: 8),
          ],
          // Cantidades M / H / Total
          Row(
            children: [
              Expanded(child: _item('Machos', '${grupo.cantMachos ?? 0}')),
              Expanded(child: _item('Hembras', '${grupo.cantHembras ?? 0}')),
              Expanded(child: _item('Total', '${grupo.totalAves}')),
            ],
          ),
          const SizedBox(height: 8),
          _item('Observaciones', _textOrEmpty(grupo.observaciones)),
          if (grupo.fotos.isNotEmpty) const SizedBox(height: 8),
          _photoThumbnails(grupo.fotos, isDark),
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
          const Padding(
            padding: EdgeInsets.only(left: 8),
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
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final path = paths[index];
                final file = File(path);
                final image = file.existsSync()
                    ? Image.file(file, width: 80, height: 80, fit: BoxFit.cover)
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
            maxLines: 6,
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
}
