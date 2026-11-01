import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'choice_card.dart';

String produccionRegistroLabel(String? value) {
  switch (value) {
    case 'Crianza':
      return 'Crianza';
    case 'Necropsia':
      return 'Necropsia';
    case 'Laboratorio':
      return 'Laboratorio';
    case 'Cuarentena':
      return 'Cuarentena';
    default:
      return '';
  }
}

class _RegistroOption {
  final String value;
  final String label;
  final IconData icon;
  final LinearGradient gradient;

  const _RegistroOption({
    required this.value,
    required this.label,
    required this.icon,
    required this.gradient,
  });
}

const _options = [
  _RegistroOption(
    value: 'Crianza',
    label: 'Crianza',
    icon: Icons.agriculture_rounded,
    gradient: LinearGradient(
      colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  _RegistroOption(
    value: 'Necropsia',
    label: 'Necropsia',
    icon: Icons.biotech_rounded,
    gradient: LinearGradient(
      colors: [Color(0xFF26A69A), Color(0xFF80CBC4)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  _RegistroOption(
    value: 'Laboratorio',
    label: 'Laboratorio',
    icon: Icons.science_rounded,
    gradient: LinearGradient(
      colors: [Color(0xFF42A5F5), Color(0xFF90CAF9)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
  _RegistroOption(
    value: 'Cuarentena',
    label: 'Cuarentena',
    icon: Icons.health_and_safety_rounded,
    gradient: LinearGradient(
      colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ),
];

Future<String?> showProduccionRegistroDialog({
  required BuildContext context,
  required String? selected,
  required Color accentColor,
}) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  var current = selected ?? 'Crianza';

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            backgroundColor: isDark ? AppColors.darkCard : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.agriculture_outlined, color: AppColors.textSecondary, size: 22),
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
                      for (var i = 0; i < 2; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        ChoiceCard(
                          compact: true,
                          label: _options[i].label,
                          icon: _options[i].icon,
                          selected: current == _options[i].value,
                          accentColor: accentColor,
                          gradient: _options[i].gradient,
                          onTap: () => setDialogState(() => current = _options[i].value),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var i = 2; i < 4; i++) ...[
                        if (i > 2) const SizedBox(width: 8),
                        ChoiceCard(
                          compact: true,
                          label: _options[i].label,
                          icon: _options[i].icon,
                          selected: current == _options[i].value,
                          accentColor: accentColor,
                          gradient: _options[i].gradient,
                          onTap: () => setDialogState(() => current = _options[i].value),
                        ),
                      ],
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
