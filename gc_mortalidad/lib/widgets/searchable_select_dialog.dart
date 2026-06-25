import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';

Future<void> showSearchableSelectDialog<T>({
  required BuildContext context,
  required String title,
  required IconData icon,
  required List<T> items,
  required String Function(T) getLabel,
  String Function(T)? getSubtitle,
  bool showSubtitle = false,
  required String? selectedValue,
  required String? Function(T) getValue,
  required ValueChanged<String?> onSelected,
  String emptyMessage = 'Sin opciones disponibles',
  bool autofocus = false,
}) async {
  String query = '';
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final dialogBg = isDark ? AppColors.darkCard : Colors.white;

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = items.where((item) {
            if (query.isEmpty) return true;
            final label = getLabel(item).toLowerCase();
            final sub = showSubtitle && getSubtitle != null
                ? getSubtitle(item).toLowerCase()
                : '';
            final q = query.toLowerCase();
            return label.contains(q) || sub.contains(q);
          }).toList();

          return Dialog(
            backgroundColor: dialogBg,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: SizedBox(
              width: double.maxFinite,
              height: MediaQuery.of(context).size.height * 0.58,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        Icon(icon, color: AppColors.primary, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close_rounded,
                            color: isDark ? Colors.white70 : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      autofocus: autofocus,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: AppInputStyles.decoration(
                        context,
                        r: 12,
                        hintText: 'Buscar...',
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white38 : Colors.grey.shade500,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                        fillColor: isDark ? AppColors.darkSurface : Colors.grey.shade50,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: (v) => setDialogState(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                emptyMessage,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          )
                        : filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Sin resultados',
                                style: TextStyle(
                                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 4),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final val = getValue(item);
                              final isSelected = val == selectedValue;
                              return Material(
                                color: isSelected
                                    ? AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.1)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                child: ListTile(
                                  dense: true,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  title: Text(
                                    getLabel(item),
                                    style: TextStyle(
                                      fontWeight:
                                          isSelected ? FontWeight.w700 : FontWeight.w500,
                                      fontSize: 15,
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                  ),
                                  subtitle: showSubtitle && getSubtitle != null
                                      ? Text(
                                          getSubtitle(item),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                                          ),
                                        )
                                      : null,
                                  trailing: isSelected
                                      ? const Icon(
                                          Icons.check_circle_rounded,
                                          color: AppColors.primary,
                                          size: 22,
                                        )
                                      : null,
                                  onTap: () {
                                    onSelected(val);
                                    Navigator.pop(context);
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
