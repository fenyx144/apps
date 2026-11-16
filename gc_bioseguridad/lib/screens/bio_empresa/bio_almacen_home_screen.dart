import 'package:flutter/material.dart';

import '../../services/bio_empresa_api.dart' show BioEmpresaApi, BioEmpresaApiException;
import '../../utils/constants.dart' show AppColors, AppConstants;
import '../../widgets/app_drawer.dart';
import '../../widgets/section_app_bar.dart';
import 'bio_consumo_screen.dart';
import 'bio_relevo_screen.dart';

class BioAlmacenHomeScreen extends StatefulWidget {
  const BioAlmacenHomeScreen({super.key});

  @override
  State<BioAlmacenHomeScreen> createState() => _BioAlmacenHomeScreenState();
}

class _BioAlmacenHomeScreenState extends State<BioAlmacenHomeScreen> {
  final _api = BioEmpresaApi();
  bool _loading = true;
  String? _error;
  List<dynamic> _entregas = [];
  List<dynamic> _stock = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!await _api.appConSesion()) {
        setState(() {
          _loading = false;
          _error = 'Inicie sesión en la app para usar almacén.';
        });
        return;
      }
      final ctx = await _api.get('/almacen/campo-context');
      final data = ctx['data'] as Map<String, dynamic>;
      setState(() {
        _entregas = data['entregas_pendientes'] as List<dynamic>? ?? [];
        _stock = data['stock'] as List<dynamic>? ?? [];
        _loading = false;
      });
    } on BioEmpresaApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.code == 'unauthorized'
            ? 'Sin acceso a la API bioseguridad (${AppConstants.bioEmpresaApiBase}).\n${e.message}'
            : '${e.message}\n\nURL: ${AppConstants.bioEmpresaApiBase}';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error =
            'No se pudo conectar con ${AppConstants.bioEmpresaApiBase}.\n'
            'Revise red y que el servicio esté en el mismo servidor que el login.\n$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: const SectionAppBar(
        title: 'Almacén',
        sectionIcon: Icons.inventory_2_outlined,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_outlined,
                            size: 48, color: theme.colorScheme.error),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Entregas pendientes (${_entregas.length})',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      if (_entregas.isEmpty)
                        const Text('No hay entregas pendientes de recepción.'),
                      ..._entregas.take(20).map((e) {
                        final m = e as Map<String, dynamic>;
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.local_shipping_outlined),
                            title: Text('Entrega #${m['id']} · ${m['fecha']}'),
                            subtitle: Text((m['observacion'] ?? '').toString()),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                      Text('Stock (${_stock.length} líneas)',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ..._stock.take(30).map((s) {
                        final m = s as Map<String, dynamic>;
                        return ListTile(
                          dense: true,
                          title: Text('${m['insumo_nombre']} (${m['insumo_codigo']})'),
                          trailing: Text('${m['stock']} ${m['unidad']}'),
                        );
                      }),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () async {
                          final ok = await Navigator.of(context).push<bool>(
                            MaterialPageRoute<bool>(
                              builder: (_) => const BioConsumoScreen(),
                            ),
                          );
                          if (ok == true) _cargar();
                        },
                        icon: const Icon(Icons.output_rounded),
                        label: const Text('Registrar consumo'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const BioRelevoScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Relevo de turno'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
