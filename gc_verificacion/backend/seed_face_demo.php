<?php
// Siembra veri_plantilla con las 50 personas de face-demo (solo pruebas).
// Uso: C:\xampp\php\php.exe <ruta>\backend\seed_face_demo.php [personas.json]
// No desplegar a htdocs: es solo herramienta local.
declare(strict_types=1);

chdir('C:/xampp/htdocs/conexion_grs');
require 'conexion.php';

$archivo = $argv[1] ?? 'C:/Users/SISTEMASTEST/Documents/face-demo/dataset/personas.json';
if (!is_file($archivo)) {
    fwrite(STDERR, "No existe $archivo\n");
    exit(1);
}
$data = json_decode((string) file_get_contents($archivo), true);
if (!is_array($data) || !isset($data['personas']) || !is_array($data['personas'])) {
    fwrite(STDERR, "personas.json inválido\n");
    exit(1);
}

$conn = conectar_joya_mysqli();
if (!$conn) {
    fwrite(STDERR, "Sin conexión JOYA\n");
    exit(1);
}
mysqli_set_charset($conn, 'utf8mb4');

$st = $conn->prepare(
    'INSERT INTO veri_plantilla (dni, nombre, vector, miniatura, modelo, estado, usuario) VALUES (?, ?, ?, ?, ?, \'A\', \'SEED\') ' .
    'ON DUPLICATE KEY UPDATE nombre = VALUES(nombre), vector = VALUES(vector), miniatura = VALUES(miniatura), modelo = VALUES(modelo), estado = \'A\''
);
if (!$st) {
    fwrite(STDERR, 'Error al preparar: ' . $conn->error . "\n");
    exit(1);
}

$ok = 0;
$omitidas = 0;
foreach ($data['personas'] as $p) {
    if (!is_array($p)) {
        $omitidas++;
        continue;
    }
    $dni = preg_replace('/\D/', '', (string) ($p['doc'] ?? '')) ?? '';
    $nombre = trim((string) ($p['nombre'] ?? ''));
    $media = $p['media'] ?? null;
    $modelo = trim((string) ($p['modelo'] ?? ''));
    if (strlen($dni) !== 8 || mb_strlen($nombre) < 2) {
        $omitidas++;
        continue;
    }
    if ($modelo !== 'arcface-w600k_mbf') {
        $omitidas++;
        continue;
    }
    if (!is_array($media) || count($media) !== 512) {
        $omitidas++;
        continue;
    }
    $floats = [];
    $valido = true;
    foreach (array_values($media) as $v) {
        if (!is_numeric($v) || !is_finite((float) $v)) {
            $valido = false;
            break;
        }
        $floats[] = (float) $v;
    }
    if (!$valido) {
        $omitidas++;
        continue;
    }
    $foto = trim((string) ($p['foto'] ?? ''));
    if (strncmp($foto, 'data:', 5) === 0) {
        $pos = strpos($foto, ',');
        $foto = $pos === false ? '' : substr($foto, $pos + 1);
    }
    if ($foto !== '') {
        if (strlen($foto) > 150000) {
            $omitidas++;
            continue;
        }
        $bin = base64_decode($foto, true);
        if ($bin === false || strlen($bin) < 3 || substr($bin, 0, 3) !== "\xFF\xD8\xFF") {
            $omitidas++;
            continue;
        }
    }
    $vectorJson = json_encode($floats, JSON_UNESCAPED_UNICODE);
    if (!is_string($vectorJson)) {
        $omitidas++;
        continue;
    }
    $st->bind_param('sssss', $dni, $nombre, $vectorJson, $foto, $modelo);
    if ($st->execute()) {
        $ok++;
    } else {
        fwrite(STDERR, "Error $dni: " . $st->error . "\n");
        $omitidas++;
    }
}
$st->close();

$total = 0;
$rs = $conn->query("SELECT COUNT(*) AS n FROM veri_plantilla WHERE estado = 'A'");
if ($rs && ($row = $rs->fetch_assoc())) {
    $total = (int) $row['n'];
}
$conn->close();
echo "Sembradas: $ok | Omitidas: $omitidas | Activas en tabla: $total\n";
echo "Sincronice la app: deben llegar como altas.\n";
