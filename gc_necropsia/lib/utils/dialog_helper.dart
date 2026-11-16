import 'package:flutter/material.dart';

void Function() showChickenLoadingDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      backgroundColor: Colors.white,
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
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    ),
  );

  // Retorna una función para cerrar el diálogo
  return () {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  };
}
