import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';
import '../utils/mortality_design.dart';
import '../utils/theme_extensions.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/mortality_type_card.dart';
import '../widgets/mortality_register_icon.dart';
import '../widgets/produccion_registro_dialog.dart';
import '../widgets/transport_subtype_dialog.dart';
import 'mortality_form_screen.dart';

class MortalityTypeSelectScreen extends StatefulWidget {
  const MortalityTypeSelectScreen({super.key});

  @override
  State<MortalityTypeSelectScreen> createState() => _MortalityTypeSelectScreenState();
}

class _MortalityTypeSelectScreenState extends State<MortalityTypeSelectScreen> {
  List<MortalityType> _visibleTypes = MortalityType.values;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTiposPermitidos());
  }

  String _permisoParaTipo(MortalityType t) {
    switch (t) {
      case MortalityType.produccion: return 'verRegProduccion';
      case MortalityType.despacho:   return 'verRegDespacho';
      case MortalityType.incubacion: return 'verRegPI';
      case MortalityType.transporte: return 'verRegTransporte';
    }
  }

  void _loadTiposPermitidos() {
    final storage = context.read<StorageService>();
    final permisos = storage.getPermisos();
    final tipos = MortalityType.values.where((t) {
      return permisos[_permisoParaTipo(t)] == true;
    }).toList();
    if (mounted) {
      setState(() => _visibleTypes = tipos);
    }
  }

  Future<void> _onTypeSelected(BuildContext context, MortalityType type) async {
    if (type == MortalityType.transporte) {
      final subtipo = await showTransportSubtypeDialog(
        context: context,
        selected: 'transporte',
        accentColor: type.accentColor,
        transportGradient: type.iconGradient,
      );
      if (subtipo == null || !context.mounted) return;
      Get.to(
        () => MortalityFormScreen(
          type: type,
          initialSubtipoTransporte: subtipo,
        ),
        transition: Transition.rightToLeft,
      );
      return;
    }

    if (type == MortalityType.produccion) {
      final registro = await showProduccionRegistroDialog(
        context: context,
        selected: 'Crianza',
        accentColor: type.accentColor,
      );
      if (registro == null || !context.mounted) return;
      Get.to(
        () => MortalityFormScreen(
          type: type,
          initialOrigenAnalisis: registro,
        ),
        transition: Transition.rightToLeft,
      );
      return;
    }

    Get.to(
      () => MortalityFormScreen(type: type),
      transition: Transition.rightToLeft,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(
        context,
        'Registro Mortalidad',
        appIconWidget: const MortalityRegisterIcon(size: 22, color: Colors.white),
      ),
      drawer: const AppDrawer(),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Expanded(
                child: _visibleTypes.isEmpty
                    ? Center(
                        child: Text(
                          'No tiene tarjetas de mortalidad asignadas.\nContacte al administrador.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.mutedTextColor),
                        ),
                      )
                        : GridView.count(
                            crossAxisCount: 2,
                            mainAxisSpacing: 18,
                            crossAxisSpacing: 18,
                            childAspectRatio: 0.8,
                            children: [
                              for (var i = 0; i < _visibleTypes.length; i++)
                                MortalityTypeCard(
                                  type: _visibleTypes[i],
                                  animationDelay: i * 80,
                                  onTap: () => _onTypeSelected(context, _visibleTypes[i]),
                                ),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
