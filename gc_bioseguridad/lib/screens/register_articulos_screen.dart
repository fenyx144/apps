import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/alcoholemia_api_service.dart';
import '../services/api_service.dart';
import '../services/catalog_service.dart' show ArticuloIngresoCatalogo, CatalogService;
import '../services/storage_service.dart';
import '../utils/anomalia_contexto.dart';
import '../utils/documento_persona.dart';
import '../utils/documento_scan_flow.dart';
import '../utils/record_saver.dart';
import '../utils/theme_colors.dart';
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
  'Amoníaco',
  'Hipoclorito de sodio',
  'Alcohol 70 %',
  'Cuaternario de amonio',
  'Otro',
];

class _LineaArticulo {
  _LineaArticulo();

  final nombreCtrl = TextEditingController();
  bool permitido = true;
  bool desinfectado = true;
  String desinfectante = _desinfectantes.first;
  String codigo = '';
  String notaCatalogo = '';
  final anomaliaPermCtrl = TextEditingController();
  final agentePermCtrl = TextEditingController();
  final accionPermCtrl = TextEditingController();
  final anomaliaDesCtrl = TextEditingController();
  final agenteDesCtrl = TextEditingController();
  final accionDesCtrl = TextEditingController();
  String _autoAnomaliaPerm = '';
  String _autoAgentePerm = '';
  String _autoAccionPerm = '';
  String _autoAnomaliaDes = '';
  String _autoAgenteDes = '';
  String _autoAccionDes = '';
  final List<String?> fotos = [null, null, null];

  String get nombre => nombreCtrl.text.trim();

  bool get tieneAnomalia => !permitido || (permitido && !desinfectado);

  bool get fotosObligatorias => true;

  void aplicarCatalogo(ArticuloIngresoCatalogo a) {
    codigo = a.codigo;
    notaCatalogo = a.nota;
    if (a.permite != null) permitido = a.permite!;
  }

  void _poner(
    TextEditingController ctrl,
    String nuevo,
    String auto,
    void Function(String) guardarAuto,
  ) {
    if (ctrl.text.trim().isEmpty || ctrl.text == auto) {
      ctrl.text = nuevo;
      guardarAuto(nuevo);
    }
  }

  void rellenarAgcNoPermitido() {
    final ctx = AnomaliaContexto.articuloNoPermitido(nombre, nota: notaCatalogo);
    _poner(anomaliaPermCtrl, ctx.anomalia, _autoAnomaliaPerm, (v) => _autoAnomaliaPerm = v);
    _poner(agentePermCtrl, ctx.agenteCausal, _autoAgentePerm, (v) => _autoAgentePerm = v);
    _poner(accionPermCtrl, ctx.accion, _autoAccionPerm, (v) => _autoAccionPerm = v);
  }

  void rellenarAgcSinDesinfeccion() {
    final ctx = AnomaliaContexto.articuloSinDesinfeccion(nombre);
    _poner(anomaliaDesCtrl, ctx.anomalia, _autoAnomaliaDes, (v) => _autoAnomaliaDes = v);
    _poner(agenteDesCtrl, ctx.agenteCausal, _autoAgenteDes, (v) => _autoAgenteDes = v);
    _poner(accionDesCtrl, ctx.accion, _autoAccionDes, (v) => _autoAccionDes = v);
  }

