import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/api_service.dart';
import '../services/catalog_service.dart' show ArticuloIngresoCatalogo, CatalogService;
import '../services/storage_service.dart';
import '../utils/documento_persona.dart';
import '../utils/documento_scan_flow.dart';
import '../utils/record_saver.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/dismiss_keyboard_scope.dart';
import '../widgets/dni_input_dialog.dart';
import '../widgets/image_slot_row.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart' show RegisterSummarySheet;

const _turquesa = Color(0xFF0FA3B1);

const _desinfectantes = <String>[
  'Formol',
  'Amoníaco',
  'Hipoclorito de sodio',
  'Alcohol 70 %',
  'Cuaternario de amonio',
  'Otro',
];

class _ArticuloItem {
  final nombreCtrl = TextEditingController();
  String codigo = '';

  String get nombre => nombreCtrl.text.trim();

  void dispose() => nombreCtrl.dispose();
}

class _GrupoDesinfeccion {
  _GrupoDesinfeccion() {
    items.add(_ArticuloItem());
  }

  String desinfectante = _desinfectantes.first;
  final items = <_ArticuloItem>[];
  final fotos = <String?>[null, null, null];

  void dispose() {
    for (final i in items) {
      i.dispose();
    }
  }
}

class RegisterArticulosScreen extends StatefulWidget {
  const RegisterArticulosScreen({super.key});

  @override
  State<RegisterArticulosScreen> createState() => _RegisterArticulosScreenState();
}

class _RegisterArticulosScreenState extends State<RegisterArticulosScreen> {
  final _personaCtrl = TextEditingController();
  String _dni = '';
  String _nombre = '';
  final DateTime _fecha = DateTime.now();
  Timer? _debounceNombre;
  bool _consultandoNombre = false;
  bool _sincronizandoPersona = false;
  final List<_GrupoDesinfeccion> _grupos = [_GrupoDesinfeccion()];

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  String get _dniNorm => DocumentoPersona.normalizar(_dni);

  @override
  void dispose() {
    _debounceNombre?.cancel();
    _personaCtrl.dispose();
    for (final g in _grupos) {
      g.dispose();
    }
    super.dispose();
  }

  void _mostrarPersonaEnCampo() {
    if (_sincronizandoPersona) return;
    _sincronizandoPersona = true;
    final d = _dni.trim();
    final n = _nombre.trim();
    final texto = d.isEmpty
        ? n
        : (n.isEmpty ? d : '$d · $n');
    if (_personaCtrl.text != texto) {
      _personaCtrl.text = texto;
    }
    _sincronizandoPersona = false;
  }

  void _leerPersonaDesdeCampo(String raw) {
    final t = raw.trim();
    final i = t.indexOf('·');
    if (i >= 0) {
      _dni = t.substring(0, i).trim();
      _nombre = t.substring(i + 1).trim();
    } else {
      final posible = DocumentoPersona.parse(t) ?? DocumentoPersona.parseSoloCee(t);
      if (posible != null) {
        _dni = posible.id;
        if (_nombre.isEmpty) _nombre = '';
      } else {
        _dni = t;
      }
    }
  }

  void _alCambiarPersona(String v) {
    if (_sincronizandoPersona) return;
    _leerPersonaDesdeCampo(v);
    _debounceNombre?.cancel();
    final doc = _dniNorm;
    if (!DocumentoPersona.esCompleto(doc)) {
      setState(() => _consultandoNombre = false);
      return;
    }
    _debounceNombre = Timer(const Duration(milliseconds: 450), _consultarNombre);
  }

  Future<void> _consultarNombre() async {
    final dni = _dniNorm;
    if (!DocumentoPersona.esCompleto(dni)) return;
    final catalogo = context.read<CatalogService>();
    var nombre = catalogo.nombrePorDni(dni);
    setState(() {
      _consultandoNombre = nombre.isEmpty;
      if (nombre.isNotEmpty) _nombre = nombre;
      _mostrarPersonaEnCampo();
    });

    final res = await ApiService().consultarDni(dni);
    if (!mounted) return;
    final enLinea =
        res['success'] == true ? (res['nombre'] ?? '').toString().trim() : '';
    setState(() {
      _consultandoNombre = false;
      if (enLinea.isNotEmpty) _nombre = enLinea;
      _mostrarPersonaEnCampo();
    });
  }

