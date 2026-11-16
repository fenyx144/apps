import 'package:flutter/material.dart';

import 'theme_colors.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: builder,
  );
}

Widget appDialogHeader(
  BuildContext context, {
  required String title,
  VoidCallback? onClose,
}) {
  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textThemePrimary,
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.close, color: context.textThemeMuted),
          onPressed: onClose ?? () => Navigator.pop(context),
        ),
      ],
    ),
  );
}
