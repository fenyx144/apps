import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';

/// Selector granja + campaña (misma lógica que dashboard-evidencias-fotograficas.php).
class GranjaCampaniaPicker {
  static String normGranja(String cod) {
    var s = cod.trim();
    if (s.isEmpty) return '';
    while (s.length < 3) {
      s = '0$s';
    }
    return s.length > 3 ? s.substring(0, 3) : s;
  }

  static String padCampania(String camp) {
    var d = camp.replaceAll(RegExp(r'\D'), '');
    if (d.length >= 3) return d.substring(d.length - 3);
    while (d.length < 3) {
      d = '0$d';
    }
    return d.substring(d.length - 3);
  }

  static String codigoCenco6(String granja, String campania) {
    return normGranja(granja) + padCampania(campania);
  }

  static String padCorrelativo(String camp) {
    var d = padCampania(camp);
    while (d.length < 4) {
      d = '0$d';
    }
    return d.substring(d.length - 4);
  }

  /// Formato correlativo: 621-0001
  static String formatCodigoCorrelativo(String granja, String campania) {
    final g = normGranja(granja);
    if (g.isEmpty) return '';
    return '$g-${padCorrelativo(campania)}';
  }

  /// Normaliza 621-0001 o 621001 a 621001.
  static String normalizarCodigoCenco(String codigo) {
    final c = codigo.trim();
    if (c.isEmpty) return '';
    final m = RegExp(r'^(\d{3})-(\d{3,4})$').firstMatch(c);
    if (m != null) {
      final camp3 = m.group(2)!.padLeft(3, '0');
      return '${m.group(1)}${camp3.substring(camp3.length - 3)}';
    }
    final digits = c.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 6) {
      return digits.substring(0, 3) + digits.substring(digits.length - 3);
    }
    return c;
  }

  static bool codigoEquivalente(String a, String b) {
    return normalizarCodigoCenco(a) == normalizarCodigoCenco(b);
  }

  /// Últimos 3 dígitos del código CENCO (respaldo si no hay campaña en proyección).
  static String campaniaFromCodigo(String codigo) {
    final n = normalizarCodigoCenco(codigo);
    if (n.length >= 6) return n.substring(n.length - 3);
    final c = codigo.trim();
    if (c.length >= 3) return c.substring(c.length - 3);
    return padCampania(c);
  }

  /// Quita sufijos tipo `C=193` del nombre de granja.
  static String cleanNombreGranja(String nombre) {
    var n = nombre.trim();
    if (n.isEmpty) return '';
    n = n.replaceAll(RegExp(r'\s*C\s*=\s*\d+\s*', caseSensitive: false), ' ');
    return n.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }

  /// Etiqueta visible: `621 GJA. SANTA TERESA` (código 3 dígitos + nombre).
  static String formatGranjaLabel(String granjaCodigo, String nombre) {
    final g3 = normGranja(granjaCodigo);
    var nom = cleanNombreGranja(nombre);
    if (g3.isNotEmpty && nom.startsWith(g3)) {
      nom = nom.substring(g3.length).replaceFirst(RegExp(r'^[\s\-–—]+'), '').trim();
    }
    if (g3.isEmpty) return nom;
    if (nom.isEmpty) return g3;
    return '$g3 $nom';
  }

  /// Lista del diálogo: granja + campaña al final para distinguir filas.
  static String formatListaOpcion(Map<String, String> it) {
    final base = formatGranjaLabel(
      it['granja3'] ?? it['granja'] ?? '',
      it['granjaNombre'] ?? '',
    );
    final camp = padCampania(it['campania'] ?? '');
    if (camp.isEmpty) return base;
    return '$base  ·  $camp';
  }

  /// @deprecated Prefer [formatGranjaLabel].
  static String formatEtiqueta({
    required String codigo6,
    required String nombre,
    required String campania,
  }) {
    final g3 = normGranja(
      normalizarCodigoCenco(codigo6).length >= 3
          ? normalizarCodigoCenco(codigo6).substring(0, 3)
          : codigo6,
    );
    return formatGranjaLabel(g3, nombre);
  }

  static String formatEtiquetaFromSeleccion(Map<String, String> sel) {
    return formatGranjaLabel(
      sel['granja3'] ?? sel['granja'] ?? '',
      sel['granjaNombre'] ?? '',
    );
  }

  static List<Map<String, String>> _parseCampanias(dynamic raw) {
    if (raw is! List) return [];
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is Map) {
        final camp = padCampania((item['campania'] ?? '').toString());
        if (camp.isEmpty) continue;
        var codCorrel = (item['codigo'] ?? '').toString().trim();
        if (normalizarCodigoCenco(codCorrel).length < 6) {
          codCorrel = formatCodigoCorrelativo(
            normGranja((item['granja'] ?? codCorrel).toString()),
            camp,
          );
        }
        out.add({'campania': camp, 'codigo': codCorrel});
      } else {
        final camp = padCampania(item.toString());
        if (camp.isNotEmpty) {
          out.add({'campania': camp, 'codigo': ''});
        }
      }
    }
    return out;
  }

  /// Opciones combinadas granja+campaña desde proyección (granjas + campanias_por_granja).
  /// Si la proyección viene vacía, usa [cencosGalpones] como respaldo (catálogo descargado).
  static List<Map<String, String>> buildOpciones(
    Map<String, dynamic>? proyeccion, {
    Map<String, dynamic>? cencosGalpones,
  }) {
    final granjas = (proyeccion?['granjas'] as List?) ?? [];
    final campMap = Map<String, dynamic>.from(
      (proyeccion?['campanias_por_granja'] as Map?) ?? {},
    );
    final cencos = (proyeccion?['cencos'] as List?) ?? [];

    final nombres = <String, String>{};
    for (final g in granjas) {
      if (g is! Map) continue;
      final g3 = normGranja((g['granja'] ?? '').toString());
      if (g3.isEmpty) continue;
      final nom = cleanNombreGranja(
        (g['nombre'] ?? g['nombre_granja'] ?? '').toString(),
      );
      if (nom.isNotEmpty) nombres[g3] = nom;
    }

    for (final c in cencos) {
      if (c is! Map) continue;
      final cod = (c['codigo'] ?? '').toString().trim();
      if (cod.length < 3) continue;
      final g3 = normGranja(cod);
      final nom = cleanNombreGranja(
        (c['nombre'] ?? c['nombre_granja'] ?? '').toString(),
      );
      if (nom.isNotEmpty && !nombres.containsKey(g3)) {
        nombres[g3] = nom;
      }
    }

    final opciones = <Map<String, String>>[];
    final seen = <String>{};

    void addOpcion(String g3, String camp, String codHint) {
      final campP = padCampania(camp);
      if (g3.isEmpty || campP.isEmpty) return;
      var codCorrel = codHint.trim();
      if (normalizarCodigoCenco(codCorrel).length < 6) {
        codCorrel = formatCodigoCorrelativo(g3, campP);
      }
      if (!seen.add(normalizarCodigoCenco(codCorrel))) return;
      opciones.add({
        'codigo': codCorrel,
        'granja': codCorrel,
        'granja3': g3,
        'campania': campP,
        'granjaNombre': nombres[g3] ?? '',
      });
    }

    campMap.forEach((gk, raw) {
      final g3 = normGranja(gk.toString());
      for (final row in _parseCampanias(raw)) {
        addOpcion(g3, row['campania']!, row['codigo'] ?? '');
      }
    });

    if (opciones.isEmpty) {
      for (final g in granjas) {
        if (g is! Map) continue;
        final g3 = normGranja((g['granja'] ?? '').toString());
        if (g3.isEmpty) continue;
        final camps = _parseCampanias(
          campMap[g3] ?? campMap[g['granja']] ?? campMap[g3.padLeft(3, '0')],
        );
        if (camps.isEmpty) continue;
        for (final row in camps) {
          addOpcion(g3, row['campania']!, row['codigo'] ?? '');
        }
      }
    }

    if (opciones.isEmpty) {
      for (final c in cencos) {
        if (c is! Map) continue;
        final cod6 = (c['codigo'] ?? '').toString().trim();
        if (cod6.length < 6) continue;
        final g3 = normGranja(cod6);
        final camp = padCampania(cod6.substring(cod6.length - 3));
        addOpcion(g3, camp, cod6);
      }
    }

    if (opciones.isEmpty && cencosGalpones != null) {
      final cg = (cencosGalpones['cencos'] as List?) ?? [];
      for (final c in cg) {
        if (c is! Map) continue;
        final cod6 = (c['codigo'] ?? '').toString().trim();
        if (cod6.length < 6) continue;
        final g3 = normGranja(cod6);
        final nom = cleanNombreGranja(
          (c['nombre'] ?? c['nombre_granja'] ?? '').toString(),
        );
        if (nom.isNotEmpty && !nombres.containsKey(g3)) {
          nombres[g3] = nom;
        }
        final camp = padCampania(cod6.substring(cod6.length - 3));
        addOpcion(g3, camp, cod6);
      }
    }

    opciones.sort((a, b) {
      return formatListaOpcion(a).compareTo(formatListaOpcion(b));
    });

    return opciones;
  }

  static Future<Map<String, String>?> show(
    BuildContext context, {
    required Map<String, dynamic>? proyeccion,
    Map<String, dynamic>? cencosGalpones,
  }) async {
    final opciones = buildOpciones(
      proyeccion,
      cencosGalpones: cencosGalpones,
    );
    if (opciones.isEmpty) {
      await showAppDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin granjas'),
          content: const Text(
            'No hay granjas/campañas para la fecha seleccionada. '
            'Descargue datos desde el menú.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      return null;
    }

    final sel = await _showSearchList<Map<String, String>>(
      context,
      title: 'Seleccionar Granja',
      hint: 'Buscar por código o nombre',
      items: opciones,
      labelOf: formatListaOpcion,
      filterOf: (it, q) {
        final label = formatListaOpcion(it).toLowerCase();
        return label.contains(q) ||
            it['codigo']!.toLowerCase().contains(q) ||
            it['granja3']!.contains(q) ||
            (it['campania'] ?? '').contains(q);
      },
    );

    return sel;
  }

  static Future<T?> _showSearchList<T>(
    BuildContext context, {
    required String title,
    required String hint,
    required List<T> items,
    required String Function(T) labelOf,
    required bool Function(T, String) filterOf,
  }) {
    String filter = '';
    return showAppDialog<T>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          final q = filter.toLowerCase();
          final filtered = items
              .where((it) => filter.isEmpty || filterOf(it, q))
              .toList();

          return Dialog(
            backgroundColor: context.dialogSurface,
            insetPadding: context.dialogInsetPadding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SizedBox(
              width: MediaQuery.of(context).size.width - 24,
              height: MediaQuery.of(context).size.height * 0.58,
              child: Column(
                children: [
                  appDialogHeader(context, title: title),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setState(() => filter = v),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Sin resultados',
                              style: TextStyle(color: context.textThemeMuted),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final it = filtered[i];
                              return ListTile(
                                title: Text(
                                  labelOf(it),
                                  style: TextStyle(
                                    color: context.isAppDark
                                        ? AppColors.textSelectedValue
                                        : AppColors.textSelectedValue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: () => Navigator.pop(context, it),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
