import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/ingreso_presencia_service.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

String fmtFechaGrupoPresencia(String ymd) {
  final s = ymd.trim();
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s);
  if (d == null) return s;
  return DateFormat('dd/MM/yyyy').format(d);
}

/// Encabezado de bloque en listas de salida/regreso.
class GrupoPresenciaSeccionTitulo extends StatelessWidget {
  const GrupoPresenciaSeccionTitulo({
    super.key,
    required this.titulo,
    this.icon,
  });

  final String titulo;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.primaryDark),
            const SizedBox(width: 8),
          ],
          Text(
            titulo,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.textThemePrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta compacta de un ingreso/grupo para salida o regreso.
class GrupoPresenciaTarjeta extends StatelessWidget {
  const GrupoPresenciaTarjeta({
    super.key,
    required this.grupo,
    required this.onTap,
    required this.modo,
  });

  final GrupoPresencia grupo;
  final VoidCallback onTap;

  /// [modoSalida]: conteo en granja; [modoRegreso]: pendientes de regreso.
  final GrupoPresenciaListaModo modo;

  @override
  Widget build(BuildContext context) {
    final planificado = IngresoPresenciaService.esPlanificado(grupo);
    final fechaTxt = fmtFechaGrupoPresencia(grupo.fechaIngreso);
    final nPersonasSalida = grupo.dentro.length;
    final nVehiculosSalida = grupo.vehiculosDentro.length;
    final nPersonasRegreso = grupo.fueraTemporal.length;
    final nVehiculosRegreso = grupo.vehiculosFueraTemporal.length;

    return Material(
      color: context.surfaceCard,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderSubtle),
          ),
          padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                grupo.proveedor,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.textThemePrimary,
                                ),
                              ),
                            ),
                            if (planificado)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Planificado',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primaryDark,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (grupo.motivo.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            grupo.motivo,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textThemeMuted,
                            ),
                          ),
                        ],
                        if (fechaTxt.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Ingreso $fechaTxt'
                            '${grupo.horaIngreso.isEmpty ? '' : ' · ${grupo.horaIngreso}'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textThemeSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.textThemeMuted,
                    size: 28,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _FilaConteoPresencia(
                modo: modo,
                vehiculos: modo == GrupoPresenciaListaModo.salida
                    ? nVehiculosSalida
                    : nVehiculosRegreso,
                personas: modo == GrupoPresenciaListaModo.salida
                    ? nPersonasSalida
                    : nPersonasRegreso,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum GrupoPresenciaListaModo { salida, regreso }

/// Segunda fila de la tarjeta: vehículos y personas en la misma línea (ancho completo).
class _FilaConteoPresencia extends StatelessWidget {
  const _FilaConteoPresencia({
    required this.modo,
    required this.vehiculos,
    required this.personas,
  });

  final GrupoPresenciaListaModo modo;
  final int vehiculos;
  final int personas;

  @override
  Widget build(BuildContext context) {
    final pendiente = modo == GrupoPresenciaListaModo.regreso;
    final color = pendiente ? AppColors.warning : AppColors.success;
    final sufijo = pendiente ? ' (pend. regreso)' : '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'N° de vehículos$sufijo: $vehiculos',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              'N° de personas$sufijo: $personas',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lista con secciones: visita planificada vs ingreso sin plan del portal.
List<Widget> buildListaGruposPresenciaSeccionada({
  required BuildContext context,
  required List<GrupoPresencia> grupos,
  required GrupoPresenciaListaModo modo,
  required void Function(GrupoPresencia) onTap,
}) {
  final plan = grupos
      .where(IngresoPresenciaService.esPlanificado)
      .toList();
  final otros = grupos
      .where((g) => !IngresoPresenciaService.esPlanificado(g))
      .toList();

  final out = <Widget>[];

  void addSeccion(String titulo, IconData icon, List<GrupoPresencia> lista) {
    if (lista.isEmpty) return;
    out.add(GrupoPresenciaSeccionTitulo(titulo: titulo, icon: icon));
    for (var i = 0; i < lista.length; i++) {
      if (i > 0) out.add(const SizedBox(height: 10));
      out.add(
        GrupoPresenciaTarjeta(
          grupo: lista[i],
          modo: modo,
          onTap: () => onTap(lista[i]),
        ),
      );
    }
  }

  addSeccion(
    'Visitas planificadas',
    Icons.event_available_rounded,
    plan,
  );
  addSeccion(
    'Ingresos sin planificación',
    Icons.person_add_alt_1_rounded,
    otros,
  );

  if (out.isEmpty) {
    out.add(
      Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          modo == GrupoPresenciaListaModo.salida
              ? 'Sin ingresos abiertos.'
              : 'Sin pendientes.',
          textAlign: TextAlign.center,
          style: TextStyle(color: context.textThemeMuted),
        ),
      ),
    );
  }

  return out;
}
