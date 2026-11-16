import 'package:flutter/material.dart';

import 'constants.dart';
import 'theme_colors.dart';

void Function() showAppLoadingDialog(BuildContext context, String message) {
  BuildContext? dialogContext;
  var cerrado = false;

  showDialog(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (ctx) {
      dialogContext = ctx;
      if (cerrado) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctx.mounted) Navigator.of(ctx, rootNavigator: true).pop();
        });
      }
      return Dialog(
        backgroundColor: ctx.dialogSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ctx.textThemePrimary,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  return () {
    if (cerrado) return;
    cerrado = true;
    final ctx = dialogContext;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  };
}
