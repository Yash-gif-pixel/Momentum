#!/usr/bin/env python3
"""Renders the Credify mark to the web favicon and PWA icons.

    python3 tools/mark.py

THIS FILE AND frontend/lib/widgets/credify_mark.dart SHARE ONE SET OF
NUMBERS. The normalised geometry below is duplicated there, deliberately: the
in-app mark is painted by Flutter at runtime so it can pick up the live theme
gradient, while the browser needs flat PNGs it can show before Flutter has
booted. Neither can generate the other, so they are kept in sync by hand --
change one and change the other, or the tab icon stops matching the app.

The mark: a living cash-flow waveform cresting above a flat, dashed baseline
(the bureau file that has no record of it).

Needs Pillow. Icons are committed, so this only has to be run when the mark
itself changes.
"""

from pathlib import Path

from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parents[1]
WEB_DIR = REPO_ROOT / "frontend" / "web"

# --- Geometry (mirrors credify_mark.dart) -----------------------------------
BASELINE = 0.615
DASH_Y = 0.745
X0, X1 = 0.165, 0.835

# Cubic segments of the wave's upper edge: (control1, control2, end).
WAVE = [
    ((0.215, 0.560), (0.250, 0.470), (0.305, 0.468)),
    ((0.350, 0.466), (0.360, 0.545), (0.400, 0.520)),
    ((0.450, 0.487), (0.462, 0.245), (0.520, 0.245)),
    ((0.578, 0.245), (0.590, 0.470), (0.632, 0.500)),
    ((0.668, 0.525), (0.688, 0.430), (0.735, 0.432)),
    ((0.788, 0.434), (0.800, 0.560), (X1, BASELINE)),
]
DASHES = [(0.165, 0.300), (0.355, 0.490), (0.545, 0.680), (0.735, 0.835)]

# The dark theme is the product's primary look, so the browser icon uses it.
DARK = ((0xC0, 0x84, 0xFC), (0xF4, 0x72, 0xB6))
LIGHT = ((0x63, 0x66, 0xF1), (0x10, 0xB9, 0x81))

SUPERSAMPLE = 8

# Android crops a maskable icon to an unknown shape and only guarantees the
# central 80%. Full-bleed background, glyph shrunk to sit inside that.
MASKABLE_GLYPH_SCALE = 0.70


def _bezier(p0, c1, c2, p3, steps):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        pts.append(
            (
                u**3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t**3 * p3[0],
                u**3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t**3 * p3[1],
            )
        )
    return pts


def _wave_points(steps=28):
    pts = [(X0, BASELINE)]
    cur = (X0, BASELINE)
    for c1, c2, end in WAVE:
        pts.extend(_bezier(cur, c1, c2, end, steps)[1:])
        cur = end
    return pts


def _gradient_tile(size, gradient):
    img = Image.new("RGB", (size, size))
    px = img.load()
    (r0, g0, b0), (r1, g1, b1) = gradient
    span = 2 * (size - 1)
    for y in range(size):
        for x in range(size):
            t = (x + y) / span
            px[x, y] = (
                int(r0 + (r1 - r0) * t),
                int(g0 + (g1 - g0) * t),
                int(b0 + (b1 - b0) * t),
            )
    return img


def render(size, gradient=DARK, maskable=False):
    n = size * SUPERSAMPLE
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    tile = _gradient_tile(n, gradient)

    if maskable:
        img.paste(tile, (0, 0))
        scale = MASKABLE_GLYPH_SCALE
    else:
        mask = Image.new("L", (n, n), 0)
        # Matches the 10px-at-32px radius the app's own container uses.
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, n - 1, n - 1], radius=int(n * 0.3125), fill=255
        )
        img.paste(tile, (0, 0), mask)
        scale = 1.0

    off = (1 - scale) / 2

    def place(x, y):
        return (off * n + x * scale * n, off * n + y * scale * n)

    d = ImageDraw.Draw(img)
    poly = [place(x, y) for x, y in _wave_points()]
    poly.append(place(X1, BASELINE))
    poly.append(place(X0, BASELINE))
    d.polygon(poly, fill=(255, 255, 255, 255))

    width = max(1, round(n * scale * 0.052))
    for a, b in DASHES:
        d.line([place(a, DASH_Y), place(b, DASH_Y)], fill="white", width=width)

    return img.resize((size, size), Image.LANCZOS)


def main():
    WEB_DIR.mkdir(parents=True, exist_ok=True)
    (WEB_DIR / "icons").mkdir(exist_ok=True)

    outputs = [
        (WEB_DIR / "favicon.png", 32, False),
        (WEB_DIR / "icons" / "Icon-192.png", 192, False),
        (WEB_DIR / "icons" / "Icon-512.png", 512, False),
        (WEB_DIR / "icons" / "Icon-maskable-192.png", 192, True),
        (WEB_DIR / "icons" / "Icon-maskable-512.png", 512, True),
    ]
    for path, size, maskable in outputs:
        render(size, DARK, maskable=maskable).save(path)
        print(f"wrote {path.relative_to(REPO_ROOT)} ({size}px"
              f"{', maskable' if maskable else ''})")


if __name__ == "__main__":
    main()
