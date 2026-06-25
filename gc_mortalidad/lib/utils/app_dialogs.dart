import 'package:flutter/material.dart';
import 'constants.dart';

/// Fuerza fondo blanco en modo claro para diálogos del SDK (fechas, etc.).
Widget appDialogThemeBuilder(BuildContext context, Widget? child) {
  if (child == null) return const SizedBox.shrink();

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final dialogBg = isDark ? AppColors.darkCard : Colors.white;

  return Theme(
    data: Theme.of(context).copyWith(
      dialogTheme: DialogThemeData(
        backgroundColor: dialogBg,
        surfaceTintColor: Colors.transparent,
      ),
      colorScheme: Theme.of(context).colorScheme.copyWith(
        surface: dialogBg,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: dialogBg,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppColors.primary,
        headerForegroundColor: Colors.white,
      ),
    ),
    child: child,
  );
}

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  Locale? locale,
}) {
  return showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: firstDate,
    lastDate: lastDate,
    helpText: helpText,
    locale: locale,
    builder: appDialogThemeBuilder,
  );
}
