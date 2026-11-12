#!/usr/bin/env python3
# Loopin — genera los PNG del icono (para lanzadores sin iconos adaptables) y
# una vista previa. El icono de verdad es vectorial:
#   android/app/src/main/res/drawable/ic_launcher_foreground.xml
# y este script dibuja lo mismo con las mismas medidas (lienzo de 108).
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Uso, desde app/:  python3 tool/make_icon.py
import os
import sys

from PIL import Image, ImageDraw

RES = "android/app/src/main/res"
BG = (0x1B, 0x1B, 0x1D)


def draw(size, shape, ss=8):
    """Dibuja el icono. shape: 'square' (sin recortar), 'circle' o 'squircle'."""
    n = size * ss
    k = n / 72.0  # se ve la zona central de 72 de las 108 del lienzo
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n / 2

    def disc(r, fill):
        d.ellipse([c - r * k, c - r * k, c + r * k, c + r * k], fill=fill)

    def ring(r, w, fill, start=None, end=None):
        box = [c - (r + w / 2) * k, c - (r + w / 2) * k, c + (r + w / 2) * k, c + (r + w / 2) * k]
        if start is None:
            d.ellipse(box, outline=fill, width=round(w * k))
        else:
            d.arc(box, start, end, fill=fill, width=round(w * k))
            # Extremos redondeados
            import math
            for a in (start, end):
                x = c + r * k * math.cos(math.radians(a))
                y = c + r * k * math.sin(math.radians(a))
                d.ellipse([x - w * k / 2, y - w * k / 2, x + w * k / 2, y + w * k / 2], fill=fill)

    d.rectangle([0, 0, n, n], fill=BG + (255,))
    ring(26.5, 9, (0x08, 0x08, 0x0A, 255))
    ring(26.5, 5.6, (0xFF, 0x4B, 0x3E, 255), -90, 180)
    disc(19, (0x3A, 0x3A, 0x40, 255))
    disc(16.6, (0x85, 0x83, 0x7B, 255))
    disc(15.4, (0xC4, 0xC2, 0xB9, 255))
    ring(10.2, 0.9, (0x85, 0x83, 0x7B, 255))

    if shape != "square":
        mask = Image.new("L", (n, n), 0)
        m = ImageDraw.Draw(mask)
        if shape == "circle":
            m.ellipse([0, 0, n - 1, n - 1], fill=255)
        else:
            m.rounded_rectangle([0, 0, n - 1, n - 1], radius=n * 0.23, fill=255)
        img.putalpha(mask)
    return img.resize((size, size), Image.LANCZOS)


def main():
    if not os.path.isdir(RES):
        sys.exit("Ejecuta este script desde la carpeta app/")
    for name, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        draw(size, "squircle").save(f"{RES}/mipmap-{name}/ic_launcher.png")
    # Vista previa: como lo recorta cada lanzador
    os.makedirs("tool/screenshots", exist_ok=True)
    tile, pad = 256, 32
    sheet = Image.new("RGB", (3 * tile + 4 * pad, tile + 2 * pad), (0xE8, 0xE1, 0xCE))
    for i, shape in enumerate(["circle", "squircle", "square"]):
        icon = draw(tile, shape)
        sheet.paste(icon, (pad + i * (tile + pad), pad), icon)
    sheet.save("tool/screenshots/icono.png")


if __name__ == "__main__":
    main()
