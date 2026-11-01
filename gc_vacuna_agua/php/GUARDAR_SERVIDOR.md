# Vacuna al Agua — guardado en servidor

## Varios registros el mismo día (granja + campaña)

La app envía un **UUID distinto** en cada captura (`data.id`). El backend **no** debe
usar solo `(fecha, granja, campaña, reporte)` como llave única: eso hace que el
segundo registro devuelva **409** y, si la app reintenta como actualización, **pise**
al anterior.

- **Insertar** siempre por `id` (UUID).
- **409** solo cuando el **mismo UUID** ya existe (reintento / reenvío).
- Persistir `registro.galpones` (vacunación) o `galpones: ["TODOS"]` (decloración).
- Duplicar también `galpones` en la raíz del JSON `data` (la app móvil ya lo envía).

## Galpones en listado web

Usar `vacunaagua_texto_galpones($reporte, $registro)` leyendo el JSON de
`registro` (no la columna suelta si está vacía). Ver `vacunaagua_registro_de_fila()`.

## Detalle con tablas por registro

Ver `vacunaagua_html_detalle_vacunacion()` en `vacunaagua_web_lib.php`: columnas
agrupadas por «Registro 1», «Registro 2», … y galpones bajo cada bloque.

## Estilos del detalle

En la página de detalle, incluir una sola vez:

```php
echo vacunaagua_html_estilos();
// o: <link rel="stylesheet" href=".../vacunaagua_web.css">
```

La **fecha** va en la franja clara `vacunaagua-meta` (dd/mm/yyyy), no como texto
único en un `<th>` oscuro. Los títulos de sección usan `h3.vacunaagua-sec-title`,
no `<caption>` dentro de la tabla.
