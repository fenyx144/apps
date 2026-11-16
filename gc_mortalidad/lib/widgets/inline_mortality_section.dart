import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/motivo_mortalidad.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/text_utils.dart';
import '../utils/toast_helper.dart';
import 'searchable_select_dialog.dart';
import 'sexo_table.dart';
import '../screens/image_editor_screen.dart';

const int _maxPhotosPerSex = 3;

/// Captura directa en la pantalla de registro (Incubación, Transporte y
/// Producción Necropsia/Laboratorio) en estilo tabla de 2 columnas
/// (Machos | Hembras), sin pestañas ni botones +/−.
class InlineMortalitySection extends StatefulWidget {
  final List<MortalityDetail> initialDetalles;
  final String? cantidadError;
  final String? causaError;
  final ValueChanged<List<MortalityDetail>> onChanged;
  final bool showCausa;
  final List<MotivoMortalidad> motivos;
  final Color tabAccentColor;

  /// Si es true, las cantidades se bloquean (registro sin mortalidad).
  final bool sinMortalidad;

  const InlineMortalitySection({
    super.key,
    required this.initialDetalles,
    required this.onChanged,
    required this.tabAccentColor,
    this.cantidadError,
    this.causaError,
    this.showCausa = false,
    this.motivos = const [],
    this.sinMortalidad = false,
  });

  @override
  State<InlineMortalitySection> createState() => _InlineMortalitySectionState();
}

class _SexInlineData {
  final TextEditingController cantidadController = TextEditingController();
  final TextEditingController observacionController = TextEditingController();
  String? tipoMuerte;
  String? causaCodigo;
  String? causaNombre;
  final List<String> fotos = [];
  String? detailId;

  void dispose() {
    cantidadController.dispose();
    observacionController.dispose();
  }

  int get cantidad => int.tryParse(cantidadController.text.trim()) ?? 0;

  bool get hasContent =>
      cantidad > 0 ||
      observacionController.text.trim().isNotEmpty ||
      fotos.isNotEmpty;
}

class _InlineMortalitySectionState extends State<InlineMortalitySection> {
  final _picker = ImagePicker();
  late final _SexInlineData _macho;
  late final _SexInlineData _hembra;

  @override
  void initState() {
    super.initState();
    _macho = _SexInlineData();
    _hembra = _SexInlineData();
    _loadInitial(widget.initialDetalles);

    _macho.cantidadController.addListener(_onCantidadChanged);
    _hembra.cantidadController.addListener(_onCantidadChanged);
    _macho.observacionController.addListener(_notifyParent);
    _hembra.observacionController.addListener(_notifyParent);
  }

  @override
  void dispose() {
    _macho.cantidadController.removeListener(_onCantidadChanged);
    _hembra.cantidadController.removeListener(_onCantidadChanged);
    _macho.observacionController.removeListener(_notifyParent);
    _hembra.observacionController.removeListener(_notifyParent);
    _macho.dispose();
    _hembra.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(InlineMortalitySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sinMortalidad && !oldWidget.sinMortalidad) {
      _macho.cantidadController.removeListener(_onCantidadChanged);
      _hembra.cantidadController.removeListener(_onCantidadChanged);
      _macho.cantidadController.text = '';
      _hembra.cantidadController.text = '';
      _macho.cantidadController.addListener(_onCantidadChanged);
      _hembra.cantidadController.addListener(_onCantidadChanged);
      _macho.tipoMuerte = null;
      _hembra.tipoMuerte = null;
      if (widget.showCausa) {
        _macho.causaCodigo = null;
        _macho.causaNombre = null;
        _hembra.causaCodigo = null;
        _hembra.causaNombre = null;
      }
    }
  }

  void _onCantidadChanged() => _notifyParent();

  void _notifyParent() => widget.onChanged(_buildDetalles());

  void _loadInitial(List<MortalityDetail> detalles) {
    for (final d in detalles) {
      final tab = d.isMacho ? _macho : _hembra;
      tab.detailId ??= d.id;
      if (tab.cantidadController.text.isEmpty && d.cantidad > 0) {
        tab.cantidadController.text = '${d.cantidad}';
      } else if (d.cantidad > 0) {
        tab.cantidadController.text = '${tab.cantidad + d.cantidad}';
      }
      tab.tipoMuerte = d.tipoMuerte;
      tab.causaCodigo = d.causaCodigo;
      tab.causaNombre = d.causaNombre;
      tab.fotos.addAll(d.fotos);
      if (tab.observacionController.text.isEmpty &&
          (d.observacion?.isNotEmpty ?? false)) {
        tab.observacionController.text = d.observacion!;
      }
    }
  }

  List<MortalityDetail> _buildDetalles() {
    final results = <MortalityDetail>[];
    if (_macho.hasContent) {
      results.add(_detailFromTab('M', _macho));
    }
    if (_hembra.hasContent) {
      results.add(_detailFromTab('H', _hembra));
    }
    return results;
  }

