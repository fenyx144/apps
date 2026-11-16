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
  /// Las tablas de cerco y fómites no lo usan a propósito: ahí las columnas
  /// tienen un ancho de contenido y la tabla hace scroll horizontal.
  final double flex;
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
    this.trailing = const [],
    this.rowHeight = 44,
  });

  final List<BioColumn> columns;

  /// Cantidad de filas de datos (sin encabezado ni [trailing]).
  final int rowCount;

  /// Devuelve las celdas (una por columna) de la fila [index].
  final List<Widget> Function(BuildContext context, int index) rowBuilder;

  /// Título sobre la tabla (p. ej. «Verificación del tablero»).
  final String? caption;

  /// Filas adicionales al final de la tabla (p. ej. observación general).
  final List<List<Widget>> trailing;

  final double rowHeight;

  double get _totalWidth =>
      columns.fold<double>(0, (acc, c) => acc + c.width);

  /// Anchos efectivos de cada columna para un ancho de tabla [width].
  /// Si sobra espacio, las columnas con [BioColumn.flex] se lo reparten; si no
  /// hay columnas flexibles (cerco y fómites) devuelve los anchos declarados y
  /// la tabla se desplaza en horizontal.
  List<double> _anchosEfectivos(double width) {
    final sobrante = width - _totalWidth;
    final totalFlex = columns.fold<double>(0, (acc, c) => acc + c.flex);
    if (sobrante <= 0 || totalFlex <= 0) {
      return [for (final c in columns) c.width];
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
      decoration: BoxDecoration(
        color: context.tableCaption,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
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
                  fontSize: 12.5,
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
    // El encabezado azul con texto blanco se conserva en los dos modos: es lo
    // que identifica la tabla. Lo que cambia con el tema es el cuerpo.
    final bg = header
        ? AppColors.tableHeader
        : striped
            ? context.tableCellAlt
            : context.tableCell;

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
        border: Border.all(color: context.tableCellBorder, width: 0.8),
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
    this.underline = false,
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

  /// Dibuja una línea bajo el campo. En una celda de tabla el campo sin borde
  /// no se distingue de un texto, así que donde hay que escribir (la
  /// observación del cerco) la línea avisa que ahí se puede escribir.
  final bool underline;

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
      ],
      style: TextStyle(
        fontSize: 13.5,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: context.textThemePrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: context.textThemeMuted,
        ),
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: underline ? _underline(context) : InputBorder.none,
        focusedBorder: underline
            ? _underline(context, color: AppColors.primaryDark)
            : InputBorder.none,
        // La línea también se dibuja con el campo apagado: el aviso de «acá se
        // escribe» tiene que estar a la vista **antes** de tocar nada (en el
        // cerco, la celda de Obs apagada quedaba como un texto suelto).
        disabledBorder: underline ? _underline(context) : InputBorder.none,
        contentPadding: EdgeInsets.zero,
        // Sin contador: en una celda de tabla el «0/8» solo apretaba el alto.
        counterText: '',
      ),
    );
  }

  /// Línea bajo el campo cuando [underline] está activo.
  /// El color tenue del tema dejaba una raya de 1 px tan clara sobre la celda
  /// que no se veía hasta tocar el campo (y ahí el azul del foco la delataba).
  /// El azul de la marca, apenas rebajado, se lee sobre la celda en los dos
  /// modos sin parecer un campo con borde.
  InputBorder _underline(BuildContext context, {Color? color}) =>
      UnderlineInputBorder(
        borderSide: BorderSide(
          color: color ?? AppColors.primary.withValues(alpha: 0.65),
          width: 1.2,
        ),
      );
}

