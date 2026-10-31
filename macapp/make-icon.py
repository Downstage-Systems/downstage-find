#!/usr/bin/env python3
"""Draws the app icon: the builders' device and green stage line, with a magnifier over a row of devices.
    make-icon.py out-dir    writes app-icon.png (1024) and AppIcon.icns"""
import os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw

BEZEL_EDGE, BEZEL, SCREEN = "#20262e", "#14181d", "#0b0d10"
SLATE, GREEN, VIOLET, LIGHT = "#2e3640", "#2fd97b", "#8e6fe6", "#e8ecef"


def draw(size=1024):
    k = 4                               # drawn big and scaled down for clean corners
    im = Image.new("RGBA", (size * k, size * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    def rect(x0, y0, x1, y1, r, **kw):
        d.rounded_rectangle([x0 * k, y0 * k, x1 * k, y1 * k], r * k, **kw)
    rect(112, 230, 912, 760, 92, fill=BEZEL_EDGE)
    rect(122, 240, 902, 750, 84, fill=BEZEL)
    rect(146, 264, 878, 726, 62, fill=SCREEN)
    for i, c in enumerate((SLATE, GREEN, SLATE)):            # devices on the network
        x = 232 + i * 200
        rect(x, 420, x + 160, 570, 22, fill=c)
    d.ellipse([500 * k, 330 * k, 760 * k, 590 * k], outline=LIGHT, width=30 * k)       # the search
    d.line([(725 * k, 555 * k), (815 * k, 655 * k)], fill=LIGHT, width=38 * k)
    rect(272, 812, 752, 860, 24, fill=GREEN)                 # the stage line from the Downstage mark
    return im.resize((size, size), Image.LANCZOS)


def main(out):
    big = draw()
    big.save(os.path.join(out, "app-icon.png"))
    tmp = tempfile.mkdtemp(); iconset = os.path.join(tmp, "AppIcon.iconset"); os.mkdir(iconset)
    for s in (16, 32, 128, 256, 512):
        big.resize((s, s), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}.png"))
        big.resize((s * 2, s * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{s}x{s}@2x.png"))
    subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "AppIcon.icns")])
    shutil.rmtree(tmp)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