  MortalityDetail _detailFromTab(String sexo, _SexInlineData tab) {
    final obs = capitalizeText(tab.observacionController.text);
    final sinMort = widget.sinMortalidad;
    return MortalityDetail(
      id: tab.detailId ?? const Uuid().v4(),
      sexo: sexo,
      cantidad: sinMort ? 0 : tab.cantidad,
      causaCodigo: sinMort || !widget.showCausa ? null : tab.causaCodigo,
      tipoMuerte: sinMort ? null : tab.tipoMuerte,
      causaNombre: sinMort || !widget.showCausa ? null : tab.causaNombre,
      observacion: obs.isEmpty ? null : obs,
      fotos: List.from(tab.fotos),
    );
  }

  Future<void> _openCausaDialog(_SexInlineData tab, String sexoLabel) async {
    FocusManager.instance.primaryFocus?.unfocus();
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
          _notifyParent();
        });
      },
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _pickImage(_SexInlineData tab) async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (tab.fotos.length >= _maxPhotosPerSex) {
      showWarningToast(context, 'Máximo $_maxPhotosPerSex fotos');
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

    if (!mounted) return;
    setState(() {
      tab.fotos.add(dest.path);
      _notifyParent();
    });
  }

  Future<void> _editPhoto(_SexInlineData tab, int index) async {
    final edited = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(imageFile: XFile(tab.fotos[index])),
      ),
    );
    if (edited != null && mounted) {
      setState(() {
        tab.fotos[index] = edited.path;
        _notifyParent();
      });
    }
  }

  void _removePhoto(_SexInlineData tab, int index) {
    setState(() {
      tab.fotos.removeAt(index);
      _notifyParent();
    });
  }

  List<String> get _errorLines {
    final lines = <String>[];
    final cant = widget.cantidadError;
    if (cant != null && cant.trim().isNotEmpty) lines.add(cant);
    final causa = widget.causaError;
    if (widget.showCausa && causa != null && causa.trim().isNotEmpty) {
      lines.add(causa);
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.tabAccentColor;
    final enabled = !widget.sinMortalidad;

    final rows = <Widget>[
      SexoGridRow(
        label: 'Cantidad',
        cellM: SexoNumField(
          controller: _macho.cantidadController,
          accent: accent,
          hasError: widget.cantidadError != null,
          enabled: enabled,
        ),
        cellH: SexoNumField(
          controller: _hembra.cantidadController,
          accent: accent,
          hasError: widget.cantidadError != null,
          enabled: enabled,
        ),
      ),
      if (widget.showCausa)
        SexoGridRow(
          label: 'Causa',
          cellM: SexoSelectCell(
            value: _macho.causaNombre,
            accent: accent,
            hasError: widget.causaError != null,
            enabled: enabled,
            onTap: () => _openCausaDialog(_macho, 'Machos'),
          ),
          cellH: SexoSelectCell(
            value: _hembra.causaNombre,
            accent: accent,
            hasError: widget.causaError != null,
            enabled: enabled,
            onTap: () => _openCausaDialog(_hembra, 'Hembras'),
          ),
        ),
      SexoGridRow(
        label: 'Tipo muerte',
        cellM: SexoTipoMuerteCell(
          value: _macho.tipoMuerte,
          accent: accent,
          onChanged: enabled
              ? (v) => setState(() {
                  _macho.tipoMuerte = v;
                  _notifyParent();
                })
              : null,
        ),
        cellH: SexoTipoMuerteCell(
          value: _hembra.tipoMuerte,
          accent: accent,
          onChanged: enabled
              ? (v) => setState(() {
                  _hembra.tipoMuerte = v;
                  _notifyParent();
                })
              : null,
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SexoGridTable(accent: accent, rows: rows, errors: _errorLines),
        const SizedBox(height: 10),
        SexoObsFotoBlock(
          sexoLabel: 'Machos',
          icon: Icons.male_rounded,
          accent: AppColors.maleDark,
          obsController: _macho.observacionController,
          fotos: _macho.fotos,
          maxFotos: _maxPhotosPerSex,
          onAddFoto: () => _pickImage(_macho),
          onEditFoto: (i) => _editPhoto(_macho, i),
          onRemoveFoto: (i) => _removePhoto(_macho, i),
        ),
        const SizedBox(height: 10),
        SexoObsFotoBlock(
          sexoLabel: 'Hembras',
          icon: Icons.female_rounded,
          accent: AppColors.femaleDark,
          obsController: _hembra.observacionController,
          fotos: _hembra.fotos,
          maxFotos: _maxPhotosPerSex,
          onAddFoto: () => _pickImage(_hembra),
          onEditFoto: (i) => _editPhoto(_hembra, i),
          onRemoveFoto: (i) => _removePhoto(_hembra, i),
        ),
      ],
    );
  }
}
