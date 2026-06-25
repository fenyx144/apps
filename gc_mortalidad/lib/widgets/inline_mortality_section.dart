import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/motivo_mortalidad.dart';
import '../models/mortality_detail.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import '../utils/toast_helper.dart';
import 'dashed_photo_slot.dart';
import 'searchable_select_dialog.dart';
import 'styled_select_field.dart';
import '../screens/image_editor_screen.dart';

const int _maxPhotosPerSex = 3;
const double _photoSize = 72;

class InlineMortalitySection extends StatefulWidget {
  final List<MortalityDetail> initialDetalles;
  final String? cantidadError;
  final String? causaError;
  final ValueChanged<List<MortalityDetail>> onChanged;
  final bool showCausa;
  final List<MotivoMortalidad> motivos;
  final Color tabAccentColor;

  const InlineMortalitySection({
    super.key,
    required this.initialDetalles,
    required this.onChanged,
    required this.tabAccentColor,
    this.cantidadError,
    this.causaError,
    this.showCausa = false,
    this.motivos = const [],
  });

  @override
  State<InlineMortalitySection> createState() => _InlineMortalitySectionState();
}

class _SexInlineData {
  final TextEditingController cantidadController = TextEditingController();
  final TextEditingController observacionController = TextEditingController();
  String? causaCodigo;
  String? causaNombre;
  final List<String> fotos = [];
  String? detailId;

  void dispose() {
    cantidadController.dispose();
    observacionController.dispose();
  }

  int get cantidad => int.tryParse(cantidadController.text.trim()) ?? 0;
}

class _InlineMortalitySectionState extends State<InlineMortalitySection>
    with SingleTickerProviderStateMixin {
  final _picker = ImagePicker();
  late final TabController _tabController;
  late final _SexInlineData _macho;
  late final _SexInlineData _hembra;

  @override
  void initState() {
    super.initState();
    _macho = _SexInlineData();
    _hembra = _SexInlineData();
    _loadInitial(widget.initialDetalles);

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);

    _macho.cantidadController.addListener(_notifyParent);
    _hembra.cantidadController.addListener(_notifyParent);
    _macho.observacionController.addListener(_notifyParent);
    _hembra.observacionController.addListener(_notifyParent);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      _unfocus();
    }
    setState(() {});
  }

  Tab _buildSexTabLabel({
    required int index,
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final selected = _tabController.index == index;
    final color = selected
        ? widget.tabAccentColor
        : (isDark ? Colors.white54 : Colors.grey.shade600);

    return Tab(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _loadInitial(List<MortalityDetail> detalles) {
    for (final d in detalles) {
      final tab = d.isMacho ? _macho : _hembra;
      tab.detailId ??= d.id;
      if (tab.cantidadController.text.isEmpty && d.cantidad > 0) {
        tab.cantidadController.text = '${d.cantidad}';
      } else if (d.cantidad > 0) {
        tab.cantidadController.text = '${tab.cantidad + d.cantidad}';
      }
      tab.causaCodigo = d.causaCodigo;
      tab.causaNombre = d.causaNombre;
      tab.fotos.addAll(d.fotos);
      if (tab.observacionController.text.isEmpty && (d.observacion?.isNotEmpty ?? false)) {
        tab.observacionController.text = d.observacion!;
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _macho.dispose();
    _hembra.dispose();
    super.dispose();
  }

  void _unfocus() => FocusManager.instance.primaryFocus?.unfocus();

  List<MortalityDetail> _buildDetalles() {
    final results = <MortalityDetail>[];
    if (_macho.cantidad > 0) {
      results.add(_detailFromTab('M', _macho));
    }
    if (_hembra.cantidad > 0) {
      results.add(_detailFromTab('H', _hembra));
    }
    return results;
  }

  MortalityDetail _detailFromTab(String sexo, _SexInlineData tab) {
    final obs = tab.observacionController.text.trim();
    return MortalityDetail(
      id: tab.detailId ?? const Uuid().v4(),
      sexo: sexo,
      cantidad: tab.cantidad,
      causaCodigo: widget.showCausa ? tab.causaCodigo : null,
      causaNombre: widget.showCausa ? tab.causaNombre : null,
      observacion: obs.isEmpty ? null : obs,
      fotos: List.from(tab.fotos),
    );
  }

  void _notifyParent() => widget.onChanged(_buildDetalles());

  Future<void> _openCausaDialog(_SexInlineData tab, String sexoLabel) async {
    _unfocus();
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
          _notifyParent();
        });
      },
    );
    if (mounted) _unfocus();
  }

  Future<void> _pickImage(_SexInlineData tab) async {
    _unfocus();
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

  Widget _buildSexTab({
    required _SexInlineData tab,
    required String sexoLabel,
    required Color accent,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : Colors.grey.shade50;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: tab.cantidadController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onTapOutside: (_) => _unfocus(),
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
                accentBorder: widget.cantidadError == null,
                errorText: widget.cantidadError,
                prefixIcon: Icon(Icons.numbers_rounded, color: AppColors.primary),
              ),
            ),
            if (widget.showCausa) ...[
              const SizedBox(height: 12),
              StyledSelectField(
                label: 'Causa de mortalidad',
                value: tab.causaNombre,
                placeholder: 'Seleccionar causa...',
                icon: Icons.medical_information_outlined,
                errorText: widget.causaError,
                flat: true,
                onTap: () => _openCausaDialog(tab, sexoLabel),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: tab.observacionController,
              maxLines: 2,
              maxLength: 250,
              onTapOutside: (_) => _unfocus(),
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 14,
              ),
              decoration: AppInputStyles.decoration(
                context,
                r: 12,
                labelText: 'Observación',
                hintText: 'Ingrese observaciones...',
                accentBorder: true,
                prefixIcon: Icon(Icons.notes_rounded, color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.photo_camera_outlined, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Fotos (${tab.fotos.length}/$_maxPhotosPerSex)',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: _photoSize + 4,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                children: [
                  ...tab.fotos.asMap().entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: DashedPhotoSlot(
                            size: _photoSize,
                            imagePath: e.value,
                            onAdd: () => _pickImage(tab),
                            onTapImage: () => _editPhoto(tab, e.key),
                            onDeleteImage: () => _removePhoto(tab, e.key),
                          ),
                        ),
                      ),
                  if (tab.fotos.length < _maxPhotosPerSex)
                    DashedPhotoSlot(
                      size: _photoSize,
                      onAdd: () => _pickImage(tab),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeTab = _tabController.index;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TabBar(
          controller: _tabController,
          onTap: (_) => _unfocus(),
          tabAlignment: TabAlignment.fill,
          padding: EdgeInsets.zero,
          dividerHeight: 0,
          indicatorColor: widget.tabAccentColor,
          labelColor: widget.tabAccentColor,
          unselectedLabelColor: isDark ? Colors.white54 : Colors.grey.shade600,
          labelPadding: EdgeInsets.zero,
          tabs: [
            _buildSexTabLabel(
              index: 0,
              icon: Icons.male_rounded,
              label: 'Machos',
              isDark: isDark,
            ),
            _buildSexTabLabel(
              index: 1,
              icon: Icons.female_rounded,
              label: 'Hembras',
              isDark: isDark,
            ),
          ],
        ),
        if (activeTab == 0)
          _buildSexTab(
            tab: _macho,
            sexoLabel: 'Machos',
            accent: widget.tabAccentColor,
          )
        else
          _buildSexTab(
            tab: _hembra,
            sexoLabel: 'Hembras',
            accent: widget.tabAccentColor,
          ),
      ],
    );
  }
}
