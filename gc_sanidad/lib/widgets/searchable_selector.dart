import 'package:flutter/material.dart';

import '../utils/constants.dart';

class SearchableSelector extends StatefulWidget {
  final String label;
  final String? selectedCodigo;
  final List<Map<String, dynamic>> items;
  final ValueChanged<String?> onSelectedCodigo;
  final String? errorText; 

  const SearchableSelector({
    super.key,
    required this.label,
    required this.selectedCodigo,
    required this.items,
    required this.onSelectedCodigo,
    this.errorText, 
  });

  @override
  State<SearchableSelector> createState() => _SearchableSelectorState();
}

class _SearchableSelectorState extends State<SearchableSelector> {
  Future<Map<String, String>?> _showSelectionDialog({
  required BuildContext context,
  required String title,
  required List<Map<String, dynamic>> options,
}) async {
  String busqueda = '';

  return showDialog<Map<String, String>>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setStateInterno) {
          final opcionesFiltradas = options
              .where((opcion) =>
                  (opcion['nombre'] as String?)?.toLowerCase().contains(busqueda.toLowerCase()) == true)
              .toList();

          return Dialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Container(
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxHeight: 550),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A2B56).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.business,
                          color: Color(0xFF1A2B56),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A2B56),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 22),
                        color: Colors.grey[600],
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        tooltip: 'Cerrar',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey[200]!, width: 1),
                    ),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar ${title.toLowerCase()}...',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 15,
                        ),
                        prefixIcon: Icon(Icons.search, color: Colors.grey[500], size: 22),
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                      ),
                      style: const TextStyle(fontSize: 15),
                      onChanged: (value) {
                        setStateInterno(() {
                          busqueda = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (opcionesFiltradas.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8, left: 4),
                      child: Text(
                        '${opcionesFiltradas.length} resultado${opcionesFiltradas.length != 1 ? 's' : ''}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                  Expanded(
                    child: opcionesFiltradas.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    busqueda.isEmpty ? Icons.search : Icons.search_off,
                                    size: 48,
                                    color: Colors.grey[400],
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  busqueda.isEmpty
                                      ? 'Comience a escribir para buscar'
                                      : 'No se encontraron resultados',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey[700],
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                if (busqueda.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Intente con otros términos de búsqueda',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[200]!, width: 1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListView.separated(
                              itemCount: opcionesFiltradas.length,
                              separatorBuilder: (context, index) => Divider(
                                height: 1,
                                thickness: 1,
                                color: Colors.grey[100],
                                indent: 16,
                                endIndent: 16,
                              ),
                              itemBuilder: (context, index) {
                                final opcion = opcionesFiltradas[index];
                                final isSelected = opcion['codigo'] == widget.selectedCodigo;
                                
                                return InkWell(
                                  onTap: () {
                                    Navigator.of(dialogContext).pop({
                                      'codigo': opcion['codigo'] as String,
                                      'nombre': opcion['nombre'] as String,
                                    });
                                  },
                                  borderRadius: BorderRadius.vertical(
                                    top: index == 0 ? const Radius.circular(12) : Radius.zero,
                                    bottom: index == opcionesFiltradas.length - 1
                                        ? const Radius.circular(12)
                                        : Radius.zero,
                                  ),
                                  child: Container(
                                    color: isSelected
                                        ? const Color(0xFF1A2B56).withOpacity(0.08)
                                        : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    child: Row(
                                      children: [
                                        // Indicador de selección
                                        Container(
                                          width: 24,
                                          height: 24,
                                          margin: const EdgeInsets.only(right: 14),
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFF1A2B56)
                                                : Colors.transparent,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected
                                                  ? const Color(0xFF1A2B56)
                                                  : Colors.grey[400]!,
                                              width: 2,
                                            ),
                                          ),
                                          child: isSelected
                                              ? const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 16,
                                                )
                                              : null,
                                        ),
                                        
                                        // Texto de la opción en MAYÚSCULAS
                                        Expanded(
                                          child: Text(
                                            (opcion['nombre'] as String).toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                              color: isSelected
                                                  ? const Color(0xFF1A2B56)
                                                  : Colors.black87,
                                              letterSpacing: 0.3,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        
                                        // Icono de flecha para indicar selección
                                        if (isSelected)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 8),
                                            child: Icon(
                                              Icons.arrow_forward_ios,
                                              size: 14,
                                              color: Color(0xFF1A2B56),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  String getDisplayValue() {
    if (widget.selectedCodigo == null || widget.selectedCodigo!.isEmpty) {
      return '';
    }
    try {
      final item = widget.items.firstWhere(
        (o) => o['codigo'] == widget.selectedCodigo,
        orElse: () => <String, dynamic>{'nombre': ''},
      );
      return item['nombre'] as String? ?? '';
    } catch (e) {
      return '';
    }
  }

 
  @override
Widget build(BuildContext context) {
  final String displayValue = getDisplayValue(); 
  final bool hasValue = displayValue.isNotEmpty;
  final bool hasError = widget.errorText != null; // 🔥 Detectar si hay error

  return InkWell(
    onTap: () async {
      final selected = await _showSelectionDialog(
        context: context,
        title: widget.label,
        options: widget.items,
      );
      if (selected != null) {
        widget.onSelectedCodigo(selected['codigo']); 
      }
    },
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: TextStyle(color: Colors.grey[700]),
        hintText: hasValue ? null : 'Seleccionar',
        
        // ✅ Borde normal
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.grey, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: hasError ? Colors.red : Colors.grey, // 🔥 Rojo si hay error
            width: hasError ? 1.5 : 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: hasError ? Colors.red : AppColors.primary, // 🔥 Rojo si hay error
            width: 1.8,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.red, width: 1.8),
        ),
        
        // 🔥 Mostrar el texto de error
        errorText: widget.errorText,
        errorStyle: const TextStyle(
          color: Colors.red,
          fontSize: 10,
          height: 1.2,
        ),
        
        suffixIcon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
        contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            hasValue ? displayValue : 'Seleccionar',
            style: TextStyle(
              fontSize: 16,
              color: hasValue ? Colors.black : Colors.grey[500],
              fontStyle: hasValue ? FontStyle.normal : FontStyle.italic,
            ),
          ),
        ),
      ),
    ),
  );
}
}