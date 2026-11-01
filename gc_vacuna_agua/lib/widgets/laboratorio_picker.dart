import 'dart:async';

import 'package:flutter/material.dart';

import '../services/proveedor_vacuna_catalog_service.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';
import 'proveedor_dialog.dart';

typedef BuscarLaboratorioEnLinea = Future<Map<String, dynamic>> Function(
  String q,
);

/// Lista de laboratorios descargados; si no hay coincidencia, busca en línea (ccte).
/// **Aceptar** guarda lo escrito en el buscador (aunque no esté en la lista).
Future<ProveedorSeleccion?> showLaboratorioListaDialog({
  required BuildContext context,
  required ProveedorVacunaCatalogService catalogo,
  ProveedorSeleccion actual = ProveedorSeleccion.vacia,
  BuscarLaboratorioEnLinea? buscarEnLinea,
}) {
  return showAppDialog<ProveedorSeleccion>(
    context: context,
    builder: (ctx) => _LaboratorioListaDialog(
      catalogo: catalogo,
      actual: actual,
      buscarEnLinea: buscarEnLinea,
    ),
  );
}

class _LaboratorioListaDialog extends StatefulWidget {
  const _LaboratorioListaDialog({
    required this.catalogo,
    required this.actual,
    this.buscarEnLinea,
  });

  final ProveedorVacunaCatalogService catalogo;
  final ProveedorSeleccion actual;
  final BuscarLaboratorioEnLinea? buscarEnLinea;

  @override
  State<_LaboratorioListaDialog> createState() => _LaboratorioListaDialogState();
}

class _LaboratorioListaDialogState extends State<_LaboratorioListaDialog> {
  final List<ProveedorCcteItem> _localAll = [];
  late final TextEditingController _busquedaCtrl;
  List<ProveedorCcteItem> _remotos = [];
  bool _buscandoRemoto = false;
  String? _avisoRemoto;
  Timer? _debounce;
  int _busquedaSeq = 0;

  @override
  void initState() {
    super.initState();
    _localAll.addAll(widget.catalogo.buscar(''));
    // Lista completa al abrir (igual que granja/campaña), no filtrar por lo ya elegido.
    _busquedaCtrl = TextEditingController();
    _busquedaCtrl.addListener(_onFilterChanged);
  }

  bool _esSeleccionado(ProveedorSeleccion sel) {
    final a = widget.actual;
    if (a.estaVacio) return false;
    final ar = a.ruc.trim();
    final sr = sel.ruc.trim();
    if (ar.isNotEmpty && sr.isNotEmpty && ar == sr) return true;
    final an = a.nombre.trim().toLowerCase();
    final sn = sel.nombre.trim().toLowerCase();
    if (an.isNotEmpty && sn.isNotEmpty && an == sn) return true;
    return ar == sr && an == sn;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaCtrl.removeListener(_onFilterChanged);
    _busquedaCtrl.dispose();
    super.dispose();
  }

  String get _texto => _busquedaCtrl.text.trim();

  String get _soloDigitos => _texto.replaceAll(RegExp(r'\D'), '');

  bool get _puedeBuscarEnLinea {
    if (widget.buscarEnLinea == null) return false;
    if (_texto.isEmpty) return false;
    if (_soloDigitos.length == 11) return true;
    return _texto.length >= 3;
  }

  List<ProveedorCcteItem> get _localFiltrados {
    final q = _texto.toLowerCase();
    if (q.isEmpty) return List<ProveedorCcteItem>.from(_localAll);
    return _localAll.where((it) {
      return it.ruc.toLowerCase().contains(q) ||
          it.razonsocial.toLowerCase().contains(q);
    }).toList();
  }

  List<_FilaLista> get _filas {
    final out = <_FilaLista>[];
    final vistos = <String>{};
    for (final it in _localFiltrados) {
      final clave = it.ruc.isNotEmpty ? it.ruc : it.razonsocial;
      if (!vistos.add(clave)) continue;
      out.add(_FilaLista(item: it, enLinea: false));
    }
    for (final it in _remotos) {
      final clave = it.ruc.isNotEmpty ? it.ruc : it.razonsocial;
      if (!vistos.add(clave)) continue;
      out.add(_FilaLista(item: it, enLinea: true));
    }
    return out;
  }

