import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../services/ingreso_presencia_service.dart';
import '../services/plan_visitas_service.dart';
import '../services/storage_service.dart';
import '../utils/constants.dart';
import '../utils/plan_ingreso_helper.dart';
import '../utils/record_saver.dart';
import '../utils/theme_colors.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bio_form_fields.dart';
import '../widgets/granja_campania_picker.dart';
import '../widgets/presencia_escaneo_identificar.dart';
import '../widgets/section_app_bar.dart';
import 'register_summary_screen.dart';

String _horaDelDia(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

String _fmtFechaIngreso(String ymd) {
  final s = ymd.trim();
  if (s.isEmpty) return '—';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  return DateFormat('dd/MM/yyyy').format(d);
}

/// Ingresos con personal dentro; registrar salidas escaneando DNI o placa.
class RegisterSalidaScreen extends StatefulWidget {
  const RegisterSalidaScreen({super.key});

  @override
  State<RegisterSalidaScreen> createState() => _RegisterSalidaScreenState();
}

class _RegisterSalidaScreenState extends State<RegisterSalidaScreen> {
  static const _sepBloque = 16.0;
  static const _sepCampo = 12.0;

  final DateTime _fecha = DateTime.now();
  String _granja = '';
  String _granjaNombre = '';
  StorageService? _storage;

  final _escaneoKey = GlobalKey<PresenciaEscaneoIdentificarState>();

  late String _hora;
  bool _salidaTemporal = false;

  String get _fechaYmd => DateFormat('yyyy-MM-dd').format(_fecha);

  PresenciaEscaneoIdentificarState? get _escaneo => _escaneoKey.currentState;

  bool get _hayEscaneos => _escaneo?.hayEscaneos ?? false;

  List<PresenciaEscaneoGrupoPlan> _gruposSalidaParaGuardar() =>
      _escaneo?.gruposParaGuardar() ?? const [];

  String _etiquetaGrupoSalida(GrupoPresencia g, {required int indice}) =>
      _escaneo?.etiquetaGrupo(g, indice: indice) ??
      (g.proveedor.trim().isNotEmpty && g.proveedor.trim() != '—'
          ? g.proveedor.trim()
          : 'Ingreso');

  @override
  void initState() {
    super.initState();
    _hora = _horaDelDia(DateTime.now());
    _storage = context.read<StorageService>();
    _storage!.addListener(_refrescar);
  }

  @override
  void dispose() {
    _storage?.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  void _limpiarEscaneos() {
    _escaneo?.limpiar();
    setState(() {
      _hora = _horaDelDia(DateTime.now());
      _salidaTemporal = false;
    });
  }

  Map<String, dynamic> _buildRecordSalida(
    PresenciaEscaneoGrupoPlan plan,
    StorageService storage,
  ) {
    final grupo = plan.grupo;
    return {
      'id': const Uuid().v4(),
      'reporte': 'salida',
      'fecha': _fechaYmd,
      'granja': grupo.granja.isNotEmpty ? grupo.granja : _granja,
      'granjaNombre': grupo.granjaNombre.isNotEmpty
          ? grupo.granjaNombre
          : _granjaNombre,
      'campania': grupo.campania,
      'turno': grupo.turno.isNotEmpty ? grupo.turno : 'Dia',
      'usuario': storage.getUserCodeSync() ?? '',
      'nombre_usuario': storage.getUserName() ?? '',
      'registro': {
        'hora': _hora.trim(),
        'movimiento': 'salida',
        'tipo_salida': _salidaTemporal
            ? IngresoPresenciaService.tipoSalidaTemporal
            : IngresoPresenciaService.tipoSalidaDefinitiva,
        'grupo_id': grupo.grupoId,
        'proveedor': grupo.proveedor,
        'motivo': grupo.motivo,
        'dnis': plan.personas
            .map((p) => {'dni': p.dni, 'nombre': p.nombre})
            .toList(),
        if (plan.vehiculos.isNotEmpty)
          'vehiculos': plan.vehiculos
              .map((v) => {'placa': v.etiqueta})
              .toList(),
      },
      'imagenes': const [],
      'synced': false,
      'guardado_backend': false,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  Future<void> _postGuardarSalidaOk(
    StorageService storage,
    GrupoPresencia grupo,
  ) async {
    if (_salidaTemporal) return;
    final planId = planVisitaIdDeGrupoPresencia(
      grupo.grupoId,
      planVisitaId: grupo.planVisitaId,
    );
    if (planId == null) return;
    final fechaIngreso = grupo.fechaIngreso.trim();
    await cerrarPlanVisitaTrasSalidaDefinitiva(
      storage,
      planVisitaId: planId,
      fechaYmd: fechaIngreso.isNotEmpty ? fechaIngreso : _fechaYmd,
    );
  }

  Future<void> _confirmarGuardadoRecord(
    Map<String, dynamic> record,
    StorageService storage,
    GrupoPresencia grupo,
  ) async {
    final ok = await BioRecordSaver.save(context, record);
    if (!mounted) return;
    // Cerrar planificación en local aunque el servidor no confirme aún.
    await _postGuardarSalidaOk(storage, grupo);
    if (!mounted) return;
    if (ok) {
      showSuccessToast(context, AppStrings.salidaGuardadoEnviado);
    } else {
      showInfoToast(context, AppStrings.salidaGuardadoLocalSync);
    }
  }

  Future<void> _guardarVariasSalidas(
    List<PresenciaEscaneoGrupoPlan> planes,
    StorageService storage,
  ) async {
    final total = planes.length;
    for (var i = 0; i < total; i++) {
      if (!mounted) return;
      final plan = planes[i];
      final record = _buildRecordSalida(plan, storage);
      final saved = await RegisterSummarySheet.show(
        context,
        record: record,
        titulo: 'Resumen salida ${i + 1} de $total',
        onConfirm: () => _confirmarGuardadoRecord(
          record,
          storage,
          plan.grupo,
        ),
      );
      if (!saved) return;
    }
    if (mounted) _limpiarEscaneos();
  }

  Future<void> _guardar() async {
    _escaneo?.confirmarPendientes();
    if (!_hayEscaneos) {
      showErrorToast(context, 'Escanee DNI o placa antes de guardar.');
      return;
    }
    if (_hora.trim().isEmpty) {
      showErrorToast(context, 'Indique la hora.');
      return;
    }

    final storage = context.read<StorageService>();
    final planes = _gruposSalidaParaGuardar();
    if (planes.isEmpty) {
      showErrorToast(
        context,
        'Complete documento o placa en la tabla antes de guardar.',
      );
      return;
    }

    if (planes.length > 1) {
      await _guardarVariasSalidas(planes, storage);
      return;
    }

    final plan = planes.first;
    final record = _buildRecordSalida(plan, storage);
    final saved = await RegisterSummarySheet.show(
      context,
      record: record,
      onConfirm: () => _confirmarGuardadoRecord(
        record,
        storage,
        plan.grupo,
      ),
    );
    if (saved && mounted) {
      _limpiarEscaneos();
    }
  }

  Map<String, dynamic>? _registroIngresoDeGrupo(GrupoPresencia grupo) {
    final storage = _storage;
    if (storage == null) return null;
    final gid = grupo.grupoId;
    for (final r in storage.getMyRecords()) {
      if ((r['reporte'] ?? '').toString() != 'ingreso') continue;
      if (IngresoPresenciaService.grupoIdDeIngreso(r) == gid) return r;
    }
    return null;
  }

  Widget _lineaFichaIngresoSalida(
    BuildContext context,
    String etiqueta,
    String valor, {
    int maxLines = 2,
  }) {
    final v = valor.trim().isEmpty ? '—' : valor.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: context.textThemePrimary,
          ),
          children: [
            TextSpan(
              text: '$etiqueta: ',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.textThemeSecondary,
              ),
            ),
            TextSpan(
              text: v,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenidoFichaIngresoSalida(
    BuildContext context,
    GrupoPresencia grupo,
  ) {
    final planificado = IngresoPresenciaService.esPlanificado(grupo);
    final visita = _visitaPlanDeGrupo(grupo);
    final granjaTxt = GranjaCampaniaPicker.formatGranjaLabel(
      grupo.granja,
      grupo.granjaNombre,
    );
    final camp = grupo.campania.trim().isNotEmpty
        ? GranjaCampaniaPicker.padCampania(grupo.campania)
        : '—';
    final turno = grupo.turno.trim().isEmpty
        ? '—'
        : (grupo.turno == 'Dia' ? 'Día' : grupo.turno);
    final fechaIngreso = _fmtFechaIngreso(grupo.fechaIngreso);

    if (planificado && visita != null) {
      final form = PlanIngresoFormState();
      vincularVisitaPlanEnFormulario(form: form, visita: visita);
      final galponTxt = visita.galpones.isNotEmpty
          ? visita.galpones.join(', ')
          : '—';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _lineaFichaIngresoSalida(context, 'Fecha', fechaIngreso),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _lineaFichaIngresoSalida(context, 'Turno', turno),
              ),
            ],
          ),
          _lineaFichaIngresoSalida(context, 'Granja', granjaTxt),
          _lineaFichaIngresoSalida(context, 'Campaña', camp),
          _lineaFichaIngresoSalida(
            context,
            'Galpones',
            galponTxt,
            maxLines: 4,
          ),
          _lineaFichaIngresoSalida(
            context,
            'Proveedor',
            form.proveedor.etiqueta,
            maxLines: 3,
          ),
          _lineaFichaIngresoSalida(
            context,
            'Proceso',
            form.proceso.isEmpty ? grupo.motivo : form.proceso,
            maxLines: 3,
          ),
          if (form.observacion.trim().isNotEmpty)
            _lineaFichaIngresoSalida(
              context,
              'Observación',
              form.observacion.trim(),
              maxLines: 4,
            ),
        ],
      );
    }

    final record = _registroIngresoDeGrupo(grupo);
    final reg = Map<String, dynamic>.from(
      (record?['registro'] as Map?) ?? const {},
    );
    final galpon = reg['galpon']?.toString().trim() ?? '';
    final obs = reg['observacion']?.toString().trim() ?? '';
    final proceso = grupo.motivo.trim().isNotEmpty
        ? grupo.motivo.trim()
        : (reg['motivo']?.toString().trim() ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _lineaFichaIngresoSalida(context, 'Fecha', fechaIngreso),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _lineaFichaIngresoSalida(context, 'Turno', turno),
            ),
          ],
        ),
        _lineaFichaIngresoSalida(context, 'Granja', granjaTxt),
        _lineaFichaIngresoSalida(context, 'Campaña', camp),
        if (galpon.isNotEmpty)
          _lineaFichaIngresoSalida(context, 'Galpones', galpon, maxLines: 4),
        _lineaFichaIngresoSalida(
          context,
          'Proveedor',
          proveedorIngresoResumen(reg),
          maxLines: 3,
        ),
        if (proceso.isNotEmpty)
          _lineaFichaIngresoSalida(context, 'Proceso', proceso, maxLines: 3),
        if (obs.isNotEmpty)
          _lineaFichaIngresoSalida(context, 'Observación', obs, maxLines: 4),
      ],
    );
  }

  PlanVisita? _visitaPlanDeGrupo(GrupoPresencia grupo) {
    final planId = planVisitaIdDeGrupoPresencia(
      grupo.grupoId,
      planVisitaId: grupo.planVisitaId,
    );
    if (planId == null) return null;
    final id = int.tryParse(planId);
    if (id == null) return null;
    return PlanVisitasService.local(_storage!).visitaPorId(id);
  }

  Future<void> _mostrarDialogoFichaIngresoSalida(GrupoPresencia grupo) async {
    if (!mounted) return;
    final planificado = IngresoPresenciaService.esPlanificado(grupo);
    final visita = _visitaPlanDeGrupo(grupo);
    final titulo = planificado && visita != null
        ? (visita.razonSocial.trim().isNotEmpty
            ? visita.razonSocial.trim()
            : 'Visita planificada #${visita.id}')
        : (grupo.proveedor.trim().isNotEmpty && grupo.proveedor.trim() != '—'
            ? grupo.proveedor.trim()
            : 'Ficha de ingreso');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final ancho = MediaQuery.sizeOf(dialogContext).width - 16;
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ancho, minWidth: ancho),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    child: _contenidoFichaIngresoSalida(dialogContext, grupo),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTarjetaIngresoSalida(
    BuildContext context,
    GrupoPresencia grupo, {
    int indice = 1,
    bool varias = false,
  }) {
    final horaIngreso = grupo.horaIngreso.trim().isEmpty
        ? '—'
        : grupo.horaIngreso.trim();

    final bloque = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (varias) ...[
          Text(
            _etiquetaGrupoSalida(grupo, indice: indice),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: _sepCampo),
        ],
        BioReadOnlyField(
          label: 'Hora de ingreso',
          value: horaIngreso,
          icon: Icons.schedule_rounded,
        ),
        const SizedBox(height: _sepCampo),
        OutlinedButton.icon(
          onPressed: () => _mostrarDialogoFichaIngresoSalida(grupo),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: Text(
            varias
                ? 'Ver Ficha de Ingreso $indice'
                : 'Ver Ficha de Ingreso',
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: AppColors.primaryDark,
          ),
        ),
      ],
    );

    if (varias) return bloque;

    return BioFormSection(
      title: '2. Información de ingreso',
      icon: Icons.login_rounded,
      children: [bloque],
    );
  }

  Widget _buildSeccionIngresosSalida(BuildContext context) {
    final planes = _gruposSalidaParaGuardar();
    if (planes.isEmpty) return const SizedBox.shrink();
    final varias = planes.length > 1;

    if (!varias) {
      return _buildTarjetaIngresoSalida(context, planes.first.grupo);
    }

    return BioFormSection(
      title: '2. Información de ingreso (${planes.length})',
      icon: Icons.login_rounded,
      children: [
        for (var i = 0; i < planes.length; i++) ...[
          if (i > 0) const SizedBox(height: _sepCampo),
          _buildTarjetaIngresoSalida(
            context,
            planes[i].grupo,
            indice: i + 1,
            varias: true,
          ),
        ],
      ],
    );
  }

  Widget _buildSeccionConfirmarSalida(BuildContext context) {
    return BioFormSection(
      title: '3. Confirmar salida',
      icon: Icons.task_alt_rounded,
      children: [
        BioTimeField(
          label: 'Hora de salida',
          value: _hora,
          onPicked: (h) => setState(() => _hora = h),
        ),
        const SizedBox(height: _sepCampo),
        Center(
          child: Text(
            'Tipo de salida',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: context.textThemeSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('Definitiva'),
                icon: Icon(Icons.done_all_rounded, size: 18),
              ),
              ButtonSegment(
                value: true,
                label: Text('Temporal'),
                icon: Icon(Icons.schedule_rounded, size: 18),
              ),
            ],
            selected: {_salidaTemporal},
            onSelectionChanged: (s) =>
                setState(() => _salidaTemporal = s.first),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = 24 + MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: SectionAppBar(
        title: AppStrings.menuSalida,
        sectionIcon: Icons.logout_rounded,
        actions: [
          if (_hayEscaneos) AppBarSaveButton(onPressed: _guardar),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          _refrescar();
        },
        color: AppColors.primaryDark,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPad),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BioFormSection(
                title: '1. Identificar',
                icon: Icons.qr_code_scanner_rounded,
                children: [
                  PresenciaEscaneoIdentificar(
                    key: _escaneoKey,
                    flujo: PresenciaEscaneoFlujo.salida,
                    fechaYmd: _fechaYmd,
                    granja: _granja,
                    granjaNombre: _granjaNombre,
                    onChanged: _refrescar,
                  ),
                ],
              ),
              if (_hayEscaneos) ...[
                const SizedBox(height: _sepBloque),
                _buildSeccionIngresosSalida(context),
                const SizedBox(height: _sepBloque),
                _buildSeccionConfirmarSalida(context),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
