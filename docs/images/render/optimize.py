"""Shrinks PNGs in place: 256-color palette with alpha (dithered), only when that is smaller.
Small images (lossless <= 200 KB, for example the menu bar panel) stay lossless, so soft glows and gradients do not band."""
import os, sys
from PIL import Image

for root in sys.argv[1:]:
    paths = [root] if root.endswith(".png") else [os.path.join(d, f) for d, _, fs in os.walk(root) for f in fs if f.endswith(".png")]
    for p in paths:
        if "/dmg/" in p:
            continue
        before = os.path.getsize(p)
        im = Image.open(p).convert("RGBA")
        q = None
        if im.getextrema()[3][0] == 255:
            # Opaque (hero): lossless RGB when it fits the 1.49 MB budget (no gradient banding),
            # else median cut + dithering.
            im.convert("RGB").save(p + ".rgb.png", optimize=True)
            if os.path.getsize(p + ".rgb.png") <= 1_490_000:
                q = None
            else:
                os.remove(p + ".rgb.png")
                # k-means refinement keeps palette entries for the small warm areas (the jar, the knob arc).
                q = im.convert("RGB").quantize(colors=256, method=Image.Quantize.MEDIANCUT, kmeans=3,
                                               dither=Image.Dither.FLOYDSTEINBERG)
        else:
            im.save(p + ".rgb.png", optimize=True)
            if os.path.getsize(p + ".rgb.png") <= 200_000:
                q = None
            else:
                os.remove(p + ".rgb.png")
                q = im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG)
        tmp = p + ".tmp.png"
        if q is None:
            os.replace(p + ".rgb.png", tmp)
        else:
            q.save(tmp, optimize=True)
        after = os.path.getsize(tmp)
        if after < before:
            os.replace(tmp, p)
        else:
            os.remove(tmp)
            after = before
        print(f"{os.path.basename(p)}: {before // 1024} KB -> {after // 1024} KB")
