import 'package:permission_handler/permission_handler.dart';

/// Permisos de cámara/galería: solo solicita si aún no están concedidos.
class MediaPermissions {
  static Future<bool> ensureCamera() => _ensure(Permission.camera);

  static Future<bool> ensureGallery() async {
    if (await _ensure(Permission.photos)) return true;
    return _ensure(Permission.storage);
  }

  static Future<bool> _ensure(Permission permission) async {
    var status = await permission.status;
    if (status.isGranted || status.isLimited) return true;
    if (status.isPermanentlyDenied || status.isRestricted) return false;
    status = await permission.request();
    return status.isGranted || status.isLimited;
  }
}
