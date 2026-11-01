import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/ingreso_presencia_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_fields.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/grupo_presencia_list.dart';
import '../widgets/section_app_bar.dart';
import 'register_salida_movimiento_screen.dart';

/// Ingresos con personal dentro; solo registrar salidas.
class RegisterSalidaScreen extends StatefulWidget {
  const RegisterSalidaScreen({super.key});

  @override
  State<RegisterSalidaScreen> createState() => _RegisterSalidaScreenState();
}

class _RegisterSalidaScreenState extends State<RegisterSalidaScreen> {
  final DateTime _fecha = DateTime.now();
  final _busquedaController = TextEditingController();
  String _granja = '';
  String _granjaNombre = '';
  String _busqueda = '';
  StorageService? _storage;

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  @override
  void initState() {
    super.initState();
    _storage = context.read<StorageService>();
    _storage!.addListener(_refrescar);
    _aplicarGranjaDeTrabajo();
    _busquedaController.addListener(() {
      setState(() => _busqueda = _busquedaController.text);
    });
  }

  void _aplicarGranjaDeTrabajo() {
    final sel = granjaDeTrabajoSeleccion(
      context.read<StorageService>(),
      fechaYmd: _fechaYmd,
    );
    if (sel == null) return;
    _granja = sel.granja;
    _granjaNombre = sel.granjaNombre;
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    _storage?.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  List<GrupoPresencia> get _grupos {
    final s = context.read<StorageService>();
    return IngresoPresenciaService.gruposConPersonalDentro(
      s,
      granja: _granja,
    );
  }

  List<GrupoPresencia> get _gruposFiltrados => _grupos
      .where((g) => IngresoPresenciaService.grupoCoincideBusqueda(g, _busqueda))
      .toList();

  Future<void> _abrirGrupo(GrupoPresencia grupo) async {
    if (!grupo.hayDentro) return;

    final actualizado = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RegisterSalidaMovimientoScreen(
          grupo: grupo,
          fechaYmd: _fechaYmd,
          granjaFallback: _granja,
          granjaNombreFallback: _granjaNombre,
        ),
      ),
    );
    if (actualizado == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 24 + MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuSalida,
        sectionIcon: Icons.logout_rounded,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: EvidenciaSelectField(
                label: 'Granja',
                value: _granja.isEmpty
                    ? ''
                    : GranjaCampaniaPicker.formatGranjaLabel(
                        _granja,
                        _granjaNombre,
                      ),
                placeholder: 'Seleccione',
                icon: Icons.warehouse_rounded,
                maxLines: 3,
                onTap: () async {
                  final storage = context.read<StorageService>();
                  final sel = await GranjaCampaniaPicker.show(
                    context,
                    proyeccion: storage.getProyeccion(),
                    cencosGalpones: storage.getCencosGalpones(),
                    fechaYmd: _fechaYmd,
                  );
                  if (sel == null || !mounted) return;
                  setState(() {
                    _granja = (sel['granja3'] ?? '').toString();
                    _granjaNombre = (sel['granjaNombre'] ?? '').toString();
                  });
                },
              ),
            ),
            if (_granja.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _busquedaController,
                  decoration: InputDecoration(
                    labelText: 'Buscar',
                    hintText: 'Proveedor, DNI, placa…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _busqueda.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () => _busquedaController.clear(),
                          ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (_granja.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  if (_grupos.isEmpty) {
                    return Center(
                      child: Text(
                        'Sin ingresos abiertos.',
                        style: TextStyle(color: context.textThemeMuted),
                      ),
                    );
                  }
                  if (_gruposFiltrados.isEmpty) {
                    return Center(
                      child: Text(
                        'Sin coincidencias.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.textThemeMuted),
                      ),
                    );
                  }
                  return ListView(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, bottomPad),
                    children: buildListaGruposPresenciaSeccionada(
                      context: context,
                      grupos: _gruposFiltrados,
                      modo: GrupoPresenciaListaModo.salida,
                      onTap: _abrirGrupo,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
