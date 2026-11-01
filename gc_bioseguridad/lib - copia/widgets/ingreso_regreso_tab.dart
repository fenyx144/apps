import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/register_regreso_movimiento_screen.dart';
import '../services/ingreso_presencia_service.dart';
import '../services/storage_service.dart';
import '../utils/theme_colors.dart';
import '../widgets/grupo_presencia_list.dart';

/// Pestaña «Regreso» dentro de Ingreso de personal (salidas temporales).
class IngresoRegresoTab extends StatefulWidget {
  const IngresoRegresoTab({
    super.key,
    required this.granja,
    required this.granjaNombre,
    required this.fechaYmd,
  });

  final String granja;
  final String granjaNombre;
  final String fechaYmd;

  @override
  State<IngresoRegresoTab> createState() => _IngresoRegresoTabState();
}

class _IngresoRegresoTabState extends State<IngresoRegresoTab> {
  final _busquedaController = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    context.read<StorageService>().addListener(_onStorage);
    _busquedaController.addListener(() {
      setState(() => _busqueda = _busquedaController.text);
    });
  }

  void _onStorage() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    context.read<StorageService>().removeListener(_onStorage);
    _busquedaController.dispose();
    super.dispose();
  }

  List<GrupoPresencia> get _grupos {
    if (widget.granja.isEmpty) return const [];
    return IngresoPresenciaService.gruposPendientesRegreso(
      context.read<StorageService>(),
      granja: widget.granja,
    );
  }

  Future<void> _abrirGrupo(GrupoPresencia grupo) async {
    if (!grupo.hayFueraTemporal) return;
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RegisterRegresoMovimientoScreen(
          grupo: grupo,
          fechaYmd: widget.fechaYmd,
          granjaFallback: widget.granja,
          granjaNombreFallback: widget.granjaNombre,
        ),
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 16 + MediaQuery.viewPaddingOf(context).bottom;
    final filtrados = _grupos
        .where((g) => IngresoPresenciaService.grupoCoincideBusqueda(g, _busqueda))
        .toList();

    if (widget.granja.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomPad),
      children: [
        TextField(
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
        const SizedBox(height: 8),
        if (_grupos.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Sin pendientes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textThemeMuted),
            ),
          )
        else if (filtrados.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Sin coincidencias.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textThemeMuted),
            ),
          )
        else
          ...buildListaGruposPresenciaSeccionada(
            context: context,
            grupos: filtrados,
            modo: GrupoPresenciaListaModo.regreso,
            onTap: _abrirGrupo,
          ),
      ],
    );
  }
}
