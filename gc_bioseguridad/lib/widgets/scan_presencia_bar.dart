import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/documento_scan_flow.dart';
import '../services/ingreso_presencia_service.dart';
import '../services/storage_service.dart';
import '../utils/toast_helper.dart';
import 'bio_scan_tiles.dart';
import 'dni_input_dialog.dart';
import 'granja_campania_fields.dart';
import 'placa_input_dialog.dart';

/// Barra para escanear DNI o placa y resolver presencia local.
class ScanPresenciaBar extends StatefulWidget {
  const ScanPresenciaBar({
    super.key,
    this.granjaFormulario = '',
    required this.onCoincidencia,
    this.onDocumentoAMano,
    this.onPlacaAMano,
  });

  /// Granja del formulario; si va vacía, busca en todas las Mis granjas.
  final String granjaFormulario;
  final ValueChanged<PresenciaCoincidencia> onCoincidencia;

  /// Si se define, «Ingreso manual documento» no abre diálogo (p. ej. fila en tabla).
  final VoidCallback? onDocumentoAMano;

  /// Si se define, «Ingreso manual placa» no abre diálogo.
  final VoidCallback? onPlacaAMano;

  @override
  State<ScanPresenciaBar> createState() => _ScanPresenciaBarState();
}

class _ScanPresenciaBarState extends State<ScanPresenciaBar> {
  void _emitir(
    PresenciaCoincidencia c, {
    required String granjaFiltro,
    String? dniEscaneado,
    String? placaEscaneada,
  }) {
    if (!c.encontrado) {
      widget.onCoincidencia(
        PresenciaCoincidencia(
          escaneoDni: dniEscaneado,
          escaneoPlaca: placaEscaneada,
        ),
      );
      return;
    }
    if (c.ubicacion == PresenciaUbicacion.fueraTemporal) {
      showInfoToast(
        context,
        'Figura en salida temporal; puede confirmar la salida en la ficha.',
      );
    } else if (c.ubicacion == PresenciaUbicacion.dentro) {
      // Sin bloqueo: olvidos de registro son frecuentes en garita.
    }
    widget.onCoincidencia(c);
  }

  ({String granja, List<String> granjas}) _alcance(StorageService storage) {
    return alcancePresenciaGranjas(
      storage,
      granjaFormulario: widget.granjaFormulario,
    );
  }

  PresenciaCoincidencia _resolverDniConAlcance(
    StorageService storage,
    String dni, {
    required String granja,
    required List<String> granjas,
  }) {
    var c = IngresoPresenciaService.resolverPorDni(
      storage,
      dni: dni,
      granja: granja,
      granjas: granjas,
    );
    if (!c.encontrado && (granja.isNotEmpty || granjas.isNotEmpty)) {
      c = IngresoPresenciaService.resolverPorDni(storage, dni: dni);
    }
    return c;
  }

  PresenciaCoincidencia _resolverPlacaConAlcance(
    StorageService storage,
    String placa, {
    required String granja,
    required List<String> granjas,
  }) {
    var c = IngresoPresenciaService.resolverPorPlaca(
      storage,
      placa: placa,
      granja: granja,
      granjas: granjas,
    );
    if (!c.encontrado && (granja.isNotEmpty || granjas.isNotEmpty)) {
      c = IngresoPresenciaService.resolverPorPlaca(storage, placa: placa);
    }
    return c;
  }

  Future<void> _escanearDni() async {
    final dni = await escanearDocumentoPersona(context);
    if (dni == null || !mounted) return;
    final storage = context.read<StorageService>();
    final a = _alcance(storage);
    _emitir(
      _resolverDniConAlcance(
        storage,
        dni,
        granja: a.granja,
        granjas: a.granjas,
      ),
      granjaFiltro: a.granja,
      dniEscaneado: dni,
    );
  }

  Future<void> _placaCamara() async {
    final placa = await PlacaInputDialog.capture(context);
    if (placa == null || !mounted) return;
    _resolverPlaca(placa);
  }

  Future<void> _dniAMano() async {
    final dni = await DniInputDialog.show(context);
    if (dni == null || !mounted) return;
    final storage = context.read<StorageService>();
    final a = _alcance(storage);
    _emitir(
      _resolverDniConAlcance(
        storage,
        dni,
        granja: a.granja,
        granjas: a.granjas,
      ),
      granjaFiltro: a.granja,
      dniEscaneado: dni,
    );
  }

  Future<void> _placaAMano() async {
    final placa = await PlacaInputDialog.show(context);
    if (placa == null || !mounted) return;
    _resolverPlaca(placa);
  }

  void _resolverPlaca(String placa) {
    final storage = context.read<StorageService>();
    final a = _alcance(storage);
    _emitir(
      _resolverPlacaConAlcance(
        storage,
        placa,
        granja: a.granja,
        granjas: a.granjas,
      ),
      granjaFiltro: a.granja,
      placaEscaneada: placa,
    );
  }

  @override
  Widget build(BuildContext context) {
    return BioScanTiles(
      onScanDni: _escanearDni,
      onScanPlaca: _placaCamara,
      onManualDni: widget.onDocumentoAMano ?? _dniAMano,
      onManualPlaca: widget.onPlacaAMano ?? _placaAMano,
    );
  }
}
