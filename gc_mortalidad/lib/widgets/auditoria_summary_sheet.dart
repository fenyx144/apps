import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/text_utils.dart';
import '../utils/theme_extensions.dart';
import 'photo_thumb.dart';

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
          final cardBg = context.cardColor;
          final fecha = DateFormat('dd/MM/yyyy').format(DateTime.now());

          // Muestra el nombre del auditor en lugar del código cuando está
          // disponible en la sesión.
          final auditorNombre =
              context.read<StorageService>().getUserName()?.trim() ?? '';
          final auditorDisplay = auditorNombre.isNotEmpty
              ? auditorNombre
              : usuario;

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
                    color: cardBg,
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
                            child: const Icon(
                              Icons.fact_check_outlined,
                              size: 24,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Resumen de auditoría',
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
                            // Fecha y usuario auditor en la misma fila.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _item(
                                    'Fecha',
                                    fecha,
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _item(
                                    'Usuario auditor',
                                    auditorDisplay,
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _item(
                                    'Registros',
                                    '$totalRegistros',
                                    isDark: isDark,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _item(
                                    'Total aves',
                                    '$totalAves',
                                    isDark: isDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        _section(
                          isDark: isDark,
                          title: 'Mortalidades',
                          leading: const Icon(
                            Icons.layers_outlined,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                          children: [
                            for (var i = 0; i < grupos.length; i++) ...[
                              if (i > 0) const SizedBox(height: 10),
                              _grupoCompacto(grupos[i], isDark),
                            ],
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

  /// Bloque compacto de mortalidad, sin bordes.
  static Widget _grupoCompacto(AuditoriaGrupoResumen grupo, bool isDark) {
    final type = MortalityTypeExt.fromId(grupo.clave.split(':').first);

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

    final obs = grupo.observaciones.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cabecera: tipo (icono + etiqueta) y total de registros.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (type != null)
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  gradient: type.iconGradient,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Icon(type.icon, color: Colors.white, size: 15),
              ),
            if (type != null) const SizedBox(width: 8),
            Expanded(
              child: Text(
                grupo.totalRegistros > 1
                    ? '${grupo.label} · ${grupo.totalRegistros} registros'
                    : grupo.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: isDark
                      ? AppColors.darkTextPrimary
                      : AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.check_circle_rounded,
              size: 17,
              color: AppColors.primary,
            ),
          ],
        ),
        if (granjaDisplay.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            granjaDisplay,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: 5),
        // Cantidades en una sola línea compacta.
        Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            Text(
              'M: ${grupo.cantMachos ?? 0}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.maleAccentDark
                    : AppColors.maleAccent,
              ),
            ),
            Text(
              'H: ${grupo.cantHembras ?? 0}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.femaleAccentDark
                    : AppColors.femaleAccent,
              ),
            ),
            Text(
              'Total ${grupo.totalAves}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.textPrimary,
              ),
            ),
          ],
        ),
        // Fotos del registro auditado (evidencia), dentro de su bloque.
        if (grupo.fotos.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Fotos (${grupo.fotos.length}):',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          PhotoStrip(
            fotos: grupo.fotos,
            size: 48,
          ),
        ],
        if (obs.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            obs,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontStyle: FontStyle.italic,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.textSecondary,
            ),
          ),
        ],
        Divider(
          height: 18,
          thickness: 1,
          color: isDark ? AppColors.darkBorder : AppColors.borderLight,
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
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
