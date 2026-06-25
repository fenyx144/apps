import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/constants.dart';
import '../utils/toast_helper.dart';
import '../widgets/app_drawer.dart';
import '../services/storage_service.dart';
import '../widgets/app_bar.dart';

class ReportesScreen extends StatefulWidget {
  const ReportesScreen({super.key});

  @override
  State<ReportesScreen> createState() => _ReportesScreenState();
}

class _ReportesScreenState extends State<ReportesScreen>
    with TickerProviderStateMixin {
  late AnimationController _mainAnimationController;
  final List<Animation<double>> _cardAnimations = [];

  DateTime? _fechaDesde;
  DateTime? _fechaHasta;
  List<Map<String, dynamic>> _registros = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _mainAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    for (int i = 0; i < 3; i++) {
      final delay = i * 0.1;
      _cardAnimations.add(
        Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _mainAnimationController,
            curve: Interval(delay, 0.6 + delay, curve: Curves.easeOutCubic),
          ),
        ),
      );
    }
    _inicializarFechasSemanaActual();
    _mainAnimationController.forward();
  }

  @override
  void dispose() {
    _mainAnimationController.dispose();
    super.dispose();
  }

  void _inicializarFechasSemanaActual() {
    final hoy = DateTime.now();
    final lunes = hoy.subtract(Duration(days: hoy.weekday - 1));
    final domingo = lunes.add(const Duration(days: 6));
    setState(() {
      _fechaDesde = DateTime(lunes.year, lunes.month, lunes.day);
      _fechaHasta = DateTime(domingo.year, domingo.month, domingo.day);
    });
    _cargarRegistros();
  }

  Future<void> _cargarRegistros() async {
    if (_fechaDesde == null || _fechaHasta == null) {
      if (!mounted) return;
      showInfoToast(context, 'Por favor selecciona ambas fechas.');
      return;
    }
    if (_fechaDesde!.isAfter(_fechaHasta!)) {
      if (!mounted) return;
      showErrorToast(
        context,
        'La fecha "Desde" no puede ser posterior a "Hasta".',
      );
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    try {
      final storage = context.read<StorageService>();
      List<Map<String, dynamic>> todos = storage.getAllRecords(
        AppStrings.formType1,
      );

      final desde = DateTime(
        _fechaDesde!.year,
        _fechaDesde!.month,
        _fechaDesde!.day,
      );
      final hasta = DateTime(
        _fechaHasta!.year,
        _fechaHasta!.month,
        _fechaHasta!.day,
      );

      final filtrados = todos.where((reg) {
        final fechaStr = reg['fecha'] as String?;
        if (fechaStr == null || fechaStr.isEmpty) return false;
        DateTime? fecha;
        try {
          fecha = DateFormat('yyyy-MM-dd').parse(fechaStr);
          fecha = DateTime(fecha.year, fecha.month, fecha.day);
        } catch (e) {
          return false;
        }
        return !fecha.isBefore(desde) && !fecha.isAfter(hasta);
      }).toList();

      if (mounted) {
        setState(() {
          _registros = filtrados;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorToast(context, 'Error al cargar los registros.');
      }
    }
  }

  Future<void> _seleccionarFecha(BuildContext context, bool esDesde) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: esDesde
          ? (_fechaDesde ?? DateTime.now())
          : (_fechaHasta ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      locale: const Locale('es', 'ES'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        if (esDesde) {
          _fechaDesde = picked;
        } else {
          _fechaHasta = picked;
        }
      });
    }
  }

  String _safeString(dynamic value) => (value ?? '').toString().trim();

  String _formatearFecha(String? fechaStr) {
    if (fechaStr == null || fechaStr.isEmpty) return '–';
    try {
      final fecha = DateFormat('yyyy-MM-dd').parse(fechaStr);
      return DateFormat('dd/MM/yyyy').format(fecha);
    } catch (e) {
      return fechaStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _registros.isEmpty) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FD),
      appBar: buildAppBar(context, 'Reportes', appIcon: Icons.bar_chart_outlined),
      drawer: const AppDrawer(),
      body: SizedBox.expand(
        child: Container(
          color: const Color(0xFF667EEA),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FadeTransition(
                  opacity: _cardAnimations[0],
                  child: _buildDateFilters(),
                ),
                const SizedBox(height: 20),
                FadeTransition(
                  opacity: _cardAnimations[1],
                  child: _buildSearchButton(),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: _cardAnimations[2],
                  child: _buildResultsSection(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateFilters() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => _seleccionarFecha(context, true),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withOpacity(0.2),
                          AppColors.accentLight.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Desde',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fechaDesde != null
                              ? DateFormat('dd/MM/yyyy').format(_fechaDesde!)
                              : 'Seleccionar',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () => _seleccionarFecha(context, false),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accent.withOpacity(0.2),
                          AppColors.accentLight.withOpacity(0.1),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.calendar_today,
                      color: AppColors.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hasta',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fechaHasta != null
                              ? DateFormat('dd/MM/yyyy').format(_fechaHasta!)
                              : 'Seleccionar',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchButton() {
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: _isLoading
            ? null
            : const LinearGradient(
                colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
              ),
        boxShadow: _isLoading
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF667EEA).withOpacity(0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _cargarRegistros,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_rounded, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'BUSCAR',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildResultsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.list_alt,
                color: AppColors.accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Registros Mostrados (${_registros.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_isLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32.0),
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          )
        else if (_registros.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8),
              ],
            ),
            child: Column(
              children: [
                Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'No hay registros en este rango de fechas',
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _registros.length,
            itemBuilder: (context, index) {
              final r = _registros[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'ID: ${_safeString(r['id'])}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Fecha: ${_formatearFecha(r['fecha'])}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: (r['synced'] == true)
                                  ? AppColors.success.withOpacity(0.15)
                                  : AppColors.error.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              (r['synced'] == true) ? 'Subido' : 'Pendiente',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: (r['synced'] == true)
                                    ? AppColors.success
                                    : AppColors.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      _buildDetailRow(
                        'Provincia',
                        _safeString(r['provincia_nombre']),
                      ),
                      _buildDetailRow(
                        'Mercado',
                        _safeString(r['mercado_nombre']),
                      ),
                      _buildDetailRow(
                        'Tipo',
                        _safeString(r['tipo_establecimiento']),
                      ),
                      _buildDetailRow('Tamaño', _safeString(r['tamanio'])),
                      _buildDetailRow('Cantidad', _safeString(r['cantidad'])),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.isEmpty ? '–' : value,
              style: const TextStyle(fontSize: 13),
              softWrap: true,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
