import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/catalog_service.dart';
import '../utils/anomalia_contexto.dart';
import 'evidencia_select_field.dart';
import 'image_slot_row.dart';

class AlcoholemiaPruebaFila {
  String dni = '';
  String nombre = '';
  String valorAparato = '';
  String gradoGl = '';
  String agenteCausal = '';
  String anomalia = '';
  String accion = '';
  final List<String?> fotos = [null, null, null];
}

class AlcoholemiaIngresoState {
  bool activa = false;
  final List<AlcoholemiaPruebaFila> filas = [];
}

/// Backward alias
typedef AlcoholemiaIngresoData = AlcoholemiaIngresoState;

double? _parseGrado(String raw) =>
    double.tryParse(raw.trim().replaceAll(',', '.'));

class IngresoAlcoholemiaSection extends StatefulWidget {
  const IngresoAlcoholemiaSection({
    super.key,
    required this.candidatos,
    required this.data,
    required this.onChanged,
  });

  final List<({String dni, String nombre})> candidatos;
  final AlcoholemiaIngresoState data;
  final ValueChanged<AlcoholemiaIngresoState> onChanged;

  @override
  State<IngresoAlcoholemiaSection> createState() =>
      _IngresoAlcoholemiaSectionState();
}

class _IngresoAlcoholemiaSectionState extends State<IngresoAlcoholemiaSection> {
  void _notify() => widget.onChanged(widget.data);

  void _precargarUnicaPersona() {
    if (widget.candidatos.length != 1) return;
    final c = widget.candidatos.first;
    if (c.dni.isEmpty) return;
    if (widget.data.filas.isEmpty) {
      final fila = AlcoholemiaPruebaFila()
        ..dni = c.dni
        ..nombre = c.nombre;
      widget.data.filas.add(fila);
      return;
    }
    final f = widget.data.filas.first;
    if (f.dni.trim().isEmpty) {
      f.dni = c.dni;
      f.nombre = c.nombre;
    }
  }

  void _asegurarFilaInicial() {
    if (widget.data.filas.isEmpty) {
      if (widget.candidatos.length == 1 && widget.candidatos.first.dni.isNotEmpty) {
        final c = widget.candidatos.first;
        widget.data.filas.add(
          AlcoholemiaPruebaFila()
            ..dni = c.dni
            ..nombre = c.nombre,
        );
      } else {
        widget.data.filas.add(AlcoholemiaPruebaFila());
      }
    } else {
      _precargarUnicaPersona();
    }
  }

  @override
  void didUpdateWidget(covariant IngresoAlcoholemiaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.data.activa) return;
    final candCambio = oldWidget.candidatos.length != widget.candidatos.length ||
        (widget.candidatos.length == 1 &&
            oldWidget.candidatos.isNotEmpty &&
            widget.candidatos.first.dni != oldWidget.candidatos.first.dni);
    if (candCambio || widget.data.filas.isEmpty) {
      _asegurarFilaInicial();
      _precargarUnicaPersona();
      _notify();
      if (mounted) setState(() {});
    }
  }

  void _agregarFila() {
    setState(() {
      widget.data.filas.add(AlcoholemiaPruebaFila());
      _notify();
    });
  }

  void _quitarFila(int index) {
    if (widget.data.filas.length <= 1) return;
    setState(() {
      widget.data.filas.removeAt(index);
      _notify();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _verdeAlc, width: 1.4),
      ),
      child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Row(
          children: [
            const Icon(Icons.local_bar_outlined, size: 18, color: _verdeAlc),
            const SizedBox(width: 8),
            const Text(
              'Alcoholemia',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _verdeAlc,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          activeThumbColor: _verdeAlc,
          title: const Text(
            'Registrar',
            style: TextStyle(fontWeight: FontWeight.w700, color: _verdeAlc),
          ),
          value: widget.data.activa,
          onChanged: (v) {
            setState(() {
              widget.data.activa = v;
              if (v) {
                _asegurarFilaInicial();
                _precargarUnicaPersona();
              }
              _notify();
            });
          },
        ),
        if (widget.data.activa) ...[
          const SizedBox(height: 4),
          for (var i = 0; i < widget.data.filas.length; i++) ...[
            _FilaAlcoholemiaTile(
              key: ValueKey('alc-fila-$i-${widget.data.filas[i].dni}'),
              index: i,
              fila: widget.data.filas[i],
              candidatos: widget.candidatos,
              puedeQuitar: widget.data.filas.length > 1,
              onQuitar: () => _quitarFila(i),
              onChanged: () {
                setState(() {});
                _notify();
              },
            ),
            if (i < widget.data.filas.length - 1) const Divider(height: 20),
          ],
          TextButton.icon(
            onPressed: _agregarFila,
            style: TextButton.styleFrom(foregroundColor: _verdeAlc),
            icon: const Icon(Icons.person_add_outlined),
            label: const Text('Agregar persona'),
          ),
        ],
        ],
      ),
      ),
    );
  }
}

