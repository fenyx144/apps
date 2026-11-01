import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../services/catalog_sync_service.dart';
import '../services/storage_service.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';
import '../utils/dialog_helper.dart';
import '../utils/galpones_resolver.dart';
import '../utils/record_id.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/evidencia_select_field.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/process_tree_dialog.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

class RegisterEvidenciaScreen extends StatefulWidget {
  const RegisterEvidenciaScreen({super.key});

  @override
  State<RegisterEvidenciaScreen> createState() => _RegisterEvidenciaScreenState();
}

class _RegisterEvidenciaScreenState extends State<RegisterEvidenciaScreen> {
  DateTime _fecha = DateTime.now();
  String _tareaKey = '';
  String _procesoNombre = '';
  String _granja = '';
  String _granjaNombre = '';
  String _campania = '';
  String _galpon = '';
  final _obsController = TextEditingController();
  final List<String?> _imagePaths = [null, null, null];
  List<Map<String, dynamic>> _galpones = [];
  bool _cargandoProyeccion = false;

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  String _fmtDateDisplay(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  String get _campaniaEfectiva {
    if (_campania.isNotEmpty) return _campania;
    if (_granja.isNotEmpty) {
      return GranjaCampaniaPicker.campaniaFromCodigo(_granja);
    }
    return '';
  }

  String get _granjaLabel {
    if (_granja.isEmpty) return '';
    return GranjaCampaniaPicker.formatGranjaLabel(_granja, _granjaNombre);
  }

  String get _campaniaDisplay {
    final c = _campaniaEfectiva;
    return c.isEmpty ? '' : GranjaCampaniaPicker.padCampania(c);
  }

  List<String> get _galponCodes => _galpones
      .map((g) => (g['tcodint'] ?? '').toString())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _reloadProyeccionPorFecha() async {
    if (_cargandoProyeccion) return;
    setState(() => _cargandoProyeccion = true);
    try {
      final storage = context.read<StorageService>();
      await CatalogSyncService().syncProyeccion(
        storage: storage,
        fecha: _fmtDate(_fecha),
      );
      if (mounted) {
        setState(() {
          _granja = '';
          _granjaNombre = '';
          _campania = '';
          _galpon = '';
          _galpones = [];
        });
      }
    } catch (_) {
      // Sin red o error: se mantiene la proyección guardada.
    } finally {
      if (mounted) setState(() => _cargandoProyeccion = false);
    }
  }

  void _loadGalpones(StorageService storage) {
    if (_granja.isEmpty) {
      setState(() => _galpones = []);
      return;
    }

    final gps = GalponesResolver.resolveOffline(
      granjaCodigo: _granja,
      campania: _campaniaEfectiva,
      galponesPorGranja: storage.getGalponesPorGranjaMapLocal(),
      galponesPorCenco: storage.getGalponesPorCencoLocal(),
      cencosLista: storage.getCencosListaLocal(),
    );

    setState(() => _galpones = gps);

    if (gps.isEmpty && !storage.hasCencosGalponesLocal()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showErrorToast(
            context,
            'No hay galpones descargados. Use el menú → Descargar catálogos.',
          );
        }
      });
    }
  }

  Map<String, dynamic> _buildRecord(StorageService storage) {
    final campania = _campaniaEfectiva;
    final imagenes =
        _imagePaths.whereType<String>().where((p) => p.isNotEmpty).toList();
    final usuario = storage.getUserCodeSync() ?? '';
    final recordId = const Uuid().v4();
    return {
      'id': recordId,
      'fecha': _fmtDate(_fecha),
      'tareaKey': _tareaKey,
      'procesoNombre': _procesoNombre,
      'granja': GranjaCampaniaPicker.normGranja(_granja),
      'granjaNombre': _granjaNombre,
      'campania': campania,
      'galpon': _galpon,
      'obs': _obsController.text.trim(),
      'imagenes': imagenes,
      'synced': false,
      'guardado_backend': false,
      'usuario': usuario,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  void _clearForm() {
    setState(() {
      _fecha = DateTime.now();
      _tareaKey = '';
      _procesoNombre = '';
      _granja = '';
      _granjaNombre = '';
      _campania = '';
      _galpon = '';
      _galpones = [];
      _obsController.clear();
      _imagePaths[0] = null;
      _imagePaths[1] = null;
      _imagePaths[2] = null;
    });
  }

  Future<bool> _hasInternetFast() async {
    try {
      final r = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 4));
      return r.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _guardar() async {
    if (_tareaKey.isEmpty) {
      showErrorToast(context, 'Seleccione el proceso.');
      return;
    }
    if (_granja.isEmpty) {
      showErrorToast(context, 'Seleccione granja y campaña.');
      return;
    }
    final campania = _campaniaEfectiva;
    if (campania.isEmpty) {
      showErrorToast(context, 'Seleccione granja y campaña.');
      return;
    }
    final imagenes =
        _imagePaths.whereType<String>().where((p) => p.isNotEmpty).toList();
    if (imagenes.isEmpty) {
      showErrorToast(context, 'Adjunte al menos una imagen.');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 100));

    final storage = context.read<StorageService>();
    final record = _buildRecord(storage);

    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        await storage.saveRecord(record);
        record['synced'] = false;

        if (!await _hasInternetFast()) return;

        if (!mounted) return;

        final close = showChickenLoadingDialog(context, 'Enviando registro…');
        try {
          final api = ApiService();
          final result = await api.uploadEvidencia(record);
          debugPrint(
            '[guardar_evidencia] respuesta: $result '
            '(id=${EvidenciaRecordId.of(record)})',
          );
          if (result['success'] == true) {
            await storage.markRecordAsSynced({
              ...record,
              'id': EvidenciaRecordId.of(record),
              'guardado_backend': true,
            });
            await storage.setLastSyncDate();
            record['synced'] = true;
            record['guardado_backend'] = true;
          }
        } catch (_) {
          // Falló el envío; el registro ya quedó guardado en local.
        } finally {
          close();
        }
      },
    );

    if (!mounted || !saved) return;
    if (record['synced'] == true) {
      showSuccessToast(context, 'Registro guardado y enviado');
    } else {
      showSuccessToast(
        context,
        'Registro guardado localmente (pendiente de subir)',
      );
    }
    _clearForm();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final arbol = storage.getArbolProcesos();
    final proyeccion = storage.getProyeccion();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuRegistro,
        sectionIcon: Icons.add_a_photo_outlined,
        actions: [AppBarSaveButton(onPressed: _guardar)],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EvidenciaSelectField(
              label: 'Fecha',
              value: _fmtDateDisplay(_fecha),
              placeholder: 'Seleccione fecha',
              icon: Icons.calendar_today_outlined,
              onTap: _cargandoProyeccion
                  ? null
                  : () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _fecha,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (d != null && d != _fecha) {
                        setState(() => _fecha = d);
                        await _reloadProyeccionPorFecha();
                      }
                    },
            ),
            if (_cargandoProyeccion) ...[
              const SizedBox(height: 6),
              const LinearProgressIndicator(minHeight: 2),
            ],
            const SizedBox(height: 12),
            EvidenciaSelectField(
              label: 'Proceso',
              value: _procesoNombre,
              placeholder: 'Toca para seleccionar',
              icon: Icons.account_tree_outlined,
              onTap: () async {
                final sel = await ProcessTreeDialog.show(context, arbol);
                if (sel != null) {
                  setState(() {
                    _tareaKey = sel['tareaKey'] ?? '';
                    _procesoNombre = sel['procesoNombre'] ?? '';
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: EvidenciaSelectField(
                    label: 'Granja',
                    value: _granjaLabel,
                    placeholder: 'Seleccione',
                    icon: Icons.warehouse_outlined,
                    enabled: !_cargandoProyeccion,
                    onTap: () async {
                      final sel = await GranjaCampaniaPicker.show(
                        context,
                        proyeccion: proyeccion,
                        cencosGalpones: storage.getCencosGalpones(),
                      );
                      if (sel != null) {
                        final codigo = sel['granja'] ?? sel['codigo'] ?? '';
                        var camp = sel['campania'] ?? '';
                        if (camp.isEmpty && codigo.isNotEmpty) {
                          camp = GranjaCampaniaPicker.campaniaFromCodigo(codigo);
                        }
                        setState(() {
                          _granja = GranjaCampaniaPicker.normGranja(
                            sel['granja3'] ?? codigo,
                          );
                          _granjaNombre = GranjaCampaniaPicker.cleanNombreGranja(
                            sel['granjaNombre'] ?? '',
                          );
                          _campania = camp;
                          _galpon = '';
                        });
                        _loadGalpones(storage);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: EvidenciaSelectField(
                    label: 'CAMP',
                    value: _campaniaDisplay,
                    placeholder: '',
                    icon: Icons.tag,
                    showIcon: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            EvidenciaGalponField(
              value: _galpon,
              options: _galponCodes,
              enabled: _granja.isNotEmpty,
              onSelected: (v) => setState(() => _galpon = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _obsController,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: context.formColors.valueSelected,
                height: 1.35,
              ),
              decoration: const InputDecoration(
                labelText: 'Observaciones',
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            Text(
              'Imágenes (máx. 3)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ImageSlotRow(
              paths: _imagePaths,
              onChanged: (i, path) => setState(() => _imagePaths[i] = path),
            ),
          ],
        ),
      ),
    );
  }
}
