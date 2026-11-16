<?php
// Evitar mostrar warnings/errors que interrumpan el JSON
error_reporting(E_ALL);
ini_set('display_errors', 0);
ini_set('log_errors', 1);

header('Content-Type: application/json; charset=utf-8');
date_default_timezone_set('America/Lima');

// Capturar cualquier salida del include
ob_start();
include_once '../../../conexion_grs_joya/conexion.php';
$conn = conectar_joya();
ob_end_clean();

if (!$conn) {
    echo json_encode(['success' => false, 'message' => 'Error de conexión a la base de datos'], JSON_UNESCAPED_UNICODE);
    exit;
}

// Obtener parámetros de paginación
$page = isset($_GET['page']) ? (int)$_GET['page'] : 1;
$pageSize = isset($_GET['pageSize']) ? (int)$_GET['pageSize'] : 10;

if ($page < 1) $page = 1;
if ($pageSize < 1) $pageSize = 10;

$offset = ($page - 1) * $pageSize;

// Configurar sql_mode para MySQL 5.4 (deshabilitar ONLY_FULL_GROUP_BY si es necesario)
$conn->query("SET sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''))");

// Query para obtener necropsias agrupadas por lote (tdate, tnumreg, tgranja, tgalpon, tfectra)
// Ordenar por fecha descendente, luego por numreg descendente, luego por granja
// Usar GROUP BY en lugar de DISTINCT para mejor compatibilidad con MySQL 5.4
$sql = "SELECT
    tdate, tnumreg, tgranja, tgalpon, tfectra, tcencos, tedad, tcampania
FROM t_regnecropsia
GROUP BY tdate, tnumreg, tgranja, tgalpon, tfectra, tcencos, tedad, tcampania
ORDER BY
    tdate DESC,
    tnumreg DESC,
    tgranja ASC
LIMIT ? OFFSET ?";

$stmt = $conn->prepare($sql);

if (!$stmt) {
    echo json_encode([
        'success' => false,
        'message' => 'Error preparando consulta: ' . $conn->error
    ], JSON_UNESCAPED_UNICODE);
    $conn->close();
    exit;
}

$stmt->bind_param("ii", $pageSize, $offset);
$stmt->execute();
$result = $stmt->get_result();

$necropsias = [];
while ($row = $result->fetch_assoc()) {
    $necropsias[] = $row;
}

$stmt->close();
$conn->close();

echo json_encode([
    'success' => true,
    'data' => $necropsias,
    'page' => $page,
    'pageSize' => $pageSize,
], JSON_UNESCAPED_UNICODE);
?>
