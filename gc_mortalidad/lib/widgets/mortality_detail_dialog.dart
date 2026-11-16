import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/motivo_mortalidad.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/text_utils.dart';
import '../utils/toast_helper.dart';
import '../screens/image_editor_screen.dart';
import 'searchable_select_dialog.dart';
import 'sexo_table.dart';

const int _maxPhotosPerDetail = 3;

Future<List<MortalityDetail>?> showMortalityDetailDialog({
  required BuildContext context,
  required MortalityType type,
  required List<MotivoMortalidad> motivos,
  MortalityDetail? existingMacho,
  MortalityDetail? existingHembra,
  bool sinMortalidad = false,
}) {
  return showDialog<List<MortalityDetail>>(
    context: context,
    builder: (ctx) => _MortalityDetailDialog(
      type: type,
      motivos: motivos,
      existingMacho: existingMacho,
      existingHembra: existingHembra,
      sinMortalidad: sinMortalidad,
    ),
  );
}

/// Datos editables de un sexo dentro del diálogo.
class _SexTabData {
  final TextEditingController cantidadController = TextEditingController();
  final TextEditingController observacionController = TextEditingController();

  /// Controllers de las etapas del proceso de despacho (solo tipo despacho).
  final Map<String, TextEditingController> etapaControllers = {};
  String? detailId;
  String? causaCodigo;
  String? causaNombre;
  String? tipoMuerte;
  final List<String> fotos = [];
  String? errorCantidad;
  String? errorCausa;

  void dispose() {
    cantidadController.dispose();
    observacionController.dispose();
    for (final c in etapaControllers.values) {
      c.dispose();
    }
    etapaControllers.clear();
  }

  int get cantidad => int.tryParse(cantidadController.text.trim()) ?? 0;

  int get procesoSuma => etapaControllers.values.fold(
    0,
    (sum, c) => sum + (int.tryParse(c.text.trim()) ?? 0),
  );

  /// Construye el mapa columna camelCase cantidad (solo valores > 0).
  Map<String, int> get procesoEtapas {
    final map = <String, int>{};
    etapaControllers.forEach((id, c) {
      final v = int.tryParse(c.text.trim()) ?? 0;
      if (v > 0) map[id] = v;
    });
    return map;
  }

  /// Muestra el bloque de observación/fotos si hay cantidad o contenido.
  bool get hasBlock =>
      procesoSuma > 0 ||
      cantidad > 0 ||
      observacionController.text.trim().isNotEmpty ||
      fotos.isNotEmpty;

  void clearErrors() {
    errorCantidad = null;
    errorCausa = null;
  }
}

class _MortalityDetailDialog extends StatefulWidget {
  final MortalityType type;
  final List<MotivoMortalidad> motivos;
  final MortalityDetail? existingMacho;
  final MortalityDetail? existingHembra;
  final bool sinMortalidad;

  const _MortalityDetailDialog({
    required this.type,
    required this.motivos,
    this.existingMacho,
    this.existingHembra,
    this.sinMortalidad = false,
  });

  @override
  State<_MortalityDetailDialog> createState() => _MortalityDetailDialogState();
}

class _MortalityDetailDialogState extends State<_MortalityDetailDialog> {
  final _picker = ImagePicker();
  late final _SexTabData _macho;
  late final _SexTabData _hembra;
  String? _errorGeneral;

  bool get _showCausa => mortalityShowsCausa(widget.type);
  bool get _isDespacho => widget.type == MortalityType.despacho;
  bool get _sinMortalidad => widget.sinMortalidad;
  bool get _isEditing =>
      widget.existingMacho != null || widget.existingHembra != null;

  ({String codigo, String nombre}) get _causaTransporte =>
      mortalityCausaTransporte(widget.motivos);

  @override
  void initState() {
    super.initState();
    _macho = _SexTabData();
    _hembra = _SexTabData();

    if (_isDespacho) {
      for (final tab in [_macho, _hembra]) {
        for (final etapa in kDespachoEtapas) {
          tab.etapaControllers[etapa.id] = TextEditingController();
        }
      }
    }

    if (widget.existingMacho != null) {
      _loadDetail(widget.existingMacho!, _macho);
    }
    if (widget.existingHembra != null) {
      _loadDetail(widget.existingHembra!, _hembra);
    }

    _macho.cantidadController.addListener(_onInputChanged);
    _hembra.cantidadController.addListener(_onInputChanged);
    if (_isDespacho) {
      for (final tab in [_macho, _hembra]) {
        for (final c in tab.etapaControllers.values) {
          c.addListener(_onInputChanged);
        }
      }
    }
  }