class _FilaAlcoholemiaTile extends StatefulWidget {
  const _FilaAlcoholemiaTile({
    super.key,
    required this.index,
    required this.fila,
    required this.candidatos,
    required this.puedeQuitar,
    required this.onQuitar,
    required this.onChanged,
  });

  final int index;
  final AlcoholemiaPruebaFila fila;
  final List<({String dni, String nombre})> candidatos;
  final bool puedeQuitar;
  final VoidCallback onQuitar;
  final VoidCallback onChanged;

  @override
  State<_FilaAlcoholemiaTile> createState() => _FilaAlcoholemiaTileState();
}

const _verdeAlc = Color(0xFF0FA3B1);

class _FilaAlcoholemiaTileState extends State<_FilaAlcoholemiaTile> {
  late final TextEditingController _valor;
  late final TextEditingController _grado;
  late final TextEditingController _accion;
  late final TextEditingController _anomalia;
  late final TextEditingController _agente;
  bool _syncLecturaGrado = true;
  bool _anomaliaTocada = false;
  bool _agenteTocado = false;
  String _anomaliaAuto = '';
  String _agenteAuto = '';

  @override
  void initState() {
    super.initState();
    _valor = TextEditingController(text: widget.fila.valorAparato);
    _grado = TextEditingController(text: widget.fila.gradoGl);
    _accion = TextEditingController(text: widget.fila.accion);
    _anomalia = TextEditingController(text: widget.fila.anomalia);
    _agente = TextEditingController(text: widget.fila.agenteCausal);
    _anomaliaTocada = widget.fila.anomalia.trim().isNotEmpty;
    _agenteTocado = widget.fila.agenteCausal.trim().isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _aplicarDefaults());
  }

  void _aplicarDefaults() {
    _actualizarAnomalia();
  }

  @override
  void dispose() {
    _valor.dispose();
    _grado.dispose();
    _accion.dispose();
    _anomalia.dispose();
    _agente.dispose();
    super.dispose();
  }

  double? get _gradoNum => _parseGrado(_grado.text);

  bool _superaUmbral(double umbral) {
    final g = _gradoNum;
    if (g == null) return false;
    return g > umbral + 1e-9;
  }

  void _ponerAuto({
    required TextEditingController ctrl,
    required bool tocado,
    required String autoPrevio,
    required String nuevo,
    required void Function(String texto) guardarAuto,
    required void Function(String texto) guardarFila,
  }) {
    final actual = ctrl.text;
    final sigueAuto = !tocado || actual.trim().isEmpty || actual == autoPrevio;
    if (sigueAuto) {
      if (actual != nuevo) {
        ctrl.value = TextEditingValue(
          text: nuevo,
          selection: TextSelection.collapsed(offset: nuevo.length),
        );
      }
      guardarAuto(nuevo);
      guardarFila(nuevo);
    } else {
      guardarFila(actual);
    }
  }

  void _actualizarAnomalia() {
    final umbral = context.read<CatalogService>().alcoholemiaMeta.umbralGl;
    final g = _gradoNum;
    if (g != null && _superaUmbral(umbral)) {
      final meta = context.read<CatalogService>().alcoholemiaMeta;
      final ctx = AnomaliaContexto.alcoholemia(
        dni: widget.fila.dni,
        nombre: widget.fila.nombre,
        gradoGl: g,
        umbral: umbral,
        agenteDef: meta.agenteCausalDef,
        accionDef: meta.accionDef,
      );
      _ponerAuto(
        ctrl: _anomalia,
        tocado: _anomaliaTocada,
        autoPrevio: _anomaliaAuto,
        nuevo: ctx.anomalia,
        guardarAuto: (t) => _anomaliaAuto = t,
        guardarFila: (t) => widget.fila.anomalia = t,
      );
      _ponerAuto(
        ctrl: _agente,
        tocado: _agenteTocado,
        autoPrevio: _agenteAuto,
        nuevo: ctx.agenteCausal,
        guardarAuto: (t) => _agenteAuto = t,
        guardarFila: (t) => widget.fila.agenteCausal = t,
      );
      if (widget.fila.accion.trim().isEmpty) {
        widget.fila.accion = ctx.accion;
        if (_accion.text != ctx.accion) _accion.text = ctx.accion;
      }
    }
  }

  void _onLecturaChanged(String v) {
    widget.fila.valorAparato = v;
    final p = _parseGrado(v);
    if (p != null && _syncLecturaGrado) {
      final g = p.toString();
      if (_grado.text != g) {
        _grado.text = g;
        widget.fila.gradoGl = g;
      }
    } else if (p == null && v.trim().isNotEmpty) {
      _syncLecturaGrado = false;
    }
    _actualizarAnomalia();
    widget.onChanged();
  }

  void _onGradoChanged(String v) {
    widget.fila.gradoGl = v;
    final p = _parseGrado(v);
    final pLect = _parseGrado(_valor.text);
    if (p != null && pLect != null && (p - pLect).abs() > 1e-9) {
      _syncLecturaGrado = false;
    }
    if (p != null && _syncLecturaGrado && _valor.text != v) {
      _valor.text = v;
      widget.fila.valorAparato = v;
    }
    _actualizarAnomalia();
    setState(() {});
    widget.onChanged();
  }

  Future<void> _pickPersona() async {
    if (widget.candidatos.isEmpty) return;
    final sel = await showModalBottomSheet<({String dni, String nombre})>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Persona a evaluar')),
            for (final c in widget.candidatos)
              ListTile(
                title: Text(c.nombre.isNotEmpty ? c.nombre : c.dni),
                subtitle: Text(c.dni),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (sel == null) return;
    setState(() {
      widget.fila.dni = sel.dni;
      widget.fila.nombre = sel.nombre;
      _actualizarAnomalia();
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<CatalogService>().alcoholemiaMeta;
    final labelPersona = widget.fila.dni.isEmpty
        ? ''
        : '${widget.fila.nombre.isNotEmpty ? widget.fila.nombre : widget.fila.dni} · ${widget.fila.dni}';
    final supera = _superaUmbral(meta.umbralGl);

    final g = _gradoNum;
    final colorEstado = g != null && g > meta.umbralGl + 0.10
        ? const Color(0xFFC62828)
        : const Color(0xFFF9A825);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Persona ${widget.index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: _verdeAlc,
                ),
              ),
            ),
            if (widget.puedeQuitar)
              IconButton(
                tooltip: 'Quitar',
                onPressed: widget.onQuitar,
                icon: const Icon(Icons.close, size: 20, color: _verdeAlc),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        EvidenciaSelectField(
          label: 'Persona',
          value: labelPersona,
          placeholder: 'Seleccione',
          icon: Icons.person_outline,
          iconColor: _verdeAlc,
          onTap: widget.candidatos.isEmpty ? null : _pickPersona,
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _valor,
                cursorColor: _verdeAlc,
                showCursor: true,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: _campoClaro('Lectura aparato'),
                onChanged: _onLecturaChanged,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _grado,
                cursorColor: _verdeAlc,
                showCursor: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                decoration: _campoClaro('Grado (g/L)'),
                onChanged: _onGradoChanged,
              ),
            ),
          ],
        ),
        ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            heightFactor: supera ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colorEstado.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colorEstado, width: 1.4),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(
                            supera && g != null && g > meta.umbralGl + 0.10
                                ? Icons.error_rounded
                                : Icons.warning_amber_rounded,
                            size: 18,
                            color: colorEstado,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Anomalía',
                            style: TextStyle(
                              color: colorEstado,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _anomalia,
                        cursorColor: _verdeAlc,
                        showCursor: true,
                        minLines: 1,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        decoration: _campoClaro('Anomalía'),
                        onChanged: (v) {
                          _anomaliaTocada = true;
                          widget.fila.anomalia = v;
                          widget.onChanged();
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _agente,
                        cursorColor: _verdeAlc,
                        showCursor: true,
                        minLines: 1,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        decoration: _campoClaro('Agente causal'),
                        onChanged: (v) {
                          _agenteTocado = true;
                          widget.fila.agenteCausal = v;
                          widget.onChanged();
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _accion,
                        cursorColor: _verdeAlc,
                        showCursor: true,
                        minLines: 2,
                        maxLines: 3,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        decoration: _campoClaro('Acción'),
                        onChanged: (v) {
                          widget.fila.accion = v;
                          widget.onChanged();
                        },
                      ),
                      const SizedBox(height: 10),
                      ImageSlotRow(
                        paths: widget.fila.fotos,
                        onChanged: (i, path) {
                          widget.fila.fotos[i] = path;
                          widget.onChanged();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

InputDecoration _campoClaro(String label) {
  const borde = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
    borderSide: BorderSide(color: _verdeAlc, width: 1.5),
  );
  return const InputDecoration(
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    floatingLabelBehavior: FloatingLabelBehavior.auto,
  ).copyWith(
    labelText: label,
    labelStyle: const TextStyle(color: _verdeAlc, fontWeight: FontWeight.w600),
    floatingLabelStyle: const TextStyle(
      color: _verdeAlc,
      fontWeight: FontWeight.w700,
    ),
    contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
    border: borde,
    enabledBorder: borde,
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: _verdeAlc, width: 2),
    ),
  );
}

class AlcoholemiaCatalogMeta {
  const AlcoholemiaCatalogMeta({
    required this.umbralGl,
    required this.agenteCausalDef,
    required this.accionDef,
  });

  final double umbralGl;
  final String agenteCausalDef;
  final String accionDef;

  static const fallback = AlcoholemiaCatalogMeta(
    umbralGl: 0,
    agenteCausalDef: 'Alcohol en aliento detectado en control de alcoholemia',
    accionDef: 'Negar ingreso. Comunicar al supervisor de bioseguridad.',
  );
}