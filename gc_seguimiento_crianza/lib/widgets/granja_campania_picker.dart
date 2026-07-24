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

  /// Ej: `621-0001 - Granja Sur C=001`
  static String formatEtiqueta({
    required String codigo6,
    required String nombre,
    required String campania,
  }) {
    final cod = codigo6.trim();
    final camp = padCampania(campania);
    final nom = nombre.trim();
    if (normalizarCodigoCenco(cod).length < 6) {
      return nom.isNotEmpty ? nom : camp;
    }
    final displayCod = cod.contains('-')
        ? cod
        : formatCodigoCorrelativo(cod.substring(0, 3), camp);
    if (nom.isNotEmpty) return '$displayCod - $nom C=$camp';
    return '$displayCod C=$camp';
  }

  static String formatEtiquetaFromSeleccion(Map<String, String> sel) {
    final cod = sel['granja'] ?? '';
    final camp = sel['campania'] ?? '';
    final nom = sel['granjaNombre'] ?? '';
    final codDisplay = normalizarCodigoCenco(cod).length >= 6
        ? (cod.contains('-') ? cod : formatCodigoCorrelativo(cod, camp))
        : formatCodigoCorrelativo(cod, camp);
    return formatEtiqueta(codigo6: codDisplay, nombre: nom, campania: camp);
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
    if (proyeccion == null) return [];

    final granjas = (proyeccion['granjas'] as List?) ?? [];
    final campMap = Map<String, dynamic>.from(
      (proyeccion['campanias_por_granja'] as Map?) ?? {},
    );
    final cencos = (proyeccion['cencos'] as List?) ?? [];

    final nombres = <String, String>{};
    for (final g in granjas) {
      if (g is! Map) continue;
      final g3 = normGranja((g['granja'] ?? '').toString());
      if (g3.isEmpty) continue;
      final nom = (g['nombre'] ?? g['nombre_granja'] ?? '').toString().trim();
      if (nom.isNotEmpty) nombres[g3] = nom;
    }

    for (final c in cencos) {
      if (c is! Map) continue;
      final cod = (c['codigo'] ?? '').toString().trim();
      if (cod.length < 3) continue;
      final g3 = normGranja(cod);
      final nom = (c['nombre'] ?? c['nombre_granja'] ?? '').toString().trim();
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
        final nom = (c['nombre'] ?? c['nombre_granja'] ?? '').toString().trim();
        if (nom.isNotEmpty && !nombres.containsKey(g3)) {
          nombres[g3] = nom;
        }
        final camp = padCampania(cod6.substring(cod6.length - 3));
        addOpcion(g3, camp, cod6);
      }
    }

    opciones.sort((a, b) {
      final la = formatEtiqueta(
        codigo6: a['codigo']!,
        nombre: a['granjaNombre']!,
        campania: a['campania']!,
      );
      final lb = formatEtiqueta(
        codigo6: b['codigo']!,
        nombre: b['granjaNombre']!,
        campania: b['campania']!,
      );
      return la.compareTo(lb);
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
            'Descargue datos desde el menú o elija otra fecha.',
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
      title: 'Granja y campaña',
      hint: 'Buscar por código, nombre o campaña...',
      items: opciones,
      labelOf: (it) => formatEtiqueta(
        codigo6: it['codigo']!,
        nombre: it['granjaNombre']!,
        campania: it['campania']!,
      ),
      filterOf: (it, q) {
        final label = formatEtiqueta(
          codigo6: it['codigo']!,
          nombre: it['granjaNombre']!,
          campania: it['campania']!,
        ).toLowerCase();
        return label.contains(q) ||
            it['codigo']!.contains(q) ||
            it['granja3']!.contains(q);
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
