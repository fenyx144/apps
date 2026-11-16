import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/section_app_bar.dart';

/// Pantalla para elegir la granja de trabajo del usuario.
/// Lo que se guarda acá queda premarcado al abrir cualquiera de los formularios
/// de vacuna al agua: la granja con la campaña que le corresponde a la fecha del
/// registro. Si no hay granja elegida, los formularios arrancan como antes.
class MiGranjaScreen extends StatefulWidget {
  const MiGranjaScreen({super.key});

  @override
  State<MiGranjaScreen> createState() => _MiGranjaScreenState();
}

class _MiGranjaScreenState extends State<MiGranjaScreen> {
  /// Código de granja de 3 dígitos ('' si no hay ninguna elegida).
  String _granja = '';

  /// Nombre de la granja para la etiqueta del campo.
  String _nombre = '';

  @override
  void initState() {
    super.initState();
    final storage = context.read<StorageService>();
    _granja = GranjaCampaniaPicker.normGranja(storage.getGranjaTrabajo());
    if (_granja.isNotEmpty) {
      _nombre = GranjaCampaniaPicker.nombreDeGranja(
        storage.getProyeccion(),
        _granja,
      );
    }
  }

  Future<void> _elegirGranja() async {
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

    await storage.saveGranjaTrabajo(g3);
    if (!mounted) return;
    setState(() {
      _granja = g3;
      _nombre = (sel['granjaNombre'] ?? '').toString();
    });
    showSuccessToast(context, 'Granja de trabajo guardada');
  }

  Future<void> _quitarGranja() async {
    final storage = context.read<StorageService>();
    await storage.saveGranjaTrabajo('');
    if (!mounted) return;
    setState(() {
      _granja = '';
      _nombre = '';
    });
    showSuccessToast(context, 'Granja de trabajo eliminada');
  }

  /// Campañas que le tocarían hoy a la granja elegida. Sirve de vista previa de
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
        padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + MediaQuery.viewPaddingOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Granja de trabajo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.textThemePrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Se eligirá la granja automáticamente al abrir los formularios',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: context.textThemeSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: EvidenciaSelectField(
                    label: 'Granja',
                    value: _granja.isEmpty
                        ? ''
                        : GranjaCampaniaPicker.formatGranjaLabel(
                            _granja,
                            _nombre,
                          ),
                    placeholder: 'Ninguna',
                    icon: Icons.home_work_outlined,
                    onTap: _elegirGranja,
                  ),
                ),
                if (_granja.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _quitarGranja,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Quitar granja de trabajo',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          AppColors.error.withValues(alpha: 0.15),
                      foregroundColor: AppColors.error,
                      minimumSize: const Size(52, 52),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