  Future<void> _escanearDocumento() async {
    final dni = await escanearDocumentoPersona(context);
    if (dni == null || !mounted) return;
    setState(() {
      _dni = dni;
      _nombre = '';
      _mostrarPersonaEnCampo();
    });
    await _consultarNombre();
  }

  Future<void> _ingresoManualDocumento() async {
    final dni = await DniInputDialog.show(context);
    if (dni == null || !mounted) return;
    setState(() {
      _dni = dni;
      _nombre = '';
      _mostrarPersonaEnCampo();
    });
    await _consultarNombre();
  }

  void _agregarGrupo() {
    setState(() => _grupos.add(_GrupoDesinfeccion()));
  }

  void _resetearTrasGuardar() {
    for (final g in _grupos) {
      g.dispose();
    }
    _grupos
      ..clear()
      ..add(_GrupoDesinfeccion());
    _personaCtrl.clear();
    _dni = '';
    _nombre = '';
    _consultandoNombre = false;
  }

  void _quitarGrupo(int index) {
    if (_grupos.length <= 1) return;
    setState(() => _grupos.removeAt(index).dispose());
  }

  ArticuloIngresoCatalogo? _catalogoPorNombre(String nombre) {
    final n = nombre.toLowerCase();
    for (final a in context.read<CatalogService>().articulosIngreso) {
      if (a.descripcion.toLowerCase() == n) return a;
    }
    return null;
  }

