import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/motivo_mortalidad.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/mortality_design.dart';
import '../utils/theme_extensions.dart';
import '../utils/toast_helper.dart';
import 'dashed_photo_slot.dart';
import 'searchable_select_dialog.dart';
import 'styled_select_field.dart';
import '../screens/image_editor_screen.dart';

const int _maxPhotosPerDetail = 3;

Future<List<MortalityDetail>?> showMortalityDetailDialog({
  required BuildContext context,
  required MortalityType type,
  required List<MotivoMortalidad> motivos,
  MortalityDetail? existingMacho,
  MortalityDetail? existingHembra,
}) {
  return showDialog<List<MortalityDetail>>(
    context: context,
    builder: (ctx) => _MortalityDetailDialog(
      type: type,
      motivos: motivos,
      existingMacho: existingMacho,
      existingHembra: existingHembra,
    ),
  );
}

class _SexTabData {
  final TextEditingController cantidadController = TextEditingController();
  final TextEditingController observacionController = TextEditingController();
  final FocusNode cantidadFocus = FocusNode();
  final FocusNode observacionFocus = FocusNode();
  String? detailId;
  String? causaCodigo;
  String? causaNombre;
  final List<String> fotos = [];
  String? errorCantidad;
  String? errorCausa;

  void dispose() {
    cantidadFocus.dispose();
    observacionFocus.dispose();
    cantidadController.dispose();
    observacionController.dispose();
  }

  int get cantidad => int.tryParse(cantidadController.text.trim()) ?? 0;

  bool get hasContent => cantidad > 0 || fotos.isNotEmpty || (causaCodigo?.isNotEmpty ?? false);

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

  const _MortalityDetailDialog({
    required this.type,
    required this.motivos,
    this.existingMacho,
    this.existingHembra,
  });

  @override
  State<_MortalityDetailDialog> createState() => _MortalityDetailDialogState();
}