  @override
  void dispose() {
    _macho.cantidadController.removeListener(_onInputChanged);
    _hembra.cantidadController.removeListener(_onInputChanged);
    if (_isDespacho) {
      for (final tab in [_macho, _hembra]) {
        for (final c in tab.etapaControllers.values) {
          c.removeListener(_onInputChanged);
        }
      }
    }
    _macho.dispose();
    _hembra.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    if (!mounted) return;
    // En despacho la cantidad es la suma de las etapas (sin input manual).
    bool actividad(_SexTabData tab) =>
        _isDespacho ? tab.procesoSuma > 0 : tab.cantidad > 0;
    setState(() {
      for (final tab in [_macho, _hembra]) {
        if (actividad(tab) && tab.errorCantidad != null) {
          tab.errorCantidad = null;
        }
        if (actividad(tab) &&
            _showCausa &&
            (tab.causaCodigo?.isNotEmpty ?? false) &&
            tab.errorCausa != null) {
          tab.errorCausa = null;
        }
      }
      if ((actividad(_macho) || actividad(_hembra)) && _errorGeneral != null) {
        _errorGeneral = null;
      }
    });
  }

  void _unfocusKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _loadDetail(MortalityDetail detail, _SexTabData tab) {
    tab.detailId = detail.id;
    // En despacho la cantidad es la suma de las etapas (no hay campo manual).
    if (!_isDespacho) {
      tab.cantidadController.text = detail.cantidad > 0
          ? '${detail.cantidad}'
          : '';
    }
    tab.causaCodigo = detail.causaCodigo;
    tab.causaNombre = detail.causaNombre;
    tab.tipoMuerte = detail.tipoMuerte;
    tab.observacionController.text = detail.observacion ?? '';
    tab.fotos.addAll(detail.fotos);
    // Cargar etapas del despacho guardadas en el detalle.
    if (_isDespacho && detail.procesoEtapas.isNotEmpty) {
      detail.procesoEtapas.forEach((etapaId, value) {
        tab.etapaControllers[etapaId]?.text = '$value';
      });
    }
  }

  /// Valida ambos sexos y deja los mensajes en cada tab.
  bool _validateAll() {
    _errorGeneral = null;
    _macho.clearErrors();
    _hembra.clearErrors();

    if (_sinMortalidad) return true;

    // Despacho: la cantidad es la suma de las 6 etapas (solo se muestra),
    // por lo que no hay cuadre que validar. Solo se exige causa si se
    // registraron aves en ese sexo. Sin etapas = se puede guardar igual
    // (el switch de sin mortalidad cubre el caso 0 aves).
    if (_isDespacho) {
      var ok = true;
      for (final e in [(_macho, 'Machos'), (_hembra, 'Hembras')]) {
        final tab = e.$1;
        if (tab.procesoSuma > 0 &&
            _showCausa &&
            (tab.causaCodigo == null || tab.causaCodigo!.isEmpty)) {
          tab.errorCausa = 'Seleccione causa';
          ok = false;
        }
      }
      return ok;
    }

    final anyCantidad = _macho.cantidad > 0 || _hembra.cantidad > 0;
    if (!anyCantidad) {
      _errorGeneral = 'Ingrese cantidad en al menos un sexo';
      return false;
    }

    var ok = true;
    for (final e in [(_macho, 'Machos'), (_hembra, 'Hembras')]) {
      final tab = e.$1;
      final cant = tab.cantidad;

      if (cant <= 0) {
        continue;
      }

      if (_showCausa && (tab.causaCodigo == null || tab.causaCodigo!.isEmpty)) {
        tab.errorCausa = 'Seleccione causa';
        ok = false;
      }
    }
    return ok;
  }

  List<String> _errorLines() {
    final lines = <String>[];
    final general = _errorGeneral;
    if (general != null && general.trim().isNotEmpty) lines.add(general);
    for (final e in [(_macho, 'Machos'), (_hembra, 'Hembras')]) {
      final tab = e.$1;
      final label = e.$2;
      if (tab.errorCantidad != null) {
        lines.add('$label: ${tab.errorCantidad}');
      }
      if (tab.errorCausa != null) {
        lines.add('$label: ${tab.errorCausa}');
      }
    }
    return lines;
  }

