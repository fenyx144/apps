import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Convierte un frame de [CameraController] a [InputImage] para ML Kit.
InputImage? inputImageFromCameraImage(
  CameraImage image,
  CameraDescription camera,
  int deviceOrientationDeg,
) {
  if (image.planes.isEmpty) return null;

  InputImageRotation rotation;
  if (Platform.isIOS) {
    rotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
        InputImageRotation.rotation0deg;
  } else {
    var rotationCompensation =
        _orientacionDispositivo(deviceOrientationDeg) ?? 0;
    if (camera.lensDirection == CameraLensDirection.front) {
      rotationCompensation = (sensorOrientation(camera) + rotationCompensation) % 360;
    } else {
      rotationCompensation =
          (sensorOrientation(camera) - rotationCompensation + 360) % 360;
    }
    rotation =
        InputImageRotationValue.fromRawValue(rotationCompensation) ??
        InputImageRotation.rotation0deg;
  }

  final format = InputImageFormatValue.fromRawValue(image.format.raw);
  if (format == null) return null;

  if (Platform.isAndroid &&
      format != InputImageFormat.nv21 &&
      format != InputImageFormat.yuv420) {
    return null;
  }

  final bytes = _concatPlanes(image.planes);
  if (bytes.isEmpty) return null;

  return InputImage.fromBytes(
    bytes: bytes,
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: image.planes.first.bytesPerRow,
    ),
  );
}

int sensorOrientation(CameraDescription camera) => camera.sensorOrientation;

int? _orientacionDispositivo(int deg) {
  return switch (deg) {
    0 => 0,
    90 => 90,
    180 => 180,
    270 => 270,
    _ => null,
  };
}

Uint8List _concatPlanes(List<Plane> planes) {
  final out = BytesBuilder(copy: false);
  for (final p in planes) {
    out.add(p.bytes);
  }
  return out.takeBytes();
}