  Map<String, dynamic> _buildRecord(StorageService storage) {
    final items = <Map<String, dynamic>>[];
    for (final g in _grupos) {
      final fotos = g.fotos
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .map((p) => {'path': p})
          .toList();
      for (final l in g.items) {
        if (l.nombre.isEmpty) continue;
        final cat = _catalogoPorNombre(l.nombre);
        final codigo = l.codigo.isNotEmpty ? l.codigo : (cat?.codigo ?? '99');
        items.add({
          'codigo': codigo,
          'descripcion': l.nombre,
          'permitido': true,
          'desinfectado': true,
          'desinfectante': g.desinfectante,
          'imagenes': fotos,
        });
      }
    }
    return {
      'id': const Uuid().v4(),
      'reporte': 'articulos',
      'fecha': _fechaYmd,
      'granja': '',
      'granjaNombre': '',
      'campania': '',
      'turno': 'Dia',
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        'dni': _dniNorm,
        'nombre': _nombre.trim(),
        'articulos': items,
      },
      'imagenes': const [],
      'synced': false,
      'guardado_backend': false,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _guardar() async {
    if (!DocumentoPersona.esCompleto(_dniNorm)) {
      showErrorToast(context, 'Indique DNI o carné y nombre en el campo persona.');
      return;
    }
    final conArticulo = _grupos.where((g) => g.items.any((l) => l.nombre.isNotEmpty));
    if (conArticulo.isEmpty) {
      showErrorToast(context, 'Indique al menos un artículo.');
      return;
    }
    for (final g in conArticulo) {
      if (g.desinfectante.trim().isEmpty) {
        showErrorToast(context, 'Indique el desinfectante.');
        return;
      }
    }

    final storage = context.read<StorageService>();
    final record = _buildRecord(storage);
    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        final ok = await BioRecordSaver.save(context, record);
        if (!mounted) return;
        if (ok) {
          showSuccessToast(context, 'Registro guardado y enviado.');
        } else {
          showInfoToast(
            context,
            'Guardado local. Sincronice cuando haya conexión.',
          );
        }
      },
    );
    if (saved && mounted) {
      setState(_resetearTrasGuardar);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = context.watch<CatalogService>().articulosIngreso
        .where((a) => a.codigo != '99')
        .toList();

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: 'Control de artículos',
        sectionIcon: Icons.checklist_rtl_rounded,
        actions: [
          AppBarSaveButton(onPressed: _guardar),
        ],
      ),
      body: DismissKeyboardScope(
        child: RefreshIndicator(
          onRefresh: () async {
            await context.read<CatalogService>().downloadCatalogosBioseguridad();
          },
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              children: [
                BioFormSection(
                  title: 'PERSONA',
                  icon: Icons.person_outline,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _escanearDocumento,
                            icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                            label: const Text('Escanear'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _ingresoManualDocumento,
                            icon: const Icon(Icons.keyboard_rounded, size: 20),
                            label: const Text('Manual'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _personaCtrl,
                      decoration: InputDecoration(
                        labelText: 'Persona',
                        hintText: 'DNI o CEE · nombre',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: _consultandoNombre
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : null,
                      ),
                      onChanged: (v) {
                        _alCambiarPersona(v);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (var i = 0; i < _grupos.length; i++) ...[
                  _GrupoCard(
                    index: i,
                    grupo: _grupos[i],
                    catalogo: catalogo,
                    puedeQuitar: _grupos.length > 1,
                    onQuitar: () => _quitarGrupo(i),
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _agregarGrupo,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _turquesa,
                      side: const BorderSide(color: _turquesa, width: 1.4),
                    ),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Otro grupo'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GrupoCard extends StatelessWidget {
  const _GrupoCard({
    required this.index,
    required this.grupo,
    required this.catalogo,
    required this.puedeQuitar,
    required this.onQuitar,
    required this.onChanged,
  });

  final int index;
  final _GrupoDesinfeccion grupo;
  final List<ArticuloIngresoCatalogo> catalogo;
  final bool puedeQuitar;
  final VoidCallback onQuitar;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _turquesa, width: 1.4),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Grupo ${index + 1}',
                    style: const TextStyle(
                      color: _turquesa,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (puedeQuitar)
                  IconButton(
                    onPressed: onQuitar,
                    icon: const Icon(Icons.close, color: _turquesa),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: grupo.desinfectante,
              decoration: _campo('Desinfectante'),
              items: [
                for (final d in _desinfectantes)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) {
                grupo.desinfectante = v ?? _desinfectantes.first;
                onChanged();
              },
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < grupo.items.length; i++) ...[
              Row(
                children: [
                  Expanded(child: _campoArticulo(grupo.items[i])),
                  if (grupo.items.length > 1)
                    IconButton(
                      onPressed: () {
                        grupo.items.removeAt(i).dispose();
                        onChanged();
                      },
                      icon: const Icon(Icons.remove_circle_outline, color: _turquesa),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  grupo.items.add(_ArticuloItem());
                  onChanged();
                },
                style: TextButton.styleFrom(foregroundColor: _turquesa),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Artículo'),
              ),
            ),
            ImageSlotRow(
              paths: grupo.fotos,
              onChanged: (i, path) {
                grupo.fotos[i] = path;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoArticulo(_ArticuloItem item) {
    return Autocomplete<ArticuloIngresoCatalogo>(
      optionsBuilder: (query) {
        final q = query.text.trim().toLowerCase();
        if (q.isEmpty) return catalogo.take(12);
        return catalogo.where((a) => a.descripcion.toLowerCase().contains(q));
      },
      displayStringForOption: (a) => a.descripcion,
      onSelected: (a) {
        item.nombreCtrl.text = a.descripcion;
        item.codigo = a.codigo;
        onChanged();
      },
      fieldViewBuilder: (ctx, ctrl, focus, onSubmit) {
        return TextField(
          controller: item.nombreCtrl,
          focusNode: focus,
          cursorColor: _turquesa,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(fontWeight: FontWeight.w600),
          decoration: _campo('Artículo'),
          onChanged: (v) {
            for (final a in catalogo) {
              if (a.descripcion.toLowerCase() == v.trim().toLowerCase()) {
                item.codigo = a.codigo;
                break;
              }
            }
            onChanged();
          },
        );
      },
    );
  }
}

InputDecoration _campo(String label) {
  const borde = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: _turquesa, width: 1.5),
  );
  return const InputDecoration(
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
  ).copyWith(
    labelText: label,
    labelStyle: const TextStyle(color: _turquesa, fontWeight: FontWeight.w600),
    floatingLabelStyle: const TextStyle(color: _turquesa, fontWeight: FontWeight.w700),
    border: borde,
    enabledBorder: borde,
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: _turquesa, width: 2),
    ),
  );
}