  void _onFilterChanged() {
    setState(() {
      _avisoRemoto = null;
      if (!_puedeBuscarEnLinea) {
        _remotos = [];
        _buscandoRemoto = false;
      }
    });
    _debounce?.cancel();
    if (!_puedeBuscarEnLinea) return;
    _debounce = Timer(const Duration(milliseconds: 450), _buscarRemoto);
  }

  Future<void> _buscarRemoto() async {
    final buscar = widget.buscarEnLinea;
    if (buscar == null || !_puedeBuscarEnLinea) return;
    final seq = ++_busquedaSeq;
    setState(() {
      _buscandoRemoto = true;
      _avisoRemoto = null;
    });
    final res = await buscar(_texto);
    if (!mounted || seq != _busquedaSeq) return;
    if (res['success'] == true) {
      setState(() {
        _buscandoRemoto = false;
        _remotos = _parseItems(res);
        _avisoRemoto = null;
      });
      return;
    }
    final code = res['errorCode']?.toString();
    setState(() {
      _buscandoRemoto = false;
      _remotos = [];
      if (code == 'CONNECTIVITY') {
        _avisoRemoto = 'Sin conexión: solo se muestra la lista descargada.';
      } else {
        _avisoRemoto =
            res['message']?.toString() ?? 'No se pudo buscar en el servidor.';
      }
    });
  }

  void _aceptar() {
    final sel = ProveedorSeleccion.desdeTextoLibre(_texto);
    if (sel.estaVacio) return;
    Navigator.pop(context, sel);
  }

  List<ProveedorCcteItem> _parseItems(Map<String, dynamic> res) {
    final raw = res['items'];
    if (raw is! List) return const [];
    final out = <ProveedorCcteItem>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final ruc = (row['ruc'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final nombre = (row['razonsocial'] ?? row['nombre'] ?? '')
          .toString()
          .trim();
      if (ruc.length != 11 || nombre.isEmpty) continue;
      out.add(ProveedorCcteItem(ruc: ruc, razonsocial: nombre));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final filas = _filas;
    final q = _texto;
    final puedeAceptar = q.isNotEmpty;

    return Dialog(
      backgroundColor: context.dialogSurface,
      insetPadding: context.dialogInsetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 24,
        height: MediaQuery.of(context).size.height * 0.58,
        child: Column(
          children: [
            appDialogHeader(context, title: 'Seleccionar laboratorio'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _busquedaCtrl,
                autofocus: _localAll.isEmpty,
                style: TextStyle(color: context.textThemePrimary),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) {
                  if (puedeAceptar) _aceptar();
                },
                decoration: InputDecoration(
                  hintText: 'Buscar por RUC o nombre',
                  hintStyle: TextStyle(color: context.textThemeMuted),
                  prefixIcon: Icon(Icons.search, color: context.textThemeMuted),
                  suffixIcon: _busquedaCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          icon: Icon(
                            Icons.clear,
                            color: context.textThemeMuted,
                          ),
                          onPressed: () => _busquedaCtrl.clear(),
                        ),
                  isDense: true,
                ),
              ),
            ),
            if (_buscandoRemoto)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_avisoRemoto != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _avisoRemoto!,
                  style: TextStyle(color: context.textThemeMuted, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: filas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _localAll.isEmpty && q.isEmpty
                              ? 'Descargue catálogos en el menú o escriba un laboratorio y pulse Aceptar.'
                              : q.isEmpty
                              ? 'Escriba para buscar o pulse Aceptar.'
                              : _buscandoRemoto
                              ? 'Buscando…'
                              : 'Sin coincidencias. Pulse Aceptar para usar lo escrito.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.textThemeMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filas.length,
                      itemBuilder: (_, i) {
                        final fila = filas[i];
                        final it = fila.item;
                        final sel = ProveedorSeleccion(
                          ruc: it.ruc,
                          nombre: it.razonsocial,
                        );
                        final selected = _esSeleccionado(sel);
                        return ListTile(
                          selected: selected,
                          title: Text(
                            it.razonsocial,
                            style: TextStyle(
                              color: context.textThemePrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            fila.enLinea
                                ? 'RUC ${it.ruc} · búsqueda en línea'
                                : 'RUC ${it.ruc}',
                            style: TextStyle(
                              color: context.textThemeMuted,
                              fontSize: 13,
                            ),
                          ),
                          onTap: () => Navigator.pop(context, sel),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: puedeAceptar ? _aceptar : null,
                    child: const Text('Aceptar'),
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

class _FilaLista {
  const _FilaLista({required this.item, required this.enLinea});

  final ProveedorCcteItem item;
  final bool enLinea;
}
