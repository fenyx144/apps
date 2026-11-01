import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Fila del maestro `ccte` (RUC + razón social).
class ProveedorCcteItem {
  const ProveedorCcteItem({
    required this.ruc,
    required this.razonsocial,
    this.enDispositivo = false,
    this.catalogoPlanificacion = false,
  });

  final String ruc;
  final String razonsocial;

  /// Coincidencia del historial local (planificación / ingresos en este equipo).
  final bool enDispositivo;

  /// Catálogo descargado del servidor (`san_usuario_proveedor`).
  final bool catalogoPlanificacion;
}

/// Proveedor que llega a la granja.
///
/// Se identifica por [ruc] (11 dígitos, con razón social consultada en
/// [nombre]) o solo por [nombre] escrito a mano cuando no hay RUC.
class ProveedorSeleccion {
  const ProveedorSeleccion({this.ruc = '', this.nombre = ''});

  /// RUC de 11 dígitos (`''` si se registró solo el nombre).
  final String ruc;

  /// Razón social del RUC, o el nombre escrito a mano.
  final String nombre;

  static const ProveedorSeleccion vacia = ProveedorSeleccion();

  bool get estaVacio => ruc.trim().isEmpty && nombre.trim().isEmpty;

  /// «RAZÓN SOCIAL · RUC 20123456789», o lo que haya.
  String get etiqueta {
    final r = ruc.trim();
    final n = nombre.trim();
    if (r.isEmpty) return n;
    return n.isEmpty ? 'RUC $r' : '$n · RUC $r';
  }

  /// Sin coincidencias en catálogo ni en línea: guardar lo que escribió el usuario.
  static ProveedorSeleccion desdeTextoLibre(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return vacia;
    final digits = t.replaceAll(RegExp(r'\D'), '');
    final soloDigitos =
        digits.isNotEmpty && RegExp(r'^[\d\s.\-]+$').hasMatch(t);
    if (soloDigitos && digits.length == 11) {
      return ProveedorSeleccion(ruc: digits, nombre: '');
    }
    return ProveedorSeleccion(ruc: '', nombre: t);
  }
}

/// Pide el proveedor: un campo busca en maestro `ccte` (en línea) por RUC o
/// nombre; con RUC completo y sin coincidencia local, puede usar Factiliza.
Future<ProveedorSeleccion?> showProveedorDialog({
  required BuildContext context,
  required ProveedorSeleccion actual,
  required List<ProveedorCcteItem> Function(String q) buscarProveedorLocal,
  required Future<Map<String, dynamic>> Function(String q) buscarProveedorCcte,
  required Future<Map<String, dynamic>> Function(String ruc) consultarRuc,
  String titulo = 'Proveedor',
  /// Solo lista descargada (p. ej. laboratorios de Vacuna al Agua en Sanidad).
  bool soloCatalogoDescargado = false,
}) {
  return showDialog<ProveedorSeleccion>(
    context: context,
    builder: (_) => _ProveedorDialog(
      actual: actual,
      titulo: titulo,
      buscarProveedorLocal: buscarProveedorLocal,
      buscarProveedorCcte: buscarProveedorCcte,
      consultarRuc: consultarRuc,
      soloCatalogoDescargado: soloCatalogoDescargado,
    ),
  );
}

class _ProveedorDialog extends StatefulWidget {
  const _ProveedorDialog({
    required this.actual,
    required this.titulo,
    required this.buscarProveedorLocal,
    required this.buscarProveedorCcte,
    required this.consultarRuc,
    this.soloCatalogoDescargado = false,
  });

  final ProveedorSeleccion actual;
  final String titulo;
  final List<ProveedorCcteItem> Function(String q) buscarProveedorLocal;
  final Future<Map<String, dynamic>> Function(String q) buscarProveedorCcte;
  final Future<Map<String, dynamic>> Function(String ruc) consultarRuc;
  final bool soloCatalogoDescargado;

  @override
  State<_ProveedorDialog> createState() => _ProveedorDialogState();
}

class _ProveedorDialogState extends State<_ProveedorDialog> {
  late final TextEditingController _busquedaCtrl = TextEditingController(
    text: _textoInicial(widget.actual),
  );

  String _razonsocial = '';
  String _rucResuelto = '';
  bool _consultando = false;
  List<ProveedorCcteItem> _resultados = [];
  Timer? _debounce;
  int _busquedaSeq = 0;

  static String _textoInicial(ProveedorSeleccion actual) {
    final n = actual.nombre.trim();
    final r = actual.ruc.trim();
    if (n.isNotEmpty) return n;
    return r;
  }

