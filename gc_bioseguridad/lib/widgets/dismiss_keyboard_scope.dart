import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Cierra el teclado al tocar fuera de un [EditableText] (botones, selectores, etc.).
class DismissKeyboardScope extends StatelessWidget {
  const DismissKeyboardScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) => _onPointerDown(context, event),
      child: child,
    );
  }

  void _onPointerDown(BuildContext context, PointerDownEvent event) {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || !focus.hasFocus) return;

    final view = View.of(context);
    final box = context.findRenderObject();
    var position = event.position;
    if (box is RenderBox) {
      position = box.localToGlobal(event.position);
    }

    final hit = HitTestResult();
    RendererBinding.instance.hitTestInView(hit, position, view.viewId);
    for (final entry in hit.path) {
      if (entry.target is RenderEditable) {
        return;
      }
    }
    focus.unfocus();
  }
}