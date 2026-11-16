import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/face_engine.dart';
import '../services/nomina_store.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_status_bar.dart';
import '../widgets/section_app_bar.dart';

class DiagnosticoScreen extends StatefulWidget {
  const DiagnosticoScreen({super.key});

  @override
  State<DiagnosticoScreen> createState() => _DiagnosticoScreenState();
}

class _DiagnosticoScreenState extends State<DiagnosticoScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = context.read<FaceEngine>();
    final storage = context.watch<StorageService>();
    final store = context.watch<NominaStore>();
    final t = engine.tiempos;
    final version = storage.getNominaVersion();
    return ScreenStatusBar(
      color: context.scaffoldMuted,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: const SectionAppBar(
          title: AppStrings.menuDiagnostico,
          sectionIcon: Icons.monitor_heart_rounded,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _card(
              context,
              titulo: 'Tiempos (ms)',
              accion: TextButton(
                onPressed: () => setState(t.limpiar),
                child: const Text('Limpiar'),
              ),
              child: Column(
                children: [
                  _filaTiempo(context, 'Detección', t.mediana('deteccion'),
                      t.p95('deteccion'), t.n('deteccion')),
                  _filaTiempo(context, 'Alineación', t.mediana('alineacion'),
                      t.p95('alineacion'), t.n('alineacion')),
                  _filaTiempo(context, 'Vector', t.mediana('vector'),
                      t.p95('vector'), t.n('vector')),
                  _filaTiempo(context, 'Comparación',
                      t.mediana('comparacion'), t.p95('comparacion'),
                      t.n('comparacion')),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              context,
              titulo: 'Reconocimiento',
              child: Column(
                children: [
                  _slider(
                    context,
                    etiqueta: 'Umbral',
                    valor: storage.getUmbral(),
                    min: 0.30,
                    max: 0.70,
                    onChanged: (v) {
                      storage.saveUmbral(v);
                      engine.umbral = v;
                    },
                  ),
                  _slider(
                    context,
                    etiqueta: 'Margen',
                    valor: storage.getMargen(),
                    min: 0,
                    max: 0.30,
                    onChanged: (v) {
                      storage.saveMargen(v);
                      engine.margen = v;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              context,
              titulo: 'Estado',
              child: Column(
                children: [
                  _filaDato(context, 'Nómina', '${store.total}'),
                  _filaDato(context, 'Versión',
                      version.isEmpty ? '—' : version),
                  _filaDato(context, 'Eventos pendientes',
                      '${storage.eventosPendientesCount()}'),
                  _filaDato(context, 'Plantillas pendientes',
                      '${storage.getPlantillasPendientes().length}'),
                  _filaDato(context, 'Última descarga',
                      storage.lastDownloadDateDisplay),
                  _filaDato(context, 'Última subida',
                      storage.lastSyncDateDisplay),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context, {
    required String titulo,
    required Widget child,
    Widget? accion,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: context.surfaceCard,
        borderRadius: BorderRadius.circular(AppColors.radiusLg),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(
                    color: context.textThemePrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (accion != null) accion,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _filaTiempo(
    BuildContext context,
    String etapa,
    double mediana,
    double p95,
    int n,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etapa,
              style: TextStyle(
                color: context.textThemePrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            'med ${mediana.toStringAsFixed(1)}',
            style: TextStyle(
              color: context.textThemeSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 86,
            child: Text(
              'p95 ${p95.toStringAsFixed(1)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.textThemeSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 64,
            child: Text(
              'n $n',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: context.textThemeMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider(
    BuildContext context, {
    required String etiqueta,
    required double valor,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                etiqueta,
                style: TextStyle(
                  color: context.textThemePrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              valor.toStringAsFixed(2),
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: valor.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / 0.01).round(),
          label: valor.toStringAsFixed(2),
          activeColor: AppColors.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _filaDato(BuildContext context, String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              etiqueta,
              style: TextStyle(
                color: context.textThemePrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            valor,
            style: TextStyle(
              color: context.textThemeSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