/// Texto no editable centrado verticalmente para celdas de tabla.
class BioText extends StatelessWidget {
  const BioText(
    this.text, {
    super.key,
    this.align = TextAlign.center,
    this.color,
    this.bold = false,
    this.fontSize = 13.5,
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
        color: color ?? context.textThemePrimary,
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
          style: TextStyle(fontSize: 12.5, color: context.textThemeMuted),
        ),
        icon: const Icon(
          Icons.expand_more,
          size: 16,
          color: AppColors.iconAccent,
        ),
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: context.textThemePrimary,
        ),
        items: [
          for (final it in items)
            DropdownMenuItem<T>(
              value: it,
              child: Text(
                labelOf(it),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: context.textThemePrimary,
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
/// El color sigue el criterio del reporte web: rojo cuando la respuesta es
/// «SI» (hay falla / el animal está dentro del cerco) y verde cuando es «NO».
/// [onLabel] y [offLabel] dicen con qué se contesta la fila; son nulos para
/// quedarse con «SI» y «NO», que es lo que pregunta la falla.
class BioSwitchFallo extends StatelessWidget {
  const BioSwitchFallo({
    super.key,
    required this.value,
    required this.onChanged,
    String? onLabel,
    String? offLabel,
    this.showLabel = true,
  })  : onLabel = onLabel ?? 'SI',
        offLabel = offLabel ?? 'NO';

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
              fontSize: 11.5,
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
/// Es el switch de los tres bloques del cerco: encendido = verde (el componente
/// está como debe) y apagado = rojo (no lo está). Es el inverso de
/// [BioSwitchFallo], que pregunta por la falla.
/// [onLabel] y [offLabel] dicen con qué se contesta la fila en el formato
/// físico: «CT»/«FALLA» en casi todas, «No»/«SI» en las alertas del tablero.
/// Sin indicarlos quedan «Sí» y «No».
class BioSwitchCumple extends StatelessWidget {
  const BioSwitchCumple({
    super.key,
    required this.value,
    required this.onChanged,
    String? onLabel,
    String? offLabel,
    this.showLabel = true,
  })  : onLabel = onLabel ?? 'Sí',
        offLabel = offLabel ?? 'No';

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
              fontSize: 11.5,
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
/// Se usa en las preguntas que piden observación (cerco eléctrico): al activar
/// el switch se habilita la observación en la misma celda. Sin falla el campo
/// queda deshabilitado, igual que en la app antigua.
/// Con [obsSiempreActiva] el campo se escribe siempre (voltaje y nivel de
/// batería, que se registran como valor medido esté o no la falla).
/// [value] guarda siempre la falla (true = no correcto / falló), que es el dato
/// que viaja al backend. Con [verdeAlEncender] el interruptor se muestra como
/// el de «está bien»: verde al estar correcto, rojo al no estarlo.
/// [onLabel] y [offLabel] se pasan al interruptor de adentro y son nulos cuando
/// la fila no tiene un par propio.
/// Con [apilado] la observación va **debajo** del interruptor en vez de al
/// lado. Es como se usa en el cerco: la celda queda angosta y en una fila el
/// campo al lado le robaba ancho al interruptor y lo corría de la columna.
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
    this.onLabel,
    this.offLabel,
    this.apilado = false,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final bool obsSiempreActiva;
  final bool verdeAlEncender;
  final String? onLabel;
  final String? offLabel;

  /// Con `true` la observación va debajo del interruptor.
  final bool apilado;

  @override
  Widget build(BuildContext context) {
    final activo = obsSiempreActiva || value;
    final switchWidget = verdeAlEncender
        ? BioSwitchCumple(
            value: !value,
            onChanged: (v) => onChanged(!v),
            onLabel: onLabel,
            offLabel: offLabel,
          )
        : BioSwitchFallo(
            value: value,
            onChanged: onChanged,
            onLabel: onLabel,
            offLabel: offLabel,
          );
    final campo = BioTextField(
      controller: controller,
      enabled: activo,
      hint: activo ? hint : '—',
      maxLength: maxLength,
      // En la celda sin bordes, un campo vacío se lee como una raya o como
      // nada. La línea de abajo avisa que ahí se escribe.
      underline: true,
    );

    if (apilado) {
      // `stretch` para que el campo use todo el ancho de la celda; el
      // interruptor se alinea a la izquierda para caer en la misma vertical que
      // el de las filas sin observación.
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: switchWidget),
          const SizedBox(height: 2),
          campo,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        switchWidget,
        const SizedBox(width: 4),
        Expanded(child: campo),
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
        icon: Icon(icon, size: 17),
        label: Text(label, maxLines: 1, softWrap: false),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryDark,
          // Relleno y texto cortos: los dos botones de «agregar fila» van en la
          // misma fila del formulario y con el relleno por defecto el segundo
          // quedaba fuera de la pantalla en un teléfono de 360.
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
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