  MortalityDetail _buildDetail(
    String sexo,
    _SexTabData tab, {
    String? id,
    required String grupoId,
  }) {
    String? causaCodigo;
    String? causaNombre;
    if (_showCausa) {
      causaCodigo = tab.causaCodigo;
      causaNombre = tab.causaNombre;
    } else if (widget.type == MortalityType.transporte && tab.cantidad > 0) {
      final c = _causaTransporte;
      causaCodigo = c.codigo;
      causaNombre = c.nombre;
    }
    return MortalityDetail(
      id: id ?? tab.detailId ?? const Uuid().v4(),
      sexo: sexo,
      // En despacho no se captura cantidad: equivale a la suma de las etapas.
      cantidad: _sinMortalidad
          ? 0
          : (_isDespacho ? tab.procesoSuma : tab.cantidad),
      causaCodigo: _sinMortalidad ? null : causaCodigo,
      causaNombre: _sinMortalidad ? null : causaNombre,
      tipoMuerte: _sinMortalidad ? null : tab.tipoMuerte,
      observacion: _observacionText(tab),
      fotos: List.from(tab.fotos),
      grupoId: grupoId,
      procesoEtapas: _sinMortalidad || !_isDespacho
          ? const {}
          : tab.procesoEtapas,
    );
  }

  String? _observacionText(_SexTabData tab) {
    final t = capitalizeText(tab.observacionController.text);
    return t.isEmpty ? null : t;
  }

  void _save() {
    _unfocusKeyboard();
    if (!_validateAll()) {
      setState(() {});
      return;
    }

    final grupoId =
        widget.existingMacho?.grupoId ??
        widget.existingHembra?.grupoId ??
        const Uuid().v4();

    final results = <MortalityDetail>[];
    if (_macho.hasBlock) {
      results.add(
        _buildDetail(
          'M',
          _macho,
          id: widget.existingMacho?.id,
          grupoId: grupoId,
        ),
      );
    }
    if (_hembra.hasBlock) {
      results.add(
        _buildDetail(
          'H',
          _hembra,
          id: widget.existingHembra?.id,
          grupoId: grupoId,
        ),
      );
    }
    Navigator.pop(context, results);
  }

