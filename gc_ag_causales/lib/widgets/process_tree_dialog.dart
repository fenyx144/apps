import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../utils/dialog_utils.dart';
import '../utils/theme_colors.dart';

class ProcessTreeDialog {
  static Future<Map<String, String>?> show(
    BuildContext context,
    Map<String, dynamic>? arbolData,
  ) async {
    if (arbolData == null || arbolData['arbol'] == null) {
      return null;
    }
    final arbol = arbolData['arbol'] as Map<String, dynamic>;
    return showAppDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => _ProcessTreeDialogWidget(root: arbol),
    );
  }
}

class _TreeRow {
  final Map<String, dynamic> node;
  final int depth;
  final String pathLabel;
  final bool selectable;

  const _TreeRow({
    required this.node,
    required this.depth,
    required this.pathLabel,
    required this.selectable,
  });
}

class _ProcessTreeDialogWidget extends StatefulWidget {
  final Map<String, dynamic> root;

  const _ProcessTreeDialogWidget({required this.root});

  @override
  State<_ProcessTreeDialogWidget> createState() =>
      _ProcessTreeDialogWidgetState();
}

class _ProcessTreeDialogWidgetState extends State<_ProcessTreeDialogWidget> {
  String _filter = '';

  List<Map<String, dynamic>> get _topChildren {
    final children = widget.root['children'];
    if (children is! List) return [];
    return children
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  /// Misma regla que `esHojaNodo` en sip-mapa-proceso-necropsias.js (web).
  bool _hasStructuralChildren(Map<String, dynamic> node) {
    final children = node['children'];
    return children is List && children.isNotEmpty;
  }

  String _tareaKey(Map<String, dynamic> node) =>
      (node['actividadKey'] ?? node['tareaKey'] ?? '').toString().trim();

  String _name(Map<String, dynamic> node) =>
      (node['name'] ?? '').toString().trim();

  /// Profundidad visual desde treePath/pathCodigo del API (0 = hijo directo de la raíz).
  int _depthFromNode(Map<String, dynamic> node, int fallback) {
    final treePath = (node['treePath'] ?? '').toString().trim();
    if (treePath.isNotEmpty) {
      return treePath.split('.').where((p) => p.isNotEmpty).length - 1;
    }
    final pathCodigo = (node['pathCodigo'] ?? '').toString().trim();
    if (pathCodigo.isNotEmpty) {
      return pathCodigo.split('-').where((p) => p.isNotEmpty).length - 1;
    }
    return fallback;
  }

  bool _nodeMatchesFilter(Map<String, dynamic> node) {
    if (_filter.isEmpty) return true;
    final q = _filter.toLowerCase();
    if (_name(node).toLowerCase().contains(q)) return true;
    if (_tareaKey(node).toLowerCase().contains(q)) return true;
    final children = node['children'];
    if (children is List) {
      for (final c in children) {
        if (c is Map && _nodeMatchesFilter(Map<String, dynamic>.from(c))) {
          return true;
        }
      }
    }
    return false;
  }

  void _collectRows(
    Map<String, dynamic> node,
    int walkDepth,
    String pathPrefix,
    List<_TreeRow> out,
  ) {
    if (!_nodeMatchesFilter(node)) return;

    final name = _name(node);
    final hasKids = _hasStructuralChildren(node);
    final tk = _tareaKey(node);
    final pathLabel = name.isEmpty
        ? pathPrefix
        : (pathPrefix.isEmpty ? name : '$pathPrefix › $name');
    final depth = _depthFromNode(node, walkDepth);

    if (!hasKids) {
      if (name.isEmpty && tk.isEmpty) return;
      if (_filter.isNotEmpty &&
          !name.toLowerCase().contains(_filter.toLowerCase()) &&
          !tk.toLowerCase().contains(_filter.toLowerCase())) {
        return;
      }
      out.add(
        _TreeRow(
          node: node,
          depth: depth,
          pathLabel: pathLabel,
          selectable: tk.isNotEmpty,
        ),
      );
      return;
    }

    if (name.isNotEmpty) {
      out.add(
        _TreeRow(
          node: node,
          depth: depth,
          pathLabel: pathLabel,
          selectable: false,
        ),
      );
    }

    final children = node['children'] as List;
    for (final c in children) {
      if (c is! Map) continue;
      final child = Map<String, dynamic>.from(c);
      _collectRows(child, walkDepth + 1, pathLabel, out);
    }
  }

  List<_TreeRow> get _visibleRows {
    final rows = <_TreeRow>[];
    for (final child in _topChildren) {
      _collectRows(child, 0, '', rows);
    }
    return rows;
  }

  double _indentForDepth(int depth) => 12.0 + depth * 16.0;

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;

    return Dialog(
      backgroundColor: context.dialogSurface,
      insetPadding: context.dialogInsetPadding,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
          maxWidth: MediaQuery.of(context).size.width - 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            appDialogHeader(context, title: 'Seleccionar proceso'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'Buscar...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: rows.isEmpty ? 1 : rows.length,
                itemBuilder: (context, index) {
                  if (rows.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'Sin resultados',
                          style: TextStyle(color: context.textThemeMuted),
                        ),
                      ),
                    );
                  }

                  final row = rows[index];
                  final name = _name(row.node);
                  final indent = _indentForDepth(row.depth);

                  if (!row.selectable) {
                    return Padding(
                      padding: EdgeInsets.only(
                        left: indent,
                        right: 12,
                        top: 6,
                        bottom: 2,
                      ),
                      child: Text(
                        name.isEmpty ? 'Proceso' : name,
                        style: TextStyle(
                          fontWeight:
                              row.depth == 0 ? FontWeight.w700 : FontWeight.w600,
                          color: context.textThemePrimary,
                          fontSize: row.depth == 0 ? 15 : 14,
                        ),
                      ),
                    );
                  }

                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(left: indent, right: 12),
                    leading: Icon(
                      Icons.touch_app_outlined,
                      size: 18,
                      color: context.textThemeMuted,
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.isAppDark
                            ? AppColors.textSelectedValue
                            : AppColors.textSelectedValue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: () {
                      final tk = _tareaKey(row.node);
                      if (tk.isEmpty) return;
                      Navigator.pop(context, {
                        'tareaKey': tk,
                        'procesoNombre': row.pathLabel.isNotEmpty
                            ? row.pathLabel
                            : name,
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
