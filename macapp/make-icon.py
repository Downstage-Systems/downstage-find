#!/usr/bin/env python3
"""Downstage app icons, on the brand guide's product-mark recipe (page 06): the master enclosure and the green
downstage edge on House Black, one interior element per app, colour only where it means something. A full macOS
tile, flat: no gradients or shadows. The master copy is Logos/app-icons/make-icon.py; each app keeps a copy with its
name set in APP below, so its build needs nothing outside its repo.
    make-icon.py out-dir [--ios ios.png]     writes app-icon.png (1024) and AppIcon.icns; --ios also writes the
                                             full-bleed 1024 iPhone icon
    make-icon.py --sheet out-dir             (master only) every app's icon plus sheet.png, big and at Dock sizes"""
import os, shutil, subprocess, sys, tempfile
from PIL import Image, ImageDraw
APP = "Find"
from PIL import Image, ImageDraw
K, N = 4, 1024
BLACK, PANEL, EDGE, TEXT, DIM = "#0B0D10", "#14181D", "#242B33", "#E8ECEF", "#9AA4AD"
GREEN, RED, AMBER, VIOLET = "#2FD97B", "#E5484D", "#F5A524", "#8E6FE6"
APPS = ["Find", "Virtual Deck", "Show Builder", "SuperSource Builder", "Lower Thirds", "Cue Tally Builder"]
S = 7.2                                  # mark units (96 box) to icon px; the mark is centred, nudged up a little