class _MortalityDetailDialogState extends State<_MortalityDetailDialog>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  late final TabController _tabController;
  late final _SexTabData _macho;
  late final _SexTabData _hembra;
  String? _errorGeneral;

  bool get _showCausa => mortalityShowsCausa(widget.type);

  ({String codigo, String nombre}) get _causaTransporte =>
      mortalityCausaTransporte(widget.motivos);
  bool get _isEditing =>
      widget.existingMacho != null || widget.existingHembra != null;

  @override
  void initState() {
    super.initState();
    _macho = _SexTabData();
    _hembra = _SexTabData();

    if (widget.existingMacho != null) {
      _loadDetail(widget.existingMacho!, _macho);
    }
    if (widget.existingHembra != null) {
      _loadDetail(widget.existingHembra!, _hembra);
    }

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.existingMacho == null && widget.existingHembra != null
          ? 1
          : 0,
    );
    _tabController.addListener(_onTabChanged);
    _macho.cantidadController.addListener(_onCantidadFieldChanged);
    _hembra.cantidadController.addListener(_onCantidadFieldChanged);
  }

  void _onCantidadFieldChanged() {
    var changed = false;

    if (_macho.cantidad > 0 && _macho.errorCantidad != null) {
      _macho.errorCantidad = null;
      changed = true;
    }
    if (_hembra.cantidad > 0 && _hembra.errorCantidad != null) {
      _hembra.errorCantidad = null;
      changed = true;
    }
    if ((_macho.cantidad > 0 || _hembra.cantidad > 0) && _errorGeneral != null) {
      _errorGeneral = null;
      changed = true;
    }

    if (changed && mounted) setState(() {});
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      _unfocusKeyboard();
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _macho.cantidadController.removeListener(_onCantidadFieldChanged);
    _hembra.cantidadController.removeListener(_onCantidadFieldChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _macho.dispose();
    _hembra.dispose();
    super.dispose();
  }

  void _unfocusKeyboard() => FocusManager.instance.primaryFocus?.unfocus();

  void _focusCantidad(_SexTabData tab) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tab.cantidadFocus.requestFocus();
    });
  }

  void _advanceFromCantidad(_SexTabData tab, String sexoLabel) {
    if (_showCausa && (tab.causaCodigo == null || tab.causaCodigo!.isEmpty)) {
      _openCausaDialog(tab, sexoLabel, focusObservacionAfter: true);
      return;
    }
    tab.observacionFocus.requestFocus();
  }

  void _advanceFromObservacion({required bool isLastTab}) {
    if (isLastTab) {
      _unfocusKeyboard();
      return;
    }
    _unfocusKeyboard();
    _tabController.animateTo(1);
    _focusCantidad(_hembra);
  }

  void _loadDetail(MortalityDetail detail, _SexTabData tab) {
    tab.detailId = detail.id;
    tab.cantidadController.text = detail.cantidad > 0 ? '${detail.cantidad}' : '';
    tab.causaCodigo = detail.causaCodigo;
    tab.causaNombre = detail.causaNombre;
    tab.observacionController.text = detail.observacion ?? '';
    tab.fotos.addAll(detail.fotos);
  }

  bool _validateTab(_SexTabData tab, String sexoLabel) {
    tab.clearErrors();
    final cant = tab.cantidad;

    if (cant <= 0) {
      tab.errorCantidad = 'Ingrese una cantidad válida';
      return false;
    }
    if (_showCausa && (tab.causaCodigo == null || tab.causaCodigo!.isEmpty)) {
      tab.errorCausa = 'Seleccione causa';
      return false;
    }
    return true;
  }

  bool _validateAll() {
    _errorGeneral = null;
    _macho.clearErrors();
    _hembra.clearErrors();

    if (_macho.cantidad <= 0 && _hembra.cantidad <= 0) {
      _errorGeneral = 'Ingrese cantidad en al menos una pestaña';
      setState(() {});
      return false;
    }

    var valid = true;
    if (_macho.cantidad > 0) {
      if (!_validateTab(_macho, 'Machos')) {
        valid = false;
        if (_tabController.index != 0) _tabController.animateTo(0);
      }
    }
    if (_hembra.cantidad > 0) {
      if (!_validateTab(_hembra, 'Hembras')) {
        valid = false;
        if (_tabController.index != 1) _tabController.animateTo(1);
      }
    }

    setState(() {});
    return valid;
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
      cantidad: tab.cantidad,
      causaCodigo: causaCodigo,
      causaNombre: causaNombre,
      observacion: _observacionText(tab),
      fotos: List.from(tab.fotos),
      grupoId: grupoId,
    );
  }

  String? _observacionText(_SexTabData tab) {
    final t = tab.observacionController.text.trim();
    return t.isEmpty ? null : t;
  }

  void _save() {
    _unfocusKeyboard();
    if (!_validateAll()) return;

    final grupoId = widget.existingMacho?.grupoId ??
        widget.existingHembra?.grupoId ??
        const Uuid().v4();

    final results = <MortalityDetail>[];
    if (_macho.cantidad > 0) {
      results.add(
        _buildDetail('M', _macho, id: widget.existingMacho?.id, grupoId: grupoId),
      );
    }
    if (_hembra.cantidad > 0) {
      results.add(
        _buildDetail('H', _hembra, id: widget.existingHembra?.id, grupoId: grupoId),
      );
    }
    Navigator.pop(context, results);
  }

  Future<void> _pickImage(_SexTabData tab) async {
    _unfocusKeyboard();
    if (tab.fotos.length >= _maxPhotosPerDetail) {
      showWarningToast(context, 'Máximo $_maxPhotosPerDetail fotos por detalle');
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
                leading: const Icon(Icons.photo_camera_rounded, color: AppColors.primary),
                title: const Text('Cámara'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: AppColors.primary),
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

  Future<void> _openCausaDialog(
    _SexTabData tab,
    String sexoLabel, {
    bool focusObservacionAfter = false,
  }) async {
    _unfocusKeyboard();
    if (widget.motivos.isEmpty) {
      showInfoToast(context, 'No hay causas disponibles. Descargue desde el menú.');
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
        if (focusObservacionAfter) {
          tab.observacionFocus.requestFocus();
        }
      },
    );

    if (mounted && !focusObservacionAfter) _unfocusKeyboard();
  }

  Widget _buildTabContent({
    required _SexTabData tab,
    required String sexoLabel,
    required Color accent,
    required bool isLastTab,
    String? generalError,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: tab.cantidadController,
            focusNode: tab.cantidadFocus,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _advanceFromCantidad(tab, sexoLabel),
            onTapOutside: (_) => _unfocusKeyboard(),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: AppInputStyles.decoration(
              context,
              r: 12,
              labelText: 'Cantidad',
              hintText: 'Ej: 5',
              errorText: tab.errorCantidad ?? generalError,
              accentBorder: tab.errorCantidad == null && generalError == null,
              prefixIcon: const Icon(Icons.numbers_rounded, color: AppColors.primary),
            ),
          ),
          if (_showCausa) ...[
            const SizedBox(height: 14),
            StyledSelectField(
              label: 'Causa de mortalidad',
              value: tab.causaNombre,
              placeholder: 'Seleccionar causa...',
              icon: Icons.medical_information_outlined,
              errorText: tab.errorCausa,
              onTap: () => _openCausaDialog(tab, sexoLabel),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: tab.observacionController,
            focusNode: tab.observacionFocus,
            maxLines: 2,
            maxLength: 250,
            textInputAction: isLastTab ? TextInputAction.done : TextInputAction.next,
            onSubmitted: (_) => _advanceFromObservacion(isLastTab: isLastTab),
            onTapOutside: (_) => _unfocusKeyboard(),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontSize: 14,
            ),
            decoration: AppInputStyles.decoration(
              context,
              r: 12,
              labelText: 'Observación',
              hintText: 'Notas para $sexoLabel...',
              accentBorder: true,
              prefixIcon: const Icon(Icons.notes_rounded, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Fotos (${tab.fotos.length}/$_maxPhotosPerDetail)',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ...tab.fotos.asMap().entries.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: DashedPhotoSlot(
                          imagePath: e.value,
                          onAdd: () => _pickImage(tab),
                          onTapImage: () => _editPhoto(tab, e.key),
                          onDeleteImage: () => _removePhoto(tab, e.key),
                        ),
                      ),
                    ),
                if (tab.fotos.length < _maxPhotosPerDetail)
                  DashedPhotoSlot(onAdd: () => _pickImage(tab)),
              ],
            ),
          ),
        ],
      ),
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
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TabBar(
                controller: _tabController,
                onTap: (_) => _unfocusKeyboard(),
                indicatorColor: accent,
                labelColor: accent,
                unselectedLabelColor: isDark ? Colors.white54 : Colors.grey.shade600,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.male_rounded, size: 20),
                    text: 'Machos',
                  ),
                  Tab(
                    icon: Icon(Icons.female_rounded, size: 20),
                    text: 'Hembras',
                  ),
                ],
              ),
            ),
            Flexible(
              child: IndexedStack(
                index: _tabController.index,
                children: [
                  _buildTabContent(
                    tab: _macho,
                    sexoLabel: 'Machos',
                    accent: accent,
                    isLastTab: false,
                    generalError: _errorGeneral,
                  ),
                  _buildTabContent(
                    tab: _hembra,
                    sexoLabel: 'Hembras',
                    accent: accent,
                    isLastTab: true,
                    generalError: _errorGeneral,
                  ),
                ],
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
