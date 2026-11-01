<?php
declare(strict_types=1);

/**
 * Procesa el guardado (alta o actualización) de un registro de bioseguridad.
 * Invocado por guardar_bioseguridad_movil.php y actualizar_bioseguridad_movil.php.
 */

/**
 * @param array<string, mixed> $data payload JSON del campo "data"
 * @return array{status:int,success:bool,message:string,errorCode:?string,data:?array<string,mixed>}
 */
function bio_procesar_guardado(mysqli $conn, array $data, bool $esActualizacion): array
{
    $reporte = strtolower(trim((string) ($data['reporte'] ?? '')));
    if (!in_array($reporte, BIO_REPORTES_VALIDOS, true)) {
        return bio_resp(400, false, 'Reporte no válido (garita, cerco, fomites, ingreso o salida).', 'INVALID_REPORTE');
    }

    $fecha = bio_norm_fecha((string) ($data['fecha'] ?? ''));
    if ($fecha === '') {
        return bio_resp(400, false, 'La fecha es obligatoria (YYYY-MM-DD).', 'INVALID_FECHA');
    }

    $granja = bio_norm_granja((string) ($data['granja'] ?? ''));
    $campania = bio_norm_campania((string) ($data['campania'] ?? ''));
    if (trim($granja) === '' || $campania === '') {
        return bio_resp(400, false, 'Granja y campaña son obligatorias.', 'MISSING_GRANJA');
    }
    $cencos = bio_cenco($granja, $campania);

    $turno = bio_turno((string) ($data['turno'] ?? ''));
    if ($turno === '') {
        return bio_resp(400, false, 'El turno es obligatorio (Dia o Noche).', 'MISSING_TURNO');
    }

    $tuser = trim((string) ($data['usuario'] ?? ''));
    if ($tuser === '') {
        $tuser = 'MOVIL';
    }

    $registro = is_array($data['registro'] ?? null) ? $data['registro'] : [];
    if ($registro === []) {
        $registro = $data; // compatibilidad: campos planos en la raíz
    }

    // --- Identidad y auditoría ---------------------------------------------
    // La app genera el uuid local de cada registro; si no llega (apps previas
    // al cambio) se genera aquí para que la columna nunca quede vacía.
    $uuid = bio_norm_uuid((string) ($data['id'] ?? ''));
    if ($uuid === '') {
        $uuid = bio_nuevo_uuid();
    }
    $ahoraDatetime = date('Y-m-d H:i:s');
    $fechaHoraRegistro = bio_norm_datetime((string) ($data['fechaHoraRegistro'] ?? ''));
    if ($fechaHoraRegistro === '') {
        $fechaHoraRegistro = $ahoraDatetime;
    }
    $usuarioRegistrador = bio_cut(trim((string) ($data['usuarioRegistrador'] ?? $data['usuario'] ?? '')), 25);
    if ($usuarioRegistrador === '') {
        $usuarioRegistrador = bio_cut($tuser, 25);
    }

    $ctx = [
        'reporte' => $reporte,
        'fecha' => $fecha,
        'cencos' => $cencos,
        'granja' => $granja,
        'campania' => $campania,
        'turno' => $turno,
        'tuser' => $tuser,
        'colaborador' => bio_cut((string) ($data['nombre_usuario'] ?? $tuser), 30),
        'uuid' => $uuid,
        'usuarioRegistrador' => $usuarioRegistrador,
        'fechaHoraRegistro' => $fechaHoraRegistro,
        // Quién inserta en el servidor puede ser otro usuario que el registrador.
        'usuarioTransferencia' => bio_cut($tuser, 25),
        'fechaHoraTransferencia' => $ahoraDatetime,
    ];

    // --- Datos específicos por reporte -------------------------------------
    if ($reporte === 'garita') {
        // El punto inspeccionado forma parte de la llave del registro.
        $instalacion = bio_normalizar_instalacion($conn, (string) ($registro['instalacion'] ?? ''));
        if ($instalacion === '') {
            return bio_resp(400, false, 'La instalación no es válida.', 'INVALID_INSTALACION');
        }
        // El tipo de bioseguridad también: el reporte web se abre por tipo.
        $bioseguridad = bio_normalizar_bioseguridad((string) ($registro['bioseguridad'] ?? ''));
        if ($bioseguridad === '') {
            return bio_resp(400, false, 'El tipo de bioseguridad no es válido.', 'INVALID_BIOSEGURIDAD');
        }
        // Solo la garita tiene filtros numerados; tranquera y pozo séptico no.
        if ($instalacion === 'Garita') {
            $numfiltro = (int) ($registro['numfiltro'] ?? 0);
            if ($numfiltro < 1 || $numfiltro > 3) {
                return bio_resp(400, false, 'El número de filtro debe ser 1, 2 o 3.', 'INVALID_FILTRO');
            }
        } else {
            // numfiltro es NOT NULL y parte de la PK: se guarda un relleno.
            $numfiltro = 1;
        }
        $descripcion = trim((string) ($registro['descripcion'] ?? ''));
        $agentecausal = trim((string) ($registro['agentecausal'] ?? ''));
        if ($descripcion === '' && $agentecausal === '') {
            return bio_resp(400, false, 'Ingrese la descripción o el agente causal.', 'MISSING_CONTENIDO');
        }
        $ctx['instalacion'] = $instalacion;
        $ctx['bioseguridad'] = $bioseguridad;
        $ctx['numfiltro'] = $numfiltro;
        $ctx['anomalia'] = (string) ($registro['anomalia'] ?? '');
        $ctx['hora'] = (string) ($registro['hora'] ?? '');
        $ctx['descripcion'] = $descripcion;
        $ctx['agentecausal'] = $agentecausal;
    } elseif ($reporte === 'cerco') {
        $filas = is_array($registro['filas'] ?? null) ? $registro['filas'] : [];
        $metricas = bio_cerco_metricas();
        $validas = 0;
        foreach ($filas as $fila) {
            $componente = trim((string) ($fila['componente'] ?? ''));
            if ($componente !== '' && isset($metricas[$componente])) {
                $validas++;
            }
        }
        if ($validas === 0) {
            return bio_resp(400, false, 'Verifique al menos una métrica del tablero.', 'MISSING_FILAS');
        }
        $ctx['horainicio'] = (string) ($registro['horainicio'] ?? '');
        $ctx['horafinal'] = (string) ($registro['horafinal'] ?? '');
        // El responsable de inspección lo escribe el operador en la app; si no
        // llega (apps antiguas) se usa el usuario de la sesión.
        $evaluador = trim((string) ($registro['evaluador'] ?? ''));
        if ($evaluador === '') {
            $evaluador = (string) ($data['nombre_usuario'] ?? $tuser);
        }
        $ctx['evaluador'] = bio_cut($evaluador, 30);
        $ctx['observacion'] = (string) ($registro['observacion'] ?? '');
        $ctx['filas'] = $filas;
    } elseif ($reporte === 'ingreso') {
        // Control de ingreso: cuántas personas entran y por qué. La placa solo
        // aplica si llegan en vehículo y los DNIs son opcionales (a veces
        // ingresan 30 personas y no es práctico pedir el documento a todas).
        $numpersonas = (int) ($registro['numpersonas'] ?? 0);
        if ($numpersonas < 1) {
            return bio_resp(400, false, 'Indique cuántas personas ingresaron.', 'MISSING_NUMPERSONAS');
        }
        $motivo = trim((string) ($registro['motivo'] ?? ''));
        if ($motivo === '') {
            return bio_resp(400, false, 'Indique el motivo de la visita.', 'MISSING_MOTIVO');
        }
        // Cada DNI puede venir como texto («12345678») o como par
        // {dni, nombre} cuando se escaneó y se consultó el nombre.
        $dnis = [];
        $vistos = [];
        foreach ((array) ($registro['dnis'] ?? []) as $item) {
            $par = is_array($item)
                ? ['dni' => (string) ($item['dni'] ?? ''), 'nombre' => (string) ($item['nombre'] ?? '')]
                : ['dni' => (string) $item, 'nombre' => ''];
            $par['dni'] = preg_replace('/[^0-9A-Za-z]/', '', $par['dni']) ?? '';
            if ($par['dni'] === '' || isset($vistos[$par['dni']])) {
                continue;
            }
            $vistos[$par['dni']] = true;
            $dnis[] = $par;
        }
        // Cada vehículo del ingreso: `vehiculos` ([{placa, ingresa}]) en las
        // apps nuevas; la `placa` suelta de las viejas queda como un vehículo
        // que ingresa. La cabecera guarda el primero y el detalle los guarda
        // todos (opcional: puede ser un ingreso sin vehículo).
        // Galpón opcional: columna varchar con default ''; puede ir vacío al guardar.
        $galpon = bio_norm_galpon_registro($registro);
        $vehiculos = bio_ingreso_vehiculos($registro);
        $ctx['vehiculos'] = $vehiculos;
        $ctx['hora'] = (string) ($registro['hora'] ?? '');
        $ctx['numpersonas'] = $numpersonas;
        $ctx['galpon'] = $galpon;
        $ctx['areaproveedor'] = trim((string) ($registro['areaproveedor'] ?? $registro['areaProveedor'] ?? ''));
        $ctx['motivo'] = $motivo;
        $ctx['observacion'] = (string) ($registro['observacion'] ?? '');
        $ctx['proveedor'] = trim((string) ($registro['proveedor'] ?? ''));
        $ctx['proveedorRuc'] = trim((string) ($registro['proveedor_ruc'] ?? $registro['proveedorRuc'] ?? ''));
        $ctx['planVisitaId'] = bio_norm_plan_visita_id($registro['plan_visita_id'] ?? $registro['planVisitaId'] ?? 0);
        $ctx['dnis'] = $dnis;
    } elseif ($reporte === 'salida') {
        $dnis = bio_dnis_normalizados($registro['dnis'] ?? []);
        $vehiculos = bio_ingreso_vehiculos($registro);
        if ($dnis === [] && $vehiculos === []) {
            return bio_resp(400, false, 'Marque al menos una persona o un vehículo.', 'MISSING_DNIS');
        }
        $ctx['hora'] = (string) ($registro['hora'] ?? '');
        $ctx['movimiento'] = bio_norm_movimiento_salida((string) ($registro['movimiento'] ?? 'salida'));
        $ctx['tipoSalida'] = bio_norm_tipo_salida((string) ($registro['tipo_salida'] ?? $registro['tipoSalida'] ?? 'definitiva'));
        $ctx['grupoId'] = (string) ($registro['grupo_id'] ?? $registro['grupoId'] ?? '');
        $ctx['proveedor'] = (string) ($registro['proveedor'] ?? '');
        $ctx['motivo'] = (string) ($registro['motivo'] ?? '');
        $ctx['dnis'] = $dnis;
        $ctx['vehiculos'] = $vehiculos;
    } else { // fomites
        $referencia = trim((string) ($registro['referencia'] ?? ''));
        $proceso = trim((string) ($registro['proceso'] ?? ''));
        if ($referencia === '' || $proceso === '') {
            return bio_resp(400, false, 'Referencia y proceso son obligatorios.', 'MISSING_REFERENCIA');
        }
        $filas = is_array($registro['filas'] ?? null) ? $registro['filas'] : [];
        $validas = 0;
        foreach ($filas as $fila) {
            if (trim((string) ($fila['depredador'] ?? '')) !== '' && trim((string) ($fila['tipo'] ?? '')) !== '') {
                $validas++;
            }
        }
        if ($validas === 0) {
            return bio_resp(400, false, 'Registre al menos un depredador con su tipo.', 'MISSING_FILAS');
        }
        $ctx['referencia'] = $referencia;
        $ctx['proceso'] = $proceso;
        $ctx['observacion'] = (string) ($registro['observacion'] ?? '');
        $ctx['filas'] = $filas;
    }

    // --- Existencias (idempotencia) ----------------------------------------
    bio_ensure_imagenes_col($conn);
    bio_ensure_uuid_col($conn);
    bio_ensure_instalacion_col($conn);
    bio_ensure_bioseguridad_col($conn);
    bio_ensure_dni_nombre_col($conn);
    bio_ensure_visitante_col($conn);

    $existeUuid = bio_existe_uuid($conn, $reporte, $uuid);
    $existeLogico = bio_grupo_existe_logico($conn, $reporte, $ctx);
    $archivosRecibidos = bio_contar_archivos();

    // El uuid ya está en el servidor y no llegan evidencias nuevas: la subida
    // es idempotente y se responde con lo que hay guardado para que la app
    // pueda confirmar que sus imágenes también están.
    if ($existeUuid && !$esActualizacion && $archivosRecibidos === 0) {
        $imagenesGuardadas = bio_imagenes_grupo($conn, $reporte, $ctx);
        return bio_resp(200, true, 'El registro ya estaba en el servidor.', null, [
            'reporte' => $reporte,
            'cenco' => $cencos,
            'fecha' => $fecha,
            'turno' => $turno,
            'filas' => 0,
            'archivos' => 0,
            'imagenes' => $imagenesGuardadas,
            'imagenes_lista' => bio_lista_csv($imagenesGuardadas),
            'imagenes_ok' => true,
            'ya_existia' => true,
            'actualizado' => false,
        ]);
    }

    // Se reemplaza cuando el uuid ya existe o cuando la llave lógica legacy ya
    // estaba ocupada por un registro anterior (sin uuid) de la misma fecha/turno.
    $reemplaza = $existeUuid || $existeLogico;
    $esModificacion = $esActualizacion || $reemplaza;

    // --- Evidencias --------------------------------------------------------
    $imagenesPrevias = $reemplaza ? bio_imagenes_grupo($conn, $reporte, $ctx) : '';
    $subidas = bio_subir_imagenes($reporte, $cencos);
    if ($subidas !== []) {
        if ($imagenesPrevias !== '') {
            bio_limpiar_imagenes($imagenesPrevias);
        }
        $imagenesCsv = implode(',', $subidas);
    } else {
        $imagenesCsv = $imagenesPrevias;
    }

    if ($reemplaza) {
        bio_borrar_grupo($conn, $reporte, $ctx);
    }

    // La auditoría de modificación solo se llena cuando se reemplaza algo; en
    // el alta queda vacía / NULL.
    $ctx['usuarioModificacion'] = $esModificacion ? bio_cut($tuser, 25) : '';
    $ctx['fechaHoraModificacion'] = $esModificacion ? $ahoraDatetime : '';

    $insertadas = bio_insertar_filas($conn, $reporte, $ctx, $imagenesCsv);
    if ($insertadas <= 0) {
        return bio_resp(500, false, 'No se pudo guardar el registro.', 'INSERT_FAILED');
    }

    // Verificación de evidencias: todo archivo que llegó debe haber quedado
    // guardado (la app compara esto con las imágenes que tiene en el equipo).
    $imagenesLista = bio_lista_csv($imagenesCsv);
    $imagenesOk = $archivosRecibidos === 0 ? true : (count($imagenesLista) >= $archivosRecibidos);

    return bio_resp(200, true, $esModificacion ? 'Registro actualizado.' : 'Registro guardado correctamente.', null, [
        'reporte' => $reporte,
        'cenco' => $cencos,
        'fecha' => $fecha,
        'turno' => $turno,
        'filas' => $insertadas,
        'archivos' => count($subidas),
        'imagenes' => $imagenesCsv,
        'imagenes_lista' => $imagenesLista,
        'imagenes_ok' => $imagenesOk,
        'ya_existia' => $existeUuid,
        'actualizado' => $esModificacion,
    ]);
}

