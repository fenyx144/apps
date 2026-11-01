import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/section_app_bar.dart';

/// Granjas atendidas en este punto de control (ingreso–salida).
class MiGranjaScreen extends StatefulWidget {
  const MiGranjaScreen({super.key});

  @override
  State<MiGranjaScreen> createState() => _MiGranjaScreenState();
}

class _GranjaTrabajoItem {
  _GranjaTrabajoItem({required this.codigo, required this.nombre});

  final String codigo;
  final String nombre;

  String get etiqueta => GranjaCampaniaPicker.formatGranjaLabel(codigo, nombre);
}

class _MiGranjaScreenState extends State<MiGranjaScreen> {
  List<_GranjaTrabajoItem> _items = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  void _cargar() {
    final storage = context.read<StorageService>();
    final proy = storage.getProyeccion();
    _items = storage.getGranjasTrabajo().map((g) {
      return _GranjaTrabajoItem(
        codigo: g,
        nombre: GranjaCampaniaPicker.nombreDeGranja(proy, g),
      );
    }).toList();
  }

  Future<void> _agregarGranja() async {
    final storage = context.read<StorageService>();
    final sel = await GranjaCampaniaPicker.show(
      context,
      proyeccion: storage.getProyeccion(),
      cencosGalpones: storage.getCencosGalpones(),
    );
    if (sel == null || !mounted) return;

    final g3 = GranjaCampaniaPicker.normGranja(
      (sel['granja3'] ?? '').toString(),
    );
    if (g3.isEmpty) return;

    if (_items.any((e) => e.codigo == g3)) {
      showInfoToast(context, 'Esa granja ya está en la lista.');
      return;
    }

    await storage.addGranjaTrabajo(g3);
    if (!mounted) return;
    setState(_cargar);
    showSuccessToast(context, 'Granja agregada');
  }

  Future<void> _quitarGranja(String codigo) async {
    final storage = context.read<StorageService>();
    await storage.removeGranjaTrabajo(codigo);
    if (!mounted) return;
    setState(_cargar);
    showSuccessToast(context, 'Granja quitada');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.scaffoldMuted,
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: AppStrings.miGranjaTitle,
        sectionIcon: Icons.home_work_rounded,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Granjas de este punto',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.textThemePrimary,
              ),
            ),
            if (_items.isEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Sin granjas configuradas. Agregue las que atiende este punto de control.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: context.textThemeSecondary,
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (_items.isNotEmpty)
              ..._items.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: context.surfaceCard,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: ListTile(
                        leading: Icon(
                          Icons.home_work_outlined,
                          color: AppColors.primaryDark.withValues(alpha: 0.85),
                        ),
                        title: Text(
                          e.etiqueta,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.textThemePrimary,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: 'Quitar granja',
                          onPressed: () => _quitarGranja(e.codigo),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _agregarGranja,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar granja'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.primaryDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
