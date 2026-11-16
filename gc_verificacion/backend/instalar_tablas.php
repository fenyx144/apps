<?php
// Crea las tablas veri_* con la conexión de la app (base JOYA).
// Uso: C:\xampp\php\php.exe <ruta>\backend\instalar_tablas.php
declare(strict_types=1);

chdir('C:/xampp/htdocs/conexion_grs');
require 'conexion.php';

$archivo = __DIR__ . '/verificacion.sql';
if (!is_file($archivo)) {
    fwrite(STDERR, "No existe verificacion.sql\n");
    exit(1);
}
$lineas = [];
foreach (explode("\n", (string) file_get_contents($archivo)) as $ln) {
    $t = ltrim($ln);
    if ($t === '' || strncmp($t, '--', 2) === 0) {
        continue;
    }
    $lineas[] = $ln;
}

$conn = conectar_joya_mysqli();
if (!$conn) {
    fwrite(STDERR, "Sin conexión JOYA\n");
    exit(1);
}
$ok = 0;
foreach (explode(';', implode("\n", $lineas)) as $p) {
    $stmt = trim($p);
    if ($stmt === '') {
        continue;
    }
    if (stripos(ltrim($stmt), 'CREATE TABLE') !== 0) {
        fwrite(STDERR, "Sentencia no permitida, se omite\n");
        continue;
    }
    if ($conn->query($stmt)) {
        $ok++;
        echo "OK tabla $ok\n";
    } else {
        fwrite(STDERR, 'Error: ' . $conn->error . "\n");
    }
}
$nombres = [];
$rs = $conn->query("SHOW TABLES LIKE 'veri_%'");
if ($rs) {
    while ($row = $rs->fetch_row()) {
        $nombres[] = $row[0];
    }
}
$conn->close();
echo 'Creadas: ' . $ok . ' | Tablas veri: ' . implode(',', $nombres) . "\n";
