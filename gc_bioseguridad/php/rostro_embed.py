#!/usr/bin/env python3
"""Embedding ArcFace (w600k_mbf) igual que gc_verificacion.

Lee JSON por stdin:
  {"imagenes":[{"id":"probe","path":"/tmp/a.jpg"}]}
Escribe JSON por stdout:
  {"ok":true,"vectores":{"probe":[...512]},"errores":{"probe":"sin_rostro"}}

Alineación de 5 puntos y normalización (v-127.5)/127.5, salida L2,
mismo tpl112 que lib/utils/face_math.dart.
"""
import json
import sys

import cv2
import numpy as np
import onnxruntime as ort
from PIL import Image, ImageOps

TPL = np.array(
    [
        [38.2946, 51.6963],
        [73.5318, 51.5014],
        [56.0252, 71.7366],
        [41.5493, 92.3655],
        [70.7299, 92.2041],
    ],
    dtype=np.float64,
)


def similar(src, dst):
    n = src.shape[0]
    sx, sy = src.mean(axis=0)
    dx, dy = dst.mean(axis=0)
    a = b = v = 0.0
    for i in range(n):
        x = src[i, 0] - sx
        y = src[i, 1] - sy
        u = dst[i, 0] - dx
        w = dst[i, 1] - dy
        a += x * u + y * w
        b += x * w - y * u
        v += x * x + y * y
    if v == 0:
        return 1.0, 0.0, 0.0, 1.0, 0.0, 0.0
    ca, sb = a / v, b / v
    return (
        ca,
        sb,
        -sb,
        ca,
        dx - (ca * sx - sb * sy),
        dy - (sb * sx + ca * sy),
    )


def warp112(rgb, pts):
    h, w = rgb.shape[:2]
    a, b, c, d, tx, ty = similar(pts, TPL)
    det = a * d - b * c
    if det == 0:
        return np.zeros((3, 112, 112), dtype=np.float32)
    yy, xx = np.mgrid[0:112, 0:112]
    x = (d * (xx - tx) - c * (yy - ty)) / det
    y = (-b * (xx - tx) + a * (yy - ty)) / det
    x0 = np.clip(np.floor(x).astype(np.int32), 0, w - 1)
    y0 = np.clip(np.floor(y).astype(np.int32), 0, h - 1)
    x1 = np.clip(x0 + 1, 0, w - 1)
    y1 = np.clip(y0 + 1, 0, h - 1)
    fx = np.clip(x - np.floor(x), 0, 1).astype(np.float32)
    fy = np.clip(y - np.floor(y), 0, 1).astype(np.float32)
    out = np.empty((3, 112, 112), dtype=np.float32)
    for ch in range(3):
        p00 = rgb[y0, x0, ch].astype(np.float32)
        p10 = rgb[y0, x1, ch].astype(np.float32)
        p01 = rgb[y1, x0, ch].astype(np.float32)
        p11 = rgb[y1, x1, ch].astype(np.float32)
        val = (
            p00 * (1 - fx) * (1 - fy)
            + p10 * fx * (1 - fy)
            + p01 * (1 - fx) * fy
            + p11 * fx * fy
        )
        out[ch] = (val - 127.5) / 127.5
    return out


def cargar(path):
    im = ImageOps.exif_transpose(Image.open(path).convert("RGB"))
    rgb = np.asarray(im)
    return cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR), rgb


def landmarks(bgr, det):
    h, w = bgr.shape[:2]
    det.setInputSize((w, h))
    _, faces = det.detect(bgr)
    if faces is None or len(faces) == 0:
        return None
    best = max(faces, key=lambda f: float(f[2]) * float(f[3]))
    # YuNet: re, le, nose, rcm, lcm
    re = (float(best[4]), float(best[5]))
    le = (float(best[6]), float(best[7]))
    nose = (float(best[8]), float(best[9]))
    rcm = (float(best[10]), float(best[11]))
    lcm = (float(best[12]), float(best[13]))
    return np.array([le, re, nose, lcm, rcm], dtype=np.float64)


def normalizar(vec):
    n = float(np.linalg.norm(vec))
    if n == 0:
        return vec.astype(np.float32)
    return (vec / n).astype(np.float32)


def main():
    args = sys.argv[1:]
    arc = args[args.index("--arcface") + 1]
    yunet = args[args.index("--yunet") + 1]
    pedido = json.load(sys.stdin)
    det = cv2.FaceDetectorYN.create(yunet, "", (320, 320), 0.6, 0.3, 5000)
    ses = ort.InferenceSession(arc, providers=["CPUExecutionProvider"])
    inn = ses.get_inputs()[0].name
    vectores = {}
    errores = {}
    for item in pedido.get("imagenes") or []:
        ident = str(item.get("id"))
        try:
            bgr, rgb = cargar(item["path"])
            pts = landmarks(bgr, det)
            if pts is None:
                errores[ident] = "sin_rostro"
                continue
            entrada = warp112(rgb, pts)[None, ...]
            out = ses.run(None, {inn: entrada})[0].reshape(-1)
            vectores[ident] = normalizar(out).tolist()
        except Exception as exc:
            errores[ident] = str(exc)
    json.dump({"ok": True, "vectores": vectores, "errores": errores}, sys.stdout)


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        json.dump({"ok": False, "motivo": "sin_motor", "message": str(exc)}, sys.stdout)
        sys.exit(1)