  void dispose() {
    nombreCtrl.dispose();
    anomaliaPermCtrl.dispose();
    agentePermCtrl.dispose();
    accionPermCtrl.dispose();
    anomaliaDesCtrl.dispose();
    agenteDesCtrl.dispose();
    accionDesCtrl.dispose();
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
  final List<_LineaArticulo> _lineas = [_LineaArticulo()];

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  String get _dniNorm => DocumentoPersona.normalizar(_dni);

  @override
  void dispose() {
    _debounceNombre?.cancel();
    _personaCtrl.dispose();
    for (final l in _lineas) {
      l.dispose();
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

  void _agregarLinea() {
    setState(() => _lineas.add(_LineaArticulo()));
  }

  void _resetearTrasGuardar() {
    for (final l in _lineas) {
      l.dispose();
    }
    _lineas
      ..clear()
      ..add(_LineaArticulo());
    _personaCtrl.clear();
    _dni = '';
    _nombre = '';
    _consultandoNombre = false;
  }

  Future<void> _mostrarArticulosPermitidos(
    List<ArticuloIngresoCatalogo> permitidos,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Artículos permitidos'),
        content: SizedBox(
          width: double.maxFinite,
          child: permitidos.isEmpty
              ? const Text('No hay referencias en el catálogo descargado.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: permitidos.length,
                  itemBuilder: (_, i) {
                    final a = permitidos[i];
                    final nota = a.nota.trim();
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(a.descripcion),
                      subtitle: nota.isNotEmpty ? Text(nota) : null,
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _quitarLinea(int index) {
    if (_lineas.length <= 1) {
      showInfoToast(context, 'Debe haber al menos un artículo.');
      return;
    }
    setState(() => _lineas.removeAt(index).dispose());
  }

  ArticuloIngresoCatalogo? _catalogoPorNombre(String nombre) {
    final n = nombre.toLowerCase();
    for (final a in context.read<CatalogService>().articulosIngreso) {
      if (a.descripcion.toLowerCase() == n) return a;
    }
    return null;
  }

  List<_LineaArticulo> get _lineasConDatos =>
      _lineas.where((l) => l.nombre.isNotEmpty).toList();

  Map<String, dynamic> _buildRecord(StorageService storage) {
    final items = <Map<String, dynamic>>[];
    for (final l in _lineasConDatos) {
      final cat = _catalogoPorNombre(l.nombre);
      final codigo = l.codigo.isNotEmpty ? l.codigo : (cat?.codigo ?? '99');
      final fotos = l.fotos
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .map((p) => {'path': p});
      items.add({
        'codigo': codigo,
        'descripcion': l.nombre,
        'permitido': l.permitido,
        if (!l.permitido) ...{
          'anomalia_permitido': l.anomaliaPermCtrl.text.trim(),
          'agente_causal_permitido': l.agentePermCtrl.text.trim(),
          'accion_permitido': l.accionPermCtrl.text.trim(),
        },
        if (l.permitido) ...{
          'desinfectado': l.desinfectado,
          if (l.desinfectado && l.desinfectante.isNotEmpty)
            'desinfectante': l.desinfectante,
          if (!l.desinfectado) ...{
            'anomalia_desinfeccion': l.anomaliaDesCtrl.text.trim(),
            'agente_causal_desinfeccion': l.agenteDesCtrl.text.trim(),
            'accion_desinfeccion': l.accionDesCtrl.text.trim(),
          },
        },
        'imagenes': fotos.toList(),
      });
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
    final items = _lineasConDatos;
    if (items.isEmpty) {
      showErrorToast(context, 'Indique al menos un artículo.');
      return;
    }
    for (final l in items) {
      if (!l.permitido) l.rellenarAgcNoPermitido();
      if (l.permitido && !l.desinfectado) l.rellenarAgcSinDesinfeccion();
      if (!l.fotos.any((p) => p != null && p.isNotEmpty)) {
        showErrorToast(context, 'Adjunte foto: «${l.nombre}».');
        return;
      }
      if (!l.permitido &&
          (l.anomaliaPermCtrl.text.trim().isEmpty ||
              l.agentePermCtrl.text.trim().isEmpty ||
              l.accionPermCtrl.text.trim().isEmpty)) {
        showErrorToast(context, 'Indique anomalía, agente causal y acción: «${l.nombre}».');
        return;
      }
      if (l.permitido) {
        if (!l.desinfectado &&
            (l.anomaliaDesCtrl.text.trim().isEmpty ||
                l.agenteDesCtrl.text.trim().isEmpty ||
                l.accionDesCtrl.text.trim().isEmpty)) {
          showErrorToast(context, 'Indique anomalía, agente causal y acción: «${l.nombre}».');
          return;
        } else if (l.desinfectado && l.desinfectante.trim().isEmpty) {
          showErrorToast(
            context,
            'Indique el desinfectante usado: «${l.nombre}».',
          );
          return;
        }
      }
    }

    final storage = context.read<StorageService>();
    final record = _buildRecord(storage);
    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () async {
        final ok = await BioRecordSaver.save(context, record);
        var agcOk = true;
        String? agcError;
        if (ok) {
          final api = AlcoholemiaApiService();
          final usuario = storage.getUserCodeSync() ?? '';
          for (final l in items) {
            final foto = l.fotos.whereType<String>().firstWhere(
                  (p) => p.isNotEmpty,
                  orElse: () => '',
                );
            final fotoPath = foto.isEmpty ? null : foto;
            if (!l.permitido) {
              final r = await api.guardarArticuloAnomalia(
                granja: '000',
                campania: '000',
                fecha: _fechaYmd,
                dni: _dniNorm,
                nombre: _nombre.trim(),
                articulo: l.nombre,
                accion: l.accionPermCtrl.text.trim(),
                anomalia: l.anomaliaPermCtrl.text.trim(),
                agenteCausal: l.agentePermCtrl.text.trim(),
                fotoPath: fotoPath,
                usuario: usuario,
              );
              if (!r.ok) {
                agcOk = false;
                agcError ??= r.message;
              }
            }
            if (l.permitido && !l.desinfectado) {
              final r = await api.guardarArticuloAnomalia(
                granja: '000',
                campania: '000',
                fecha: _fechaYmd,
                dni: _dniNorm,
                nombre: _nombre.trim(),
                articulo: '${l.nombre} (desinfección)',
                accion: l.accionDesCtrl.text.trim(),
                anomalia: l.anomaliaDesCtrl.text.trim(),
                agenteCausal: l.agenteDesCtrl.text.trim(),
                fotoPath: fotoPath,
                usuario: usuario,
              );
              if (!r.ok) {
                agcOk = false;
                agcError ??= r.message;
              }
            }
          }
        }
        if (!mounted) return;
        if (ok) {
          if (agcOk) {
            showSuccessToast(context, 'Registro guardado y enviado.');
          } else {
            showInfoToast(
              context,
              agcError?.isNotEmpty == true
                  ? agcError!
                  : 'Registro guardado; no se pudo registrar una o más anomalías AGC.',
            );
          }
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
    final permitidos = catalogo
        .where((a) => a.permite != false)
        .toList()
      ..sort((a, b) => a.descripcion.compareTo(b.descripcion));

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
                BioFormSection(
                  title: 'ARTÍCULOS',
                  icon: Icons.inventory_2_outlined,
                  children: [
                    if (catalogo.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => _mostrarArticulosPermitidos(permitidos),
                          icon: const Icon(Icons.list_alt_rounded, size: 20),
                          label: Text(
                            permitidos.isEmpty
                                ? 'Ver catálogo de artículos'
                                : 'Consultar artículos permitidos (${permitidos.length})',
                          ),
                        ),
                      ),
                    if (catalogo.isNotEmpty) const SizedBox(height: 4),
                    for (var i = 0; i < _lineas.length; i++) ...[
                      _ArticuloLineaTile(
                        index: i,
                        linea: _lineas[i],
                        catalogo: catalogo,
                        puedeQuitar: _lineas.length > 1,
                        onQuitar: () => _quitarLinea(i),
                        onChanged: () => setState(() {}),
                      ),
                      if (i < _lineas.length - 1) const Divider(height: 24),
                    ],
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _agregarLinea,
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Agregar otro artículo'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ArticuloLineaTile extends StatelessWidget {
  const _ArticuloLineaTile({
    required this.index,
    required this.linea,
    required this.catalogo,
    required this.puedeQuitar,
    required this.onQuitar,
    required this.onChanged,
  });

  final int index;
  final _LineaArticulo linea;
  final List<ArticuloIngresoCatalogo> catalogo;
  final bool puedeQuitar;
  final VoidCallback onQuitar;
  final VoidCallback onChanged;

  void _alElegirCatalogo(ArticuloIngresoCatalogo a) {
    linea.nombreCtrl.text = a.descripcion;
    linea.aplicarCatalogo(a);
    if (!linea.permitido) {
      linea.rellenarAgcNoPermitido();
    } else {
      linea.desinfectado = true;
      if (linea.desinfectante.isEmpty) {
        linea.desinfectante = _desinfectantes.first;
      }
    }
    onChanged();
  }

  void _alCambiarPermitido(bool? v) {
    linea.permitido = v ?? true;
    if (!linea.permitido) {
      linea.rellenarAgcNoPermitido();
    } else {
      linea.desinfectado = true;
      linea.desinfectante =
          linea.desinfectante.isNotEmpty ? linea.desinfectante : _desinfectantes.first;
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Artículo ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: _turquesa,
                ),
              ),
            ),
            if (puedeQuitar)
              IconButton(
                tooltip: 'Quitar',
                onPressed: onQuitar,
                icon: const Icon(Icons.close, size: 20),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        Autocomplete<ArticuloIngresoCatalogo>(
          optionsBuilder: (query) {
            final q = query.text.trim().toLowerCase();
            if (q.isEmpty) return catalogo.take(12);
            return catalogo.where(
              (a) => a.descripcion.toLowerCase().contains(q),
            );
          },
          displayStringForOption: (a) => a.descripcion,
          onSelected: _alElegirCatalogo,
          fieldViewBuilder: (ctx, ctrl, focus, onFieldSubmitted) {
            return TextField(
              controller: linea.nombreCtrl,
              focusNode: focus,
              decoration: const InputDecoration(
                labelText: 'Nombre del artículo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                ArticuloIngresoCatalogo? cat;
                for (final a in catalogo) {
                  if (a.descripcion.toLowerCase() == v.trim().toLowerCase()) {
                    cat = a;
                    break;
                  }
                }
                if (cat != null) {
                  linea.aplicarCatalogo(cat);
                  if (!linea.permitido) {
                    linea.rellenarAgcNoPermitido();
                  } else {
                    linea.desinfectado = true;
                    if (linea.desinfectante.isEmpty) {
                      linea.desinfectante = _desinfectantes.first;
                    }
                  }
                } else if (linea.permitido && !linea.desinfectado) {
                  linea.rellenarAgcSinDesinfeccion();
                }
                onChanged();
              },
            );
          },
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: linea.permitido,
          title: const Text('Artículo permitido'),
          onChanged: _alCambiarPermitido,
        ),
        if (!linea.permitido) ...[
          const SizedBox(height: 6),
          _CamposAnomaliaArticulo(
            anomalia: linea.anomaliaPermCtrl,
            agente: linea.agentePermCtrl,
            accion: linea.accionPermCtrl,
            onChanged: onChanged,
          ),
        ],
        if (linea.permitido) ...[
          const Divider(height: 20),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: linea.desinfectado,
            title: const Text('Se desinfectó'),
            onChanged: (v) {
              linea.desinfectado = v ?? true;
              if (linea.desinfectado) {
                linea.desinfectante = linea.desinfectante.isNotEmpty
                    ? linea.desinfectante
                    : _desinfectantes.first;
              } else {
                linea.rellenarAgcSinDesinfeccion();
              }
              onChanged();
            },
          ),
          if (linea.desinfectado) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              key: ValueKey('des-${linea.desinfectante}'),
              initialValue:
                  linea.desinfectante.isEmpty ? _desinfectantes.first : linea.desinfectante,
              decoration: const InputDecoration(
                labelText: 'Desinfectante utilizado',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final d in _desinfectantes)
                  DropdownMenuItem(value: d, child: Text(d)),
              ],
              onChanged: (v) {
                linea.desinfectante = v ?? '';
                onChanged();
              },
            ),
          ] else ...[
            const SizedBox(height: 6),
            _CamposAnomaliaArticulo(
              anomalia: linea.anomaliaDesCtrl,
              agente: linea.agenteDesCtrl,
              accion: linea.accionDesCtrl,
              onChanged: onChanged,
            ),
          ],
        ],
        const SizedBox(height: 10),
        Text(
          'Foto',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.textThemeSecondary,
          ),
        ),
        const SizedBox(height: 6),
        ImageSlotRow(
          paths: linea.fotos,
          onChanged: (i, path) {
            linea.fotos[i] = path;
            onChanged();
          },
        ),
      ],
    );
  }
}

class _CamposAnomaliaArticulo extends StatelessWidget {
  const _CamposAnomaliaArticulo({
    required this.anomalia,
    required this.agente,
    required this.accion,
    required this.onChanged,
  });

  final TextEditingController anomalia;
  final TextEditingController agente;
  final TextEditingController accion;
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
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Column(
          children: [
            TextField(
              controller: anomalia,
              cursorColor: _turquesa,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontWeight: FontWeight.w600),
              decoration: _dec('Anomalía'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: agente,
              cursorColor: _turquesa,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontWeight: FontWeight.w600),
              decoration: _dec('Agente causal'),
              onChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: accion,
              cursorColor: _turquesa,
              minLines: 2,
              maxLines: 3,
              style: const TextStyle(fontWeight: FontWeight.w600),
              decoration: _dec('Acción'),
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _dec(String label) {
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