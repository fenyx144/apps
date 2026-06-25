import 'package:flutter/material.dart';

class ReferenceCodeInput extends StatefulWidget {
  final int length;
  final String value;
  final Function(String) onChanged;

  const ReferenceCodeInput({
    super.key,
    required this.length,
    required this.value,
    required this.onChanged,
  });

  @override
  State<ReferenceCodeInput> createState() => _ReferenceCodeInputState();
}

class _ReferenceCodeInputState extends State<ReferenceCodeInput> {
  late List<TextEditingController> _controllers;

  @override
  void initState() {
    _controllers = List.generate(widget.length, (i) => TextEditingController());
    _updateControllers();
    super.initState();
  }

  @override
  void didUpdateWidget(covariant ReferenceCodeInput oldWidget) {
    if (oldWidget.length != widget.length) {
      for (final c in _controllers) {
        c.dispose();
      }
      _controllers = List.generate(
        widget.length,
        (i) => TextEditingController(),
      );
    }
    if (oldWidget.value != widget.value || oldWidget.length != widget.length) {
      _updateControllers();
    }
    super.didUpdateWidget(oldWidget);
  }

  void _updateControllers() {
    for (int i = 0; i < widget.length; i++) {
      if (i < widget.value.length) {
        _controllers[i].text = widget.value[i];
      } else {
        _controllers[i].clear();
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 4.0;
        final totalGap = gap * (widget.length - 1);
        final cellWidth =
            ((constraints.maxWidth - totalGap) / widget.length).clamp(24.0, 44.0);
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.start,
          children: List.generate(widget.length, (i) {
            return SizedBox(
              width: cellWidth,
              height: 40,
              child: TextField(
                controller: _controllers[i],
                textAlign: TextAlign.center,
                maxLength: 1,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: Color(0xFF667EEA),
                      width: 1.5,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey.shade400, width: 1.5),
                  ),
                ),
                onChanged: (v) {
                  var newValue = '';
                  for (int j = 0; j < widget.length; j++) {
                    newValue += _controllers[j].text;
                  }
                  widget.onChanged(newValue);
                  if (v.isNotEmpty && i < widget.length - 1) {
                    FocusScope.of(context).nextFocus();
                  }
                },
              ),
            );
          }),
        );
      },
    );
  }
}
