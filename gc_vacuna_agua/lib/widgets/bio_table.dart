import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';

/// Columna de una [BioTable].
class BioColumn {
  const BioColumn(
    this.label, {
    required this.width,
    this.align = TextAlign.center,
    this.flex = 0,
  });

  final String label;

  /// Ancho de la columna. Si [flex] es mayor que 0 pasa a ser el **mínimo**:
  /// la columna crece con el espacio sobrante de la tabla.
  final double width;

  final TextAlign align;

  /// Peso con el que la columna se reparte el ancho sobrante cuando la tabla
  /// no llega al borde. Con 0 (por defecto) conserva su [width].
  ///
  /// Las tablas de cerco y fómites no lo usan a propósito: ahí las columnas
  /// tienen un ancho de contenido y la tabla hace scroll horizontal.
  final double flex;
}

/// Grupo de encabezado de una [BioTable]: titula un tramo continuo de columnas
/// (p. ej. «Pollos evaluados» sobre las columnas Macho y hembra).
///
/// Los índices se cuentan sobre `columns` y son inclusivos. Los grupos de una
/// misma tabla no deben solaparse: cada columna pertenece a lo sumo a uno, y la
/// fila de grupos dibuja una celda vacía sobre las columnas que no cubre.
class BioColGroup {
  const BioColGroup(this.label, {required this.desde, required this.hasta})
      : assert(hasta >= desde, 'El grupo no puede terminar antes de empezar');

  final String label;

  /// Índice de la primera columna que cubre (inclusive).
  final int desde;

  /// Índice de la última columna que cubre (inclusive).
  final int hasta;
}

/// Tabla con el estilo de la app Android antigua: encabezado azul con texto
/// blanco en mayúsculas, celdas con borde, filas alternadas y scroll
/// horizontal cuando el contenido excede el ancho de pantalla.
class BioTable extends StatelessWidget {
  const BioTable({
    super.key,
    required this.columns,
    required this.rowCount,
    required this.rowBuilder,
    this.caption,
    this.groups = const [],
    this.trailing = const [],
    this.rowHeight = 44,
    this.expandir = false,
  });

  final List<BioColumn> columns;

  /// Cantidad de filas de datos (sin encabezado ni [trailing]).
  final int rowCount;

  /// Devuelve las celdas (una por columna) de la fila [index].
  final List<Widget> Function(BuildContext context, int index) rowBuilder;

  /// Título sobre la tabla (p. ej. «Verificación del tablero»).
  final String? caption;

  /// Fila de títulos que agrupa columnas contiguas, encima del encabezado
  /// normal. Vacía (por defecto) la tabla lleva un solo nivel de encabezado.
  final List<BioColGroup> groups;

  /// Filas adicionales al final de la tabla (p. ej. observación general).
  final List<List<Widget>> trailing;

  final double rowHeight;

  /// Reparte entre las columnas el ancho que sobra cuando la tabla no llega al
  /// borde de la pantalla, en proporción al ancho declarado de cada una.
  ///
  /// Apagado (por defecto) la tabla conserva los anchos declarados y deja el
  /// hueco a la derecha: es lo que quieren las tablas que hacen scroll
  /// horizontal, donde el ancho de columna es el del contenido.
  final bool expandir;

  double get _totalWidth =>
      columns.fold<double>(0, (acc, c) => acc + c.width);

