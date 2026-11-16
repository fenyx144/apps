import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Calendario compacto para la subida: por día muestra registros pendientes
/// (P, naranja) y subidos (S, verde) del usuario actual.
class UploadDateDialog extends StatefulWidget {
  const UploadDateDialog({
    required this.counts,
    required this.firstDate,
    required this.lastDate,
  });

  final Map<String, ({int pend, int sub})> counts;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<UploadDateDialog> createState() => UploadDateDialogState();
}

class UploadDateDialogState extends State<UploadDateDialog> {
  static const _weekdays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  late DateTime _focus;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _focus = DateTime.now();
    _selected = DateTime(_focus.year, _focus.month, _focus.day);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _changeMonth(int delta) {
    final next = DateTime(_focus.year, _focus.month + delta, 1);
    if (next.isBefore(
      DateTime(widget.firstDate.year, widget.firstDate.month, 1),
    )) {
      return;
    }
    if (next.isAfter(
      DateTime(widget.lastDate.year, widget.lastDate.month, 1),
    )) {
      return;
    }
    setState(() => _focus = next);
  }

  Widget _countBadge(int n, bool pend) {
    final bg = pend ? const Color(0xFFFFE0B2) : const Color(0xFFC8E6C9);
    final fg = pend ? const Color(0xFFE65100) : const Color(0xFF1B5E20);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        pend ? 'P: $n' : 'S: $n',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: fg,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _dayCell(double width, int dayNumber) {
    final day = DateTime(_focus.year, _focus.month, dayNumber);
    final key = DateFormat('yyyy-MM-dd').format(day);
    final c = widget.counts[key];
    final now = DateTime.now();
    final isToday = _isSameDay(day, now);
    final isSelected = _selected != null && _isSameDay(day, _selected!);
    final first = DateTime(
      widget.firstDate.year,
      widget.firstDate.month,
      widget.firstDate.day,
    );
    final last = DateTime(
      widget.lastDate.year,
      widget.lastDate.month,
      widget.lastDate.day,
    );
    final disabled = day.isBefore(first) || day.isAfter(last);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: disabled ? null : () => setState(() => _selected = day),
      child: Container(
        width: width,
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$dayNumber',
              style: TextStyle(
                fontSize: 13,
                height: 1.0,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                color: disabled
                    ? (isDark
                        ? const Color(0xFF6E6E6E)
                        : const Color(0xFF9E9E9E))
                    : isSelected
                        ? Colors.white
                        : isToday
                            ? AppColors.primaryDark
                            : isDark
                                ? const Color(0xFFF5F5F5)
                                : const Color(0xFF0F172A),
              ),
            ),
            if (c != null && (c.pend > 0 || c.sub > 0)) ...[
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (c.pend > 0) _countBadge(c.pend, true),
                    if (c.pend > 0 && c.sub > 0) const SizedBox(width: 3),
                    if (c.sub > 0) _countBadge(c.sub, false),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: context.textThemeSecondary),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstDay = DateTime(_focus.year, _focus.month, 1);
    final offset = firstDay.weekday - 1; // semana inicia lunes
    final daysInMonth = DateTime(_focus.year, _focus.month + 1, 0).day;

    var totalPend = 0;
    var totalSub = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final key = DateFormat('yyyy-MM-dd')
          .format(DateTime(_focus.year, _focus.month, d));
      final c = widget.counts[key];
      if (c != null) {
        totalPend += c.pend;
        totalSub += c.sub;
      }
    }

    final rawMonth = DateFormat('MMMM yyyy', 'es').format(_focus);
    final monthLabel = rawMonth.isEmpty
        ? rawMonth
        : rawMonth[0].toUpperCase() + rawMonth.substring(1);

    return Dialog(
      backgroundColor: Theme.of(context).dialogBackgroundColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => _changeMonth(-1),
                    visualDensity: VisualDensity.compact,
                  ),
                  Expanded(
                    child: Text(
                      monthLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.textThemePrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => _changeMonth(1),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _countBadge(totalPend, true),
                  const SizedBox(width: 6),
                  _countBadge(totalSub, false),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: _weekdays
                    .map(
                      (w) => Expanded(
                        child: Text(
                          w,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Theme.of(context).brightness ==
                                    Brightness.dark
                                ? const Color(0xFFCFCFCF)
                                : const Color(0xFF263238),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 4),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cellW = constraints.maxWidth / 7;
                  return Wrap(
                    children: [
                      for (var i = 0; i < offset; i++)
                        SizedBox(width: cellW, height: 52),
                      for (var d = 1; d <= daysInMonth; d++)
                        _dayCell(cellW, d),
                    ],
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendDot(const Color(0xFFE65100), 'Pendientes'),
                  const SizedBox(width: 14),
                  _legendDot(const Color(0xFF1B5E20), 'Subidos'),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selected == null
                        ? null
                        : () => Navigator.pop(context, _selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.4),
                    ),
                    child: const Text(
                      'Subir',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