/** Convierte el CSV de rutas de imágenes en una lista. */
function bio_lista_csv(?string $csv): array
{
    if ($csv === null || trim($csv) === '') {
        return [];
    }
    $out = [];
    foreach (explode(',', $csv) as $ruta) {
        $ruta = trim($ruta);
        if ($ruta !== '') {
            $out[] = $ruta;
        }
    }

    return $out;
}

/** Normaliza el turno a "Dia" / "Noche" (valores usados en la BD legacy). */
/**
 * Galpones del ingreso: lista `galpones[]` o texto `galpon` (varios separados por coma).
 * Se guarda en `san_fact_ingresogranja_cab.galpon` (varchar 120).
 *
 * @param array<string,mixed> $reg
 */
function bio_norm_galpon_registro(array $reg): string
{
    $partes = [];
    if (isset($reg['galpones']) && is_array($reg['galpones'])) {
        foreach ($reg['galpones'] as $g) {
            $t = trim((string) $g);
            if ($t !== '') {
                $partes[] = $t;
            }
        }
    } else {
        $raw = trim((string) ($reg['galpon'] ?? ''));
        if ($raw !== '') {
            foreach (preg_split('/\s*,\s*/', $raw) ?: [] as $g) {
                $t = trim((string) $g);
                if ($t !== '') {
                    $partes[] = $t;
                }
            }
        }
    }
    if ($partes === []) {
        return '';
    }
    $vistos = [];
    $unicos = [];
    foreach ($partes as $p) {
        $k = mb_strtolower($p, 'UTF-8');
        if (isset($vistos[$k])) {
            continue;
        }
        $vistos[$k] = true;
        $unicos[] = bio_cut($p, 40);
    }

    return bio_cut(implode(', ', $unicos), 120);
}

