import 'dart:io';

import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/section_app_bar.dart';

/// Contenido reutilizable del resumen (sin título propio; va en secciones).
class RegisterSummaryContent extends StatelessWidget {
  const RegisterSummaryContent({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isAppDark;
    final cardBg = context.surfaceCard;
    final imagenes = (record['imagenes'] as List?)
            ?.map((e) => e.toString())
            .where((p) => p.isNotEmpty)
            .toList() ??
        [];

    final granjaLabel = GranjaCampaniaPicker.formatGranjaLabel(
      record['granja']?.toString() ?? '',
      record['granjaNombre']?.toString() ?? '',
    );
    final campania = GranjaCampaniaPicker.padCampania(
      record['campania']?.toString() ?? '',
    );
    final obs = record['obs']?.toString().trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummarySection(
          isDark: isDark,
          cardBg: cardBg,
          title: 'Información general',
          leading: const Icon(
            Icons.info_outline,
            color: AppColors.iconAccent,
            size: 20,
          ),
          children: [
            _SummaryItem('Fecha', _formatDate(record['fecha']?.toString())),
            const SizedBox(height: 12),
            _SummaryItem('Proceso', record['procesoNombre']?.toString() ?? ''),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _SummaryItem(
                    'Granja',
                    granjaLabel.isNotEmpty ? granjaLabel : '—',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: _SummaryItem(
                    'CAMP',
                    campania.isNotEmpty ? campania : '—',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: _SummaryItem(
                    'Galpón',
                    record['galpon']?.toString() ?? '—',
                  ),
                ),
              ],
            ),
          ],
        ),
        _SummarySection(
          isDark: isDark,
          cardBg: cardBg,
          title: 'Observaciones',
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: AppColors.iconAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: AppColors.iconAccent,
              size: 22,
            ),
          ),
          children: [
            Text(
              obs.isEmpty ? 'No especificado' : obs,
              style: TextStyle(
                fontSize: 14,
                color: obs.isEmpty
                    ? AppColors.textMuted
                    : (isDark ? Colors.white : AppColors.textPrimary),
                fontWeight: FontWeight.w500,
                fontStyle: obs.isEmpty ? FontStyle.italic : FontStyle.normal,
                height: 1.45,
              ),
            ),
          ],
        ),
        _SummarySection(
          isDark: isDark,
          cardBg: cardBg,
          title: 'Imágenes',
          leading: const Icon(
            Icons.photo_library_outlined,
            color: AppColors.iconAccent,
            size: 20,
          ),
          children: [
            _SummaryPhotoThumbnails(paths: imagenes, isDark: isDark),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({
    required this.isDark,
    required this.cardBg,
    required this.title,
    required this.leading,
    required this.children,
  });

  final bool isDark;
  final Color cardBg;
  final String title;
  final Widget leading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
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
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isAppDark;
    final display = value.trim().isEmpty ? 'No especificado' : value;
    final empty = display == 'No especificado' || display == '—';

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
              color: empty
                  ? AppColors.textMuted
                  : (isDark ? Colors.white : AppColors.textPrimary),
              fontWeight: FontWeight.w500,
              fontStyle: empty ? FontStyle.italic : FontStyle.normal,
            ),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _SummaryPhotoThumbnails extends StatelessWidget {
  const _SummaryPhotoThumbnails({
    required this.paths,
    required this.isDark,
  });

  final List<String> paths;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
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
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final path = paths[index];
                final file = File(path);
                final image = file.existsSync()
                    ? Image.file(
                        file,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 80,
                        height: 80,
                        color: isDark
                            ? const Color(0xFF1E1E1E)
                            : Colors.grey.shade100,
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
}

String _formatDate(String? raw) {
  if (raw == null || raw.isEmpty) return '—';
  try {
    final parts = raw.split('-');
    if (parts.length == 3) {
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
  } catch (_) {}
  return raw;
}

/// Modal de resumen (guardar o solo lectura en reportes).
class RegisterSummarySheet {
  static Future<bool> show(
    BuildContext context, {
    required Map<String, dynamic> record,
    Future<void> Function()? onConfirm,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.88,
        builder: (context, scrollController) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final headerBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;
          final sheetBg = isDark ? const Color(0xFF121212) : Colors.white;
          final footerBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;

          return Container(
            decoration: BoxDecoration(
              color: sheetBg,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
                  decoration: BoxDecoration(
                    color: headerBg,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
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
                              color: AppColors.iconAccent,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Resumen de registro',
                              style: TextStyle(
                                color: isDark
                                    ? Colors.white
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
                                  ? Colors.white70
                                  : AppColors.textSecondary,
                            ),
                            onPressed: () =>
                                Navigator.pop(sheetContext, false),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      onConfirm == null
                          ? 16 + MediaQuery.paddingOf(context).bottom
                          : 16,
                    ),
                    child: RegisterSummaryContent(record: record),
                  ),
                ),
                if (onConfirm != null)
                  Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: footerBg,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    top: false,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              Navigator.pop(sheetContext, false),
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
                          onPressed: () async {
                            await onConfirm();
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext, true);
                            }
                          },
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
    return result ?? false;
  }
}

/// Vista de solo lectura para reportes.
class RegisterSummaryScreen extends StatelessWidget {
  const RegisterSummaryScreen({super.key, required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: 'Resumen de registro',
        sectionIcon: Icons.fact_check_outlined,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: RegisterSummaryContent(record: record),
      ),
    );
  }
}