  /// Anchos efectivos de cada columna para un ancho de tabla [width].
  ///
  /// Si sobra espacio, las columnas con [BioColumn.flex] se lo reparten; si no
  /// hay columnas flexibles devuelve los anchos declarados y la tabla se
  /// desplaza en horizontal, salvo que [expandir] esté encendido, en cuyo caso
  /// el sobrante se reparte entre todas en proporción a su ancho declarado.
  List<double> _anchosEfectivos(double width) {
    final sobrante = width - _totalWidth;
    final totalFlex = columns.fold<double>(0, (acc, c) => acc + c.flex);
    if (sobrante <= 0) {
      return [for (final c in columns) c.width];
    }
    if (totalFlex <= 0) {
      if (!expandir) {
        return [for (final c in columns) c.width];
      }
      // Proporcional al ancho declarado: las columnas anchas (descripciones,
      // observaciones) se llevan la mayor parte del sobrante y las angostas
      // (contadores, horas) crecen apenas, así la tabla llega al borde sin que
      // las columnas de números queden desproporcionadas.
      return [
        for (final c in columns) c.width + sobrante * (c.width / _totalWidth),
      ];
    }
    return [
      for (final c in columns)
        c.flex > 0 ? c.width + sobrante * (c.flex / totalFlex) : c.width,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _totalWidth;
        final width = _totalWidth > available ? _totalWidth : available;
        final fitsWithoutScroll = _totalWidth <= available;
        final widths = _anchosEfectivos(width);

        final table = SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // La fila de grupos va dentro del mismo bloque que el resto para
              // que se desplace junto con la tabla cuando no entra en pantalla.
              if (groups.isNotEmpty)
                _GroupHeaderRow(
                  groups: groups,
                  widths: widths,
                  columnCount: columns.length,
                ),
              _HeaderRow(columns: columns, widths: widths),
              for (var i = 0; i < rowCount; i++)
                _DataRow(
                  columns: columns,
                  widths: widths,
                  cells: rowBuilder(context, i),
                  alternate: i.isOdd,
                  height: rowHeight,
                ),
              for (var i = 0; i < trailing.length; i++)
                _DataRow(
                  columns: columns,
                  widths: widths,
                  cells: trailing[i],
                  alternate: (rowCount + i).isOdd,
                  height: rowHeight,
                ),
            ],
          ),
        );

        final content = caption == null && fitsWithoutScroll
            ? table
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (caption != null) _CaptionRow(text: caption!),
                  if (fitsWithoutScroll)
                    table
                  else
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: table,
                    ),
                ],
              );

        return content;
      },
    );
  }
}

class _CaptionRow extends StatelessWidget {
  const _CaptionRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.tableAccent,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Fila de títulos que agrupa columnas contiguas, dibujada encima del
/// encabezado normal.
///
/// Las columnas que no caen en ningún grupo llevan una celda vacía, para que
/// los anchos sigan coincidiendo con las filas de abajo.
class _GroupHeaderRow extends StatelessWidget {
  const _GroupHeaderRow({
    required this.groups,
    required this.widths,
    required this.columnCount,
  });

  final List<BioColGroup> groups;
  final List<double> widths;
  final int columnCount;

  @override
  Widget build(BuildContext context) {
    final celdas = <Widget>[];
    var i = 0;
    while (i < columnCount) {
      final grupo = _grupoQueEmpiezaEn(i);
      if (grupo == null) {
        celdas.add(
          BioTableCell(
            width: widths[i],
            header: true,
            child: const SizedBox.shrink(),
          ),
        );
        i++;
        continue;
      }

      var ancho = 0.0;
      for (var j = grupo.desde; j <= grupo.hasta && j < columnCount; j++) {
        ancho += widths[j];
      }
      celdas.add(
        BioTableCell(
          width: ancho,
          header: true,
          child: Text(
            grupo.label.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.tableHeaderText,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
        ),
      );
      i = grupo.hasta + 1;
    }

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: celdas),
    );
  }

  /// Grupo cuyo tramo arranca en [indice], o `null` si ahí no empieza ninguno.
  BioColGroup? _grupoQueEmpiezaEn(int indice) {
    for (final g in groups) {
      if (g.desde == indice && g.hasta < columnCount) return g;
    }
    return null;
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns, required this.widths});

  final List<BioColumn> columns;
  final List<double> widths;

  @override
  Widget build(BuildContext context) {
    // IntrinsicHeight es obligatorio: la tabla suele vivir dentro de un
    // SingleChildScrollView (altura sin acotar) y `stretch` necesita una
    // altura finita o el layout falla con "BoxConstraints forces an
    // infinite height".
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columns.length; i++)
            BioTableCell(
              width: widths[i],
              header: true,
              align: columns[i].align,
              child: Text(
                columns[i].label.toUpperCase(),
                textAlign: columns[i].align,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.tableHeaderText,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.columns,
    required this.widths,
    required this.cells,
    required this.alternate,
    required this.height,
  });

  final List<BioColumn> columns;
  final List<double> widths;
  final List<Widget> cells;
  final bool alternate;
  final double height;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < columns.length; i++)
            BioTableCell(
              width: widths[i],
              align: columns[i].align,
              striped: alternate,
              minHeight: height,
              child: i < cells.length ? cells[i] : const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}

