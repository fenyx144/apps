import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/cenco.dart';
import '../services/storage_service.dart';
import '../services/theme_service.dart';
import '../utils/constants.dart';
import '../utils/theme_extensions.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_bar.dart';
import '../widgets/app_drawer.dart';
import '../widgets/searchable_select_dialog.dart';
import '../widgets/styled_select_field.dart';

class ConfigScreen extends StatefulWidget {
  const ConfigScreen({super.key});

  @override
  State<ConfigScreen> createState() => _ConfigScreenState();
}

class _ConfigScreenState extends State<ConfigScreen> {
  List<Cenco> _cencos = [];
  String? _selectedGranjaCodigo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final storage = context.read<StorageService>();
    _cencos = storage.getCencosWithEdadActual()
      ..sort((a, b) => a.codigo.compareTo(b.codigo));
    _selectedGranjaCodigo = storage.getDefaultGranja();
    setState(() => _loading = false);
  }

  Cenco? get _selectedCenco {
    if (_selectedGranjaCodigo == null) return null;
    return _cencos.firstWhere(
      (c) => c.granjaCodigo == _selectedGranjaCodigo,
      orElse: () => _cencos.firstWhere(
        (c) => c.codigo == _selectedGranjaCodigo,
        orElse: () => Cenco(codigo: '', nombre: '', edad: '0'),
      ),
    );
  }

  String _cleanGranjaNombre(Cenco c) {
    final nombre = c.nombre.trim();
    final cleaned = nombre.contains('C=')
        ? nombre.substring(0, nombre.indexOf('C=')).trim()
        : nombre;
    final g = c.granjaCodigo;
    if (g.isEmpty && cleaned.isEmpty) return c.codigo;
    if (g.isEmpty) return cleaned;
    if (cleaned.isEmpty) return g;
    return '$g - $cleaned';
  }

  Future<void> _pickGranja() async {
    if (_cencos.isEmpty) {
      showInfoToast(context, 'No hay granjas disponibles. Descargue desde el menu.');
      return;
    }

    await showSearchableSelectDialog<Cenco>(
      context: context,
      title: 'Granja por defecto',
      icon: Icons.home_work_outlined,
      items: _cencos,
      getLabel: (c) => _cleanGranjaNombre(c),
      selectedValue: _selectedGranjaCodigo,
      getValue: (c) => c.granjaCodigo,
      onSelected: (code) async {
        if (code == null) return;
        final storage = context.read<StorageService>();
        await storage.saveDefaultGranja(code);
        setState(() => _selectedGranjaCodigo = code);
        if (mounted) showSuccessToast(context, 'Granja por defecto guardada');
      },
    );
  }

  void _clearDefaultGranja() async {
    final storage = context.read<StorageService>();
    await storage.saveDefaultGranja('');
    setState(() => _selectedGranjaCodigo = null);
    if (mounted) showSuccessToast(context, 'Granja por defecto eliminada');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkTheme;

    return Scaffold(
      appBar: buildAppBar(
        context,
        'Configuracion',
        appIcon: Icons.settings_rounded,
      ),
      drawer: const AppDrawer(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Seccion: Granja por defecto ──
                  Text(
                    'Granja por defecto',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Se seleccionara automaticamente al registrar mortalidad',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: StyledSelectField(
                          label: 'Granja',
                          value: _selectedCenco != null
                              ? _cleanGranjaNombre(_selectedCenco!)
                              : null,
                          placeholder: 'Ninguna',
                          icon: Icons.home_work_outlined,
                          compact: true,
                          onTap: _pickGranja,
                        ),
                      ),
                      if (_selectedGranjaCodigo != null && _selectedGranjaCodigo!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _clearDefaultGranja,
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Eliminar granja por defecto',
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.error.withValues(alpha: 0.15),
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Divider(),
                  const SizedBox(height: 16),

                  // ── Seccion: Tema ──
                  Text(
                    'Apariencia',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cambia entre modo claro y oscuro',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white60 : AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildThemeTile(context, isDark),
                ],
              ),
            ),
    );
  }

  Widget _buildThemeTile(BuildContext context, bool isDark) {
    final themeService = context.watch<ThemeService>();

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.primary.withValues(alpha: 0.12),
        ),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            themeService.modeIcon,
            color: Colors.white,
            size: 22,
          ),
        ),
        title: Text(
          'Modo ${themeService.modeLabel}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : AppColors.textPrimary,
          ),
        ),
        subtitle: Text(
          'Tema del sistema',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white60 : AppColors.textSecondary,
          ),
        ),
        trailing: Switch.adaptive(
          value: themeService.mode == ThemeMode.dark,
          activeColor: AppColors.primary,
          onChanged: (_) => themeService.toggleTheme(),
        ),
        onTap: () => themeService.toggleTheme(),
      ),
    );
  }
}