def icon(app, size=1024, ios=False):
    im = Image.new("RGBA", (N * K, N * K), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    def R(x0, y0, x1, y1, r, **kw): d.rounded_rectangle([x0 * K, y0 * K, x1 * K, y1 * K], r * K, **kw)
    s = S * 1.28 if ios else S; ox, oy = 512 - 48 * s, 512 - 50 * s
    def M(x, y): return ox + x * s, oy + y * s               # a point in mark units
    def MR(x, y, w, h, r, **kw):
        a, b = M(x, y); R(a, b, a + w * s, b + h * s, r * s, **kw)
    def ME(cx, cy, r, **kw):
        a, b = M(cx - r, cy - r); d.ellipse([a * K, b * K, (a + 2 * r * s) * K, (b + 2 * r * s) * K], **kw)
    def MA(cx, cy, r, a0, a1, w, fill):
        a, b = M(cx - r, cy - r); d.arc([a * K, b * K, (a + 2 * r * s) * K, (b + 2 * r * s) * K], a0, a1, fill=fill, width=int(w * s * K))
    # the tile: House Black, a fine Edge line so it holds its shape in a dark Dock
    if ios:                                  # iOS rounds the corners itself and wants an opaque square
        d.rectangle([0, 0, N * K, N * K], fill=BLACK)
    else:
        R(100, 100, 924, 924, 185, fill=EDGE); R(106, 106, 918, 918, 180, fill=BLACK)
    # the master enclosure and the downstage edge (downstage-mark.svg geometry)
    MR(6, 10, 84, 66, 10, fill=PANEL, outline=TEXT, width=int(7 * s * K))
    MR(20, 83, 56, 7, 3.5, fill=GREEN)
    # the interior: one element, as big as the screen allows (screen inside is 13.5..86.5 x 13.5..72.5)
    if app == "Find":                                       # a lens finding a device that's online
        ME(43, 40, 17, outline=TEXT, width=int(6.5 * s * K))
        ME(43, 40, 6, fill=GREEN)
        a, b = M(55.5, 52.5); c, e = M(70, 67)
        d.line([(a * K, b * K), (c * K, e * K)], fill=TEXT, width=int(8 * s * K)); ME(70, 67, 4, fill=TEXT)
    elif app == "Virtual Deck":                             # Stream Deck keys: control surface violet, one key live
        for r in range(2):
            for q in range(3):
                MR(19 + q * 20.5, 20 + r * 23.5, 17, 19.5, 3.5, fill=GREEN if (r, q) == (0, 0) else VIOLET)
    elif app == "Show Builder":                             # a show's pages, stacked, and a new one being added
        MR(38, 19, 36, 28, 4, fill=EDGE)
        MR(31, 26, 36, 28, 4, fill=DIM)
        MR(22, 33, 38, 31, 4, fill=TEXT)
        MR(38.6, 38, 5, 21, 2.5, fill=VIOLET); MR(30.5, 46, 21, 5, 2.5, fill=VIOLET)
    elif app == "SuperSource Builder":                      # two boxes over the background, one on program
        MR(19, 20, 32, 24, 3, fill=TEXT)
        MR(41, 35, 36, 27, 3, fill=PANEL)
        MR(43.5, 37.5, 31, 22, 2, fill=GREEN)
    elif app == "Lower Thirds":                             # a name on a bar across the bottom of the picture
        MR(18, 47, 54, 17, 3, fill=TEXT)
        MR(18, 47, 5, 17, 2, fill=GREEN)
        MR(28, 51.5, 32, 4, 2, fill=BLACK); MR(28, 58, 20, 2.8, 1.4, fill=DIM)
    elif app == "Cue Tally Builder":                        # a camera with its tally on air
        MR(19, 35, 40, 27, 5, fill=TEXT)
        d.polygon([(M(57, 41)[0] * K, M(57, 41)[1] * K), (M(77, 32)[0] * K, M(77, 32)[1] * K),
                   (M(77, 62)[0] * K, M(77, 62)[1] * K), (M(57, 53)[0] * K, M(57, 53)[1] * K)], fill=TEXT)
        ME(28, 26, 5.5, fill=RED)
        MR(25, 42.5, 18, 12, 3, fill=PANEL)
    return im.resize((size, size), Image.LANCZOS)


def main(out, app, ios_png=None):
    os.makedirs(out, exist_ok=True)
    big = icon(app)
    big.save(os.path.join(out, "app-icon.png"))
    tmp = tempfile.mkdtemp(); iconset = os.path.join(tmp, "AppIcon.iconset"); os.mkdir(iconset)
    for z in (16, 32, 128, 256, 512):
        big.resize((z, z), Image.LANCZOS).save(os.path.join(iconset, f"icon_{z}x{z}.png"))
        big.resize((z * 2, z * 2), Image.LANCZOS).save(os.path.join(iconset, f"icon_{z}x{z}@2x.png"))
    subprocess.check_call(["iconutil", "-c", "icns", iconset, "-o", os.path.join(out, "AppIcon.icns")])
    shutil.rmtree(tmp)
    if ios_png:
        icon(app, ios=True).convert("RGB").save(ios_png)


def sheet(out):
    icons = {a: icon(a) for a in APPS}
    for a, im in icons.items():
        im.save(os.path.join(out, a.replace(" ", "_") + ".png"))
    W, pad = 200, 30
    sh = Image.new("RGBA", (len(APPS) * (W + pad) + pad, W * 2 + pad * 4 + 110), (246, 247, 248, 255))
    ImageDraw.Draw(sh).rectangle([0, W + pad * 2, sh.width, sh.height], fill=(40, 40, 44, 255))
    for i, a in enumerate(APPS):
        x = pad + i * (W + pad); big = icons[a].resize((W, W), Image.LANCZOS)
        sh.paste(big, (x, pad), big); sh.paste(big, (x, W + pad * 3), big)
        for z, dx in ((64, -40), (32, 50)):
            sm = icons[a].resize((z, z), Image.LANCZOS); sh.paste(sm, (x + W // 2 + dx - z // 2, W * 2 + pad * 4 + 50 - z // 2), sm)
    sh.save(os.path.join(out, "sheet.png"))


if __name__ == "__main__":
    a = sys.argv[1:]
    if a[:1] == ["--sheet"]:
        sheet(a[1] if len(a) > 1 else ".")
    else:
        if not APP:
            sys.exit("Set APP to one of: " + ", ".join(APPS))
        ios = a[a.index("--ios") + 1] if "--ios" in a else None
        main(a[0] if a and a[0] != "--ios" else ".", APP, ios)
