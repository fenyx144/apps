import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'choice_card.dart';

String transportSubtypeLabel(String? value) {
  switch (value) {
    case 'transporte':
      return 'Transporte';
    case 'evento':
      return 'Evento';
    default:
      return '';
  }
}

Future<String?> showTransportSubtypeDialog({
  required BuildContext context,
  required String? selected,
  required Color accentColor,
  required LinearGradient transportGradient,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  var current = selected ?? 'transporte';

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: isDark ? AppColors.darkCard : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_shipping_rounded, color: AppColors.textSecondary, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tipo de registro',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark ? Colors.white70 : Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      ChoiceCard(
                        label: 'Transporte',
                        icon: Icons.local_shipping_rounded,
                        selected: current == 'transporte',
                        accentColor: accentColor,
                        gradient: transportGradient,
                        onTap: () => setDialogState(() => current = 'transporte'),
                      ),
                      const SizedBox(width: 10),
                      ChoiceCard(
                        label: 'Evento',
                        icon: Icons.event_note_rounded,
                        selected: current == 'evento',
                        accentColor: accentColor,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF26A69A), Color(0xFF4DB6AC)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        onTap: () => setDialogState(() => current = 'evento'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, current),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Confirmar',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
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
