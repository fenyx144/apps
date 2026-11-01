import 'package:flutter/material.dart';
import 'theme_colors.dart';
import 'constants.dart';

/// Diálogo de carga con la gallina animada (mismo recurso que crianza).
void Function() showAppLoadingDialog(BuildContext context, String message) {
  BuildContext? dialogContext;

  showDialog(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      dialogContext = ctx;
      return Dialog(
        backgroundColor: ctx.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // La gallina va dentro del diálogo, no por fuera.
              Image.asset(
                'assets/gifs/gallina.gif',
                width: 150,
                height: 150,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ctx.textThemePrimary,
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  return () {
    final ctx = dialogContext;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  };
}

/// Alias retrocompatible con el nombre usado por las pantallas de bioseguridad.
void Function() showChickenLoadingDialog(BuildContext context, String message) =>
    showAppLoadingDialog(context, message);