  Future<void> _pickImage(_SexTabData tab) async {
    _unfocusKeyboard();
    if (tab.fotos.length >= _maxPhotosPerDetail) {
      showWarningToast(
        context,
        'Máximo $_maxPhotosPerDetail fotos por detalle',
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(
                  Icons.photo_camera_rounded,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(
                  Icons.photo_library_rounded,
                  color: AppColors.textSecondary,
                ),
                title: const Text('Galería'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    final picked = await _picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/mortalidad_images');
    if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);
    final dest = File(
      '${imagesDir.path}/img_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await File(picked.path).copy(dest.path);

    if (mounted) setState(() => tab.fotos.add(dest.path));
  }

  Future<void> _editPhoto(_SexTabData tab, int index) async {
    final edited = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(imageFile: XFile(tab.fotos[index])),
      ),
    );
    if (edited != null && mounted) {
      setState(() => tab.fotos[index] = edited.path);
    }
  }

  void _removePhoto(_SexTabData tab, int index) {
    setState(() => tab.fotos.removeAt(index));
  }

  Future<void> _openCausaDialog(_SexTabData tab, String sexoLabel) async {
    _unfocusKeyboard();
    if (widget.motivos.isEmpty) {
      showInfoToast(
        context,
        'No hay causas disponibles. Descargue desde el menú.',
      );
      return;
    }

    await showSearchableSelectDialog<MotivoMortalidad>(
      context: context,
      title: 'Causa — $sexoLabel',
      icon: Icons.medical_information_outlined,
      items: widget.motivos,
      emptyMessage: 'No hay causas disponibles.\nDescargue desde el menú.',
      getLabel: (m) => m.nombre,
      selectedValue: tab.causaCodigo,
      getValue: (m) => m.codigo,
      onSelected: (code) {
        if (code == null) return;
        MotivoMortalidad? found;
        for (final m in widget.motivos) {
          if (m.codigo == code) {
            found = m;
            break;
          }
        }
        setState(() {
          tab.causaCodigo = code;
          tab.causaNombre = found?.nombre ?? code;

          tab.errorCausa = null;
        });
      },
    );

    _unfocusKeyboard();
  }

  Widget _buildTable(BuildContext context, bool isDark, Color accent) {
    final rows = <Widget>[
      // Despacho: la cantidad se obtiene de la suma de las etapas, por lo que
      // no se muestra el campo manual de cantidad.
      if (!_isDespacho)
        SexoGridRow(
          label: 'Cantidad',
          cellM: SexoNumField(
            controller: _macho.cantidadController,
            accent: accent,
            hasError: _macho.errorCantidad != null,
            enabled: !_sinMortalidad,
          ),
          cellH: SexoNumField(
            controller: _hembra.cantidadController,
            accent: accent,
            hasError: _hembra.errorCantidad != null,
            enabled: !_sinMortalidad,
          ),
        ),
    ];

    if (_showCausa) {
      rows.add(
        SexoGridRow(
          label: 'Causa',
          cellM: SexoSelectCell(
            value: _macho.causaNombre,
            accent: accent,
            hasError: _macho.errorCausa != null,
            enabled: !_sinMortalidad,
            onTap: () => _openCausaDialog(_macho, 'Machos'),
          ),
          cellH: SexoSelectCell(
            value: _hembra.causaNombre,
            accent: accent,
            hasError: _hembra.errorCausa != null,
            enabled: !_sinMortalidad,
            onTap: () => _openCausaDialog(_hembra, 'Hembras'),
          ),
        ),
      );
    }
    rows.add(
      SexoGridRow(
        label: 'Tipo muerte',
        cellM: _buildTipoMuerteCell(_macho, accent),
        cellH: _buildTipoMuerteCell(_hembra, accent),
      ),
    );

    if (_isDespacho) {
      for (final etapa in kDespachoEtapas) {
        rows.add(
          SexoGridRow(
            label: etapa.nombre,
            icon: etapa.icon,
            cellM: SexoNumField(
              controller: _macho.etapaControllers[etapa.id]!,
              accent: accent,
              enabled: !_sinMortalidad,
            ),
            cellH: SexoNumField(
              controller: _hembra.etapaControllers[etapa.id]!,
              accent: accent,
              enabled: !_sinMortalidad,
            ),
          ),
        );
      }
      rows.add(
        SexoGridRow(
          label: 'Suma',
          cellM: _buildSumaCell(_macho, isDark, accent),
          cellH: _buildSumaCell(_hembra, isDark, accent),
        ),
      );
    }

    return SexoGridTable(accent: accent, rows: rows, errors: _errorLines());
  }

  Widget _buildTipoMuerteCell(_SexTabData tab, Color accent) {
    return SexoTipoMuerteCell(
      value: tab.tipoMuerte,
      accent: accent,
      onChanged: _sinMortalidad
          ? null
          : (v) => setState(() => tab.tipoMuerte = v),
    );
  }

  Widget _buildSumaCell(_SexTabData tab, bool isDark, Color accent) {
    final suma = tab.procesoSuma;
    if (suma <= 0) {
      return SexoStatusChip(
        text: '—',
        color: isDark ? Colors.white38 : Colors.grey.shade500,
      );
    }
    // Solo muestra el total de las etapas (sin verificación contra cantidad).
    return SexoStatusChip(text: '$suma', color: accent);
  }

  Widget _buildBlock(
    _SexTabData tab,
    String label,
    IconData icon,
    Color color,
  ) {
    return SexoObsFotoBlock(
      sexoLabel: label,
      icon: icon,
      accent: color,
      obsController: tab.observacionController,
      fotos: tab.fotos,
      maxFotos: _maxPhotosPerDetail,
      onAddFoto: () => _pickImage(tab),
      onEditFoto: (i) => _editPhoto(tab, i),
      onRemoveFoto: (i) => _removePhoto(tab, i),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.type.accentColor;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkCard : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Icon(
                    _isEditing ? Icons.edit_rounded : Icons.add_circle_outline,
                    color: accent,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _isEditing ? 'Editar detalle' : 'Agregar detalle',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      _unfocusKeyboard();
                      Navigator.pop(context);
                    },
                    icon: Icon(
                      Icons.close_rounded,
                      color: isDark ? Colors.white70 : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTable(context, isDark, accent),
                    const SizedBox(height: 10),
                    _buildBlock(
                      _macho,
                      'Machos',
                      Icons.male_rounded,
                      AppColors.maleDark,
                    ),
                    const SizedBox(height: 10),
                    _buildBlock(
                      _hembra,
                      'Hembras',
                      Icons.female_rounded,
                      AppColors.femaleDark,
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        _unfocusKeyboard();
                        Navigator.pop(context);
                      },
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text(
                        _isEditing ? 'Actualizar' : 'Agregar',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
