import 'dart:async';

import 'package:flutter/material.dart';
import 'theme_colors.dart';
import 'constants.dart';

/// Diálogo de carga con la gallina animada (mismo recurso que crianza).
void Function() showAppLoadingDialog(BuildContext context, String message) {
  BuildContext? dialogContext;
  var dismissed = false;
  final ready = Completer<void>();

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      dialogContext = ctx;
      if (!ready.isCompleted) ready.complete();
      return Dialog(
        backgroundColor: ctx.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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

  if (!ready.isCompleted) {
    ready.complete();
  }

  var dialogClosed = false;

  /// Solo cierra la ruta del diálogo. No usa `canPop` en el navigator raíz:
  /// reintentos ahí podían hacer `pop` de la pantalla (p. ej. login) justo
  /// antes de `Get.off` y dejar el navigator sin rutas.
  void tryPop([int intento = 0]) {
    if (dialogClosed) return;
    final ctx = dialogContext;
    if (ctx != null && ctx.mounted) {
      final route = ModalRoute.of(ctx);
      if (route != null && route.isActive) {
        Navigator.of(ctx, rootNavigator: true).pop();
        dialogClosed = true;
        return;
      }
    }
    if (!dismissed && intento < 24) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        tryPop(intento + 1);
      });
    }
  }

  return () {
    if (dismissed) return;
    dismissed = true;
    tryPop();
  };
}

/// Cierra la gallina y espera a que el `pop` termine antes del toast u otro
/// diálogo.
Future<void> dismissLoadingDialog(void Function()? close) async {
  close?.call();
  await Future<void>.delayed(const Duration(milliseconds: 220));
}

/// Alias retrocompatible con el nombre usado por las pantallas de bioseguridad.
void Function() showChickenLoadingDialog(BuildContext context, String message) =>
    showAppLoadingDialog(context, message);