/// Celda con borde. Puede usarse suelta o dentro de [BioTable].
class BioTableCell extends StatelessWidget {
  const BioTableCell({
    super.key,
    required this.child,
    this.width,
    this.header = false,
    this.striped = false,
    this.align = TextAlign.center,
    this.minHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  });

  final Widget child;
  final double? width;
  final bool header;
  final bool striped;
  final TextAlign align;
  final double? minHeight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final bg = header
        ? AppColors.tableHeader
        : striped
            ? AppColors.tableRowAlt
            : Colors.white;

    return Container(
      width: width,
      constraints: BoxConstraints(minHeight: minHeight ?? 0),
      padding: padding,
      alignment: switch (align) {
        TextAlign.left => Alignment.centerLeft,
        TextAlign.right => Alignment.centerRight,
        _ => Alignment.center,
      },
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: AppColors.tableBorder, width: 0.8),
      ),
      child: child,
    );
  }
}

/// Campo de texto compacto para celdas de tabla.
class BioTextField extends StatelessWidget {
  const BioTextField({
    super.key,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.textAlign = TextAlign.left,
    this.textCapitalization = TextCapitalization.sentences,
    this.enabled = true,
    this.maxLength,
    this.onChanged,
    this.bold = false,
    this.soloDigitos = false,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final TextAlign textAlign;

  /// Cómo capitaliza el teclado. Por defecto como una frase; para nombres
  /// completos conviene [TextCapitalization.words].
  final TextCapitalization textCapitalization;

  final bool enabled;
  final int? maxLength;
  final ValueChanged<String>? onChanged;
  final bool bold;

  /// Restringe la entrada a dígitos (p. ej. DNI).
  final bool soloDigitos;

  /// Formateadores extra (p. ej. limitar a 2 decimales).
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      textAlign: textAlign,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      maxLines: 1,
      inputFormatters: [
        if (soloDigitos) FilteringTextInputFormatter.digitsOnly,
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
        ...?inputFormatters,
      ],
      style: TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          color: AppColors.textMuted,
        ),
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        // Sin contador: en una celda de tabla el «0/8» solo apretaba el alto.
        counterText: '',
      ),
    );
  }
}

/// Texto no editable centrado verticalmente para celdas de tabla.
class BioText extends StatelessWidget {
  const BioText(
    this.text, {
    super.key,
    this.align = TextAlign.center,
    this.color,
    this.bold = false,
    this.fontSize = 12,
  });

  final String text;
  final TextAlign align;
  final Color? color;
  final bool bold;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: align,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
        color: color ?? AppColors.textPrimary,
      ),
    );
  }
}