  static final RegExp _tieneLetras = RegExp(
    r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]',
  );

  String get _texto => _busquedaCtrl.text.trim();

  String get _soloDigitos => _texto.replaceAll(RegExp(r'\D'), '');

  bool get _esRucCompleto =>
      _texto.isNotEmpty &&
      !_tieneLetras.hasMatch(_texto) &&
      _soloDigitos.length == 11;

  bool get _esRucIncompleto =>
      _texto.isNotEmpty &&
      !_tieneLetras.hasMatch(_texto) &&
      _soloDigitos.isNotEmpty &&
      _soloDigitos.length < 11;

  bool get _puedeBuscarEnLinea {
    if (_texto.isEmpty) return false;
    if (_esRucCompleto) return true;
    return _texto.length >= 3;
  }

  bool get _puedeAceptar {
    if (_texto.isEmpty) return false;
    if (_esRucIncompleto) return false;
    if (_esRucCompleto) return true;
    return _texto.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    final r = widget.actual.ruc.trim();
    if (r.length == 11) {
      _rucResuelto = r;
      _razonsocial = widget.actual.nombre.trim();
    }
    if (widget.soloCatalogoDescargado) {
      _resultados = widget.buscarProveedorLocal('');
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _busquedaCtrl.dispose();
    super.dispose();
  }

  void _alCambiarTexto() {
    final buscaLocal = widget.soloCatalogoDescargado || _puedeBuscarEnLinea;
    final List<ProveedorCcteItem> locales = buscaLocal
        ? widget.buscarProveedorLocal(_texto)
        : const <ProveedorCcteItem>[];
    setState(() {
      _resultados = locales;
      if (_esRucCompleto) {
        if (_soloDigitos != _rucResuelto) {
          _razonsocial = '';
        }
      } else if (_rucResuelto.isNotEmpty &&
          _soloDigitos != _rucResuelto &&
          !_razonsocial.toUpperCase().contains(_texto.toUpperCase())) {
        _rucResuelto = '';
        _razonsocial = '';
      }
    });
    _debounce?.cancel();
    if (!widget.soloCatalogoDescargado && !_puedeBuscarEnLinea) return;
    _debounce = Timer(
      Duration(milliseconds: widget.soloCatalogoDescargado ? 150 : 450),
      _buscarEnLinea,
    );
  }

  List<ProveedorCcteItem> _parseItems(Map<String, dynamic> res) {
    final raw = res['items'];
    if (raw is! List) return const [];
    final out = <ProveedorCcteItem>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final ruc = (row['ruc'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
      final nombre = (row['razonsocial'] ?? '').toString().trim();
      if (ruc.length != 11 || nombre.isEmpty) continue;
      out.add(ProveedorCcteItem(ruc: ruc, razonsocial: nombre));
    }
    return out;
  }

  List<ProveedorCcteItem> _fusionarResultados(
    List<ProveedorCcteItem> local,
    List<ProveedorCcteItem> remoto,
  ) {
    final out = <ProveedorCcteItem>[];
    final vistosRuc = <String>{};
    final vistosNombre = <String>{};

    void agregar(ProveedorCcteItem it) {
      if (it.ruc.length == 11) {
        if (!vistosRuc.add(it.ruc)) return;
      } else {
        final k = it.razonsocial.trim().toUpperCase();
        if (k.isEmpty || !vistosNombre.add(k)) return;
      }
      out.add(it);
    }

    for (final it in local) {
      agregar(it);
    }
    for (final it in remoto) {
      agregar(it);
    }
    return out;
  }

  ProveedorSeleccion _seleccionDe(ProveedorCcteItem item) {
    final ruc = item.ruc.length == 11 ? item.ruc : '';
    final nombre = item.razonsocial.trim();
    if (ruc.isNotEmpty) {
      return ProveedorSeleccion(ruc: ruc, nombre: nombre);
    }
    return ProveedorSeleccion(ruc: '', nombre: nombre);
  }

  void _seleccionar(ProveedorCcteItem item) {
    Navigator.pop(context, _seleccionDe(item));
  }

  Future<void> _buscarEnLinea() async {
    if (widget.soloCatalogoDescargado) {
      setState(() {
        _consultando = false;
        _resultados = widget.buscarProveedorLocal(_texto);
      });
      return;
    }

    if (!_puedeBuscarEnLinea) return;

    final seq = ++_busquedaSeq;
    final local = widget.buscarProveedorLocal(_texto);
    setState(() {
      _consultando = true;
      _resultados = local;
    });

    final resCcte = await widget.buscarProveedorCcte(_texto);
    if (!mounted || seq != _busquedaSeq) return;

    if (resCcte['success'] == true) {
      final remoto = _parseItems(resCcte);
      final items = _fusionarResultados(local, remoto);
      setState(() {
        _consultando = false;
        _resultados = items;
      });
      if (items.isEmpty && _esRucCompleto) {
        await _consultarFactiliza(seq);
      }
      return;
    }

    if (resCcte['errorCode'] == 'CONNECTIVITY') {
      setState(() {
        _consultando = false;
        _resultados = local;
      });
      if (_esRucCompleto && local.isEmpty) {
        await _consultarFactiliza(seq);
      }
      return;
    }

    if (local.isNotEmpty) {
      setState(() {
        _consultando = false;
        _resultados = local;
      });
      return;
    }

    if (_esRucCompleto) {
      await _consultarFactiliza(seq);
      return;
    }

    setState(() {
      _consultando = false;
      _resultados = [];
    });
  }

  Future<void> _consultarFactiliza(int seq) async {
    final ruc = _soloDigitos;
    final res = await widget.consultarRuc(ruc);
    if (!mounted || seq != _busquedaSeq) return;
    setState(() {
      _consultando = false;
      if (res['success'] == true) {
        _razonsocial = (res['razonsocial'] ?? '').toString().trim();
        _rucResuelto = ruc;
        if (_razonsocial.isNotEmpty) {
          _resultados = [
            ProveedorCcteItem(ruc: ruc, razonsocial: _razonsocial),
          ];
        } else {
          _resultados = [];
        }
      } else {
        _razonsocial = '';
        _rucResuelto = ruc;
        _resultados = [];
      }
    });
  }

  void _aceptar() {
    final t = _texto;
    if (_rucResuelto.length == 11 && _razonsocial.isNotEmpty) {
      Navigator.pop(
        context,
        ProveedorSeleccion(ruc: _rucResuelto, nombre: _razonsocial),
      );
      return;
    }
    if (_esRucCompleto) {
      Navigator.pop(
        context,
        ProveedorSeleccion(ruc: _soloDigitos, nombre: ''),
      );
      return;
    }
    if (_rucResuelto.length == 11 && _tieneLetras.hasMatch(t)) {
      Navigator.pop(
        context,
        ProveedorSeleccion(ruc: _rucResuelto, nombre: t),
      );
      return;
    }
    Navigator.pop(context, ProveedorSeleccion(ruc: '', nombre: t));
  }

  double _anchoDialogo(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return math.min(560, w - 24);
  }

  @override
  Widget build(BuildContext context) {
    final ancho = _anchoDialogo(context);
    return Dialog(
      backgroundColor: context.dialogSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ancho, minWidth: ancho),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    color: AppColors.iconAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.titulo,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.textThemePrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _campoBusqueda(),
              if (_consultando) _lineaCargando(),
              if (_resultados.isNotEmpty) _listaResultados(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _puedeAceptar ? _aceptar : null,
                    child: const Text('Aceptar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  OutlineInputBorder _bordeCampo({Color? color, double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: color ?? context.borderSubtle,
        width: width,
      ),
    );
  }

  Widget _campoBusqueda() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextField(
            controller: _busquedaCtrl,
            autofocus: true,
            maxLength: 120,
            textCapitalization: TextCapitalization.characters,
            keyboardType: TextInputType.text,
            onChanged: (_) => _alCambiarTexto(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.textThemePrimary,
            ),
            decoration: InputDecoration(
              labelText: 'RUC o nombre',
              hintText: 'Buscar…',
              counterText: '',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: _bordeCampo(),
              focusedBorder: _bordeCampo(
                color: AppColors.primary,
                width: 2,
              ),
              border: _bordeCampo(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 48,
          height: 48,
          child: IconButton.filledTonal(
            onPressed: _consultando ? null : _buscarEnLinea,
            tooltip: 'Buscar proveedor',
            style: IconButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _consultando
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.search_rounded, size: 26),
          ),
        ),
      ],
    );
  }

  Widget _lineaCargando() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: context.textThemeMuted,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Buscando…',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textThemeMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _listaResultados() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: context.borderSubtle.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _resultados.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: context.borderSubtle.withValues(alpha: 0.6),
            ),
            itemBuilder: (context, i) {
              final item = _resultados[i];
              final sub = item.ruc.length == 11
                  ? 'RUC ${item.ruc}'
                  : 'Sin RUC';
              final origen =  sub;
              return ListTile(
                dense: true,
                title: Text(
                  item.razonsocial,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textThemePrimary,
                  ),
                ),
                subtitle: Text(
                  origen,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textThemeMuted,
                  ),
                ),
                onTap: () => _seleccionar(item),
              );
            },
          ),
        ),
      ),
    );
  }
}
