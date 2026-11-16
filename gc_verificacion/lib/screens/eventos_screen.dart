import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_status_bar.dart';
import '../widgets/section_app_bar.dart';

class EventosScreen extends StatefulWidget {
  const EventosScreen({super.key});

  @override
  State<EventosScreen> createState() => _EventosScreenState();
}

class _EventosScreenState extends State<EventosScreen> {
  DateTime _dia = DateTime.now();

  String get _titulo {
    final hoy = DateTime.now();
    final d0 = DateTime(hoy.year, hoy.month, hoy.day);
    final d1 = DateTime(_dia.year, _dia.month, _dia.day);
    if (d1 == d0) return 'Hoy';
    final s = DateFormat("EEEE, d 'de' MMMM", 'es_ES').format(_dia);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final eventos = storage.eventosDelDia(_dia);
    final ok =
        eventos.where((e) => (e['resultado'] ?? 'A') != 'R').length;
    final no = eventos.length - ok;
    final pend = eventos
        .where((e) => e['synced'] != true && e['synced'] != 'true')
        .length;
    return ScreenStatusBar(
      color: context.scaffoldMuted,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: const SectionAppBar(
          title: AppStrings.menuEventos,
          sectionIcon: Icons.history_rounded,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => setState(
                      () => _dia = _dia.subtract(const Duration(days: 1)),
                    ),
                    icon: Icon(
                      Icons.chevron_left_rounded,
                      color: context.textThemePrimary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _titulo,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: context.textThemePrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(
                      () => _dia = _dia.add(const Duration(days: 1)),
                    ),
                    icon: Icon(
                      Icons.chevron_right_rounded,
                      color: context.textThemePrimary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'A: $ok · R: $no · Pend: $pend',
                style: TextStyle(
                  color: context.textThemeSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: eventos.isEmpty
                  ? const Center(
                      child: Icon(
                        Icons.history_rounded,
                        size: 72,
                        color: AppColors.textMuted,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                      itemCount: eventos.length,
                      itemBuilder: (_, i) => _fila(context, eventos[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, Map<String, dynamic> e) {
    final ok = (e['resultado'] ?? 'A') != 'R';
    final color = ok ? AppColors.aprobado : AppColors.rechazado;
    final subido = e['synced'] == true || e['synced'] == 'true';
    final sim = e['similitud'];
    final pct = sim is num ? '${(sim * 100).toStringAsFixed(1)}%' : '—';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceCard,
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Icon(
              ok ? Icons.check_rounded : Icons.close_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (e['nombre']?.toString() ?? '').isEmpty
                      ? 'DNI ${e['dni'] ?? ''}'
                      : e['nombre'].toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.textThemePrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'DNI ${e['dni'] ?? ''} · $pct · ${e['modo'] ?? '1N'}',
                  style: TextStyle(
                    color: context.textThemeMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                (e['hora']?.toString() ?? '').length >= 8
                    ? e['hora'].toString().substring(0, 8)
                    : (e['hora']?.toString() ?? ''),
                style: TextStyle(
                  color: context.textThemePrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Icon(
                subido
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                color: subido
                    ? AppColors.aprobado
                    : AppColors.textMuted,
                size: 18,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