/// Selector compacto para celdas de tabla.
class BioDropdownCell<T> extends StatelessWidget {
  const BioDropdownCell({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.hint = '—',
    this.enabled = true,
  });

  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effective = items.contains(value) ? value : null;
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: effective,
        isExpanded: true,
        isDense: true,
        hint: Text(
          hint,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        icon: const Icon(
          Icons.expand_more,
          size: 16,
          color: AppColors.iconAccent,
        ),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
        items: [
          for (final it in items)
            DropdownMenuItem<T>(
              value: it,
              child: Text(
                labelOf(it),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
        ],
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

/// Medidas fijas del interruptor. Al no depender del ancho del contenido,
/// todos los interruptores de una tabla caen en la misma línea vertical,
/// tengan o no un campo de observación al lado.
const double _kSwitchAncho = 46;
const double _kSwitchAlto = 26;

/// Interruptor con medidas fijas. Es la pieza que comparten [BioSwitchFallo],
/// [BioSwitchCumple] y [BioSwitchObs] para quedar alineados entre sí.
class _SwitchSlot extends StatelessWidget {
  const _SwitchSlot({
    required this.value,
    required this.onChanged,
    required this.colorEncendido,
    required this.colorApagado,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color colorEncendido;
  final Color colorApagado;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSwitchAncho,
      height: _kSwitchAlto,
      child: FittedBox(
        fit: BoxFit.contain,
        child: Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeTrackColor: colorEncendido,
          activeThumbColor: Colors.white,
          inactiveTrackColor: colorApagado,
          inactiveThumbColor: Colors.white,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}

/// Interruptor NO/SI compacto usado en las columnas «¿Falló?» y «¿D. del cerco?».
///
/// El color sigue el criterio del reporte web: rojo cuando la respuesta es
/// «SI» (hay falla / el animal está dentro del cerco) y verde cuando es «NO».
class BioSwitchFallo extends StatelessWidget {
  const BioSwitchFallo({
    super.key,
    required this.value,
    required this.onChanged,
    this.onLabel = 'SI',
    this.offLabel = 'NO',
    this.showLabel = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String onLabel;
  final String offLabel;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SwitchSlot(
          value: value,
          onChanged: onChanged,
          colorEncendido: AppColors.errorDark,
          colorApagado: AppColors.success,
        ),
        if (showLabel) ...[
          const SizedBox(width: 2),
          Text(
            value ? onLabel : offLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: value ? AppColors.errorDark : AppColors.success,
            ),
          ),
        ],
      ],
    );
  }
}

/// Interruptor NO/SI donde el estado encendido es el BUENO.
///
/// Es el switch de los tres bloques del cerco, cuya pregunta es «¿Correcto?»:
/// encendido = verde (el componente está correcto) y apagado = rojo (no lo
/// está). Es el inverso de [BioSwitchFallo], que pregunta por la falla.
class BioSwitchCumple extends StatelessWidget {
  const BioSwitchCumple({
    super.key,
    required this.value,
    required this.onChanged,
    this.onLabel = 'Sí',
    this.offLabel = 'No',
    this.showLabel = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String onLabel;
  final String offLabel;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _SwitchSlot(
          value: value,
          onChanged: onChanged,
          colorEncendido: AppColors.success,
          colorApagado: AppColors.errorDark,
        ),
        if (showLabel) ...[
          const SizedBox(width: 2),
          Text(
            value ? onLabel : offLabel,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: value ? AppColors.success : AppColors.errorDark,
            ),
          ),
        ],
      ],
    );
  }
}

/// Celda combinada: el interruptor y su campo de ingreso, juntos.
///
/// Se usa en las preguntas que piden observación (cerco eléctrico): al activar
/// el switch se habilita la observación en la misma celda. Sin falla el campo
/// queda deshabilitado, igual que en la app antigua.
///
/// Con [obsSiempreActiva] el campo se escribe siempre (voltaje y nivel de
/// batería, que se registran como valor medido esté o no la falla).
///
/// [value] guarda siempre la falla (true = no correcto / falló), que es el dato
/// que viaja al backend. Con [verdeAlEncender] el interruptor se muestra como
/// el de «¿Correcto?»: verde al estar correcto, rojo al no estarlo.
class BioSwitchObs extends StatelessWidget {
  const BioSwitchObs({
    super.key,
    required this.value,
    required this.onChanged,
    required this.controller,
    this.hint = 'Obs',
    this.maxLength = 80,
    this.obsSiempreActiva = false,
    this.verdeAlEncender = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final bool obsSiempreActiva;
  final bool verdeAlEncender;

  @override
  Widget build(BuildContext context) {
    final activo = obsSiempreActiva || value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (verdeAlEncender)
          BioSwitchCumple(
            value: !value,
            onChanged: (v) => onChanged(!v),
          )
        else
          BioSwitchFallo(value: value, onChanged: onChanged),
        const SizedBox(width: 4),
        Expanded(
          child: BioTextField(
            controller: controller,
            enabled: activo,
            hint: activo ? hint : '—',
            maxLength: maxLength,
          ),
        ),
      ],
    );
  }
}

/// Botón «+» sutil para agregar filas (depredador «Otros»).
class BioAddRowButton extends StatelessWidget {
  const BioAddRowButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add_circle_outline,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Encabezado de bloque con ícono, usado sobre las tablas.
class BioSectionTitle extends StatelessWidget {
  const BioSectionTitle({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.primaryDark),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: context.textThemePrimary,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}
