import 'package:flutter/material.dart';
import 'theme_colors.dart';

void Function() showChickenLoadingDialog(BuildContext context, String message) {
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/gifs/gallina.gif',
                width: 160,
                height: 160,
              ),
              const SizedBox(height: 16),
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
    final ctx = dialogContext;
    if (ctx != null && ctx.mounted) {
      Navigator.of(ctx, rootNavigator: true).pop();
    }
  };
}