/** Id del plan en portal (`san_fact_planvisita_cab.id`); 0 si el ingreso no viene de plan. */
function bio_norm_plan_visita_id($raw): int
{
    $s = trim((string) $raw);
    if ($s === '' || !ctype_digit($s)) {
        return 0;
    }

    return max(0, (int) $s);
}

/** Valores en `san_fact_salidagranja_cab.movimiento`: salida | regreso. */
function bio_norm_movimiento_salida(string $mov): string
{
    $m = strtolower(trim($mov));
    if ($m === 'regreso' || $m === 'reingreso') {
        return 'regreso';
    }

    return 'salida';
}

/** Valores en `san_fact_salidagranja_cab.tipoSalida`: definitiva | temporal. */
function bio_norm_tipo_salida(string $tipo): string
{
    $t = strtolower(trim($tipo));
    if ($t === 'temporal') {
        return 'temporal';
    }

    return 'definitiva';
}

function bio_turno(string $turno): string
{
    $t = mb_strtolower(trim($turno), 'UTF-8');
    $t = str_replace(['í', 'á'], ['i', 'a'], $t);
    if (in_array($t, ['dia', 'día', 'd', 'day', '1'], true)) {
        return 'Dia';
    }
    if (in_array($t, ['noche', 'n', 'night', '2'], true)) {
        return 'Noche';
    }
    return '';
}

/**
 * @param array<string, mixed>|null $data
 * @return array{status:int,success:bool,message:string,errorCode:?string,data:?array<string,mixed>}
 */
function bio_resp(int $status, bool $success, string $message, ?string $errorCode = null, ?array $data = null): array
{
    return [
        'status' => $status,
        'success' => $success,
        'message' => $message,
        'errorCode' => $errorCode,
        'data' => $data,
    ];
}
