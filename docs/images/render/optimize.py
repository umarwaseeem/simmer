"""Shrinks PNGs in place: 256-color palette (dithered, median cut), only when that is smaller.
Small images (lossless <= 200 KB, for example the menu bar panel) stay lossless, so soft glows and gradients do not band."""
import os, sys
import numpy as np
from PIL import Image


def quantize_rgba(im):
    """256-color palette that keeps soft gradients: median cut + k-means for the opaque pixels (FASTOCTREE, the only
    RGBA method in Pillow, bands glows and gradients), 16 entries with their own alpha for the anti-aliased edge
    pixels, and one fully transparent entry."""
    a = np.asarray(im.getchannel("A"))
    rgb = im.convert("RGB").quantize(colors=239, method=Image.Quantize.MEDIANCUT, kmeans=3,
                                     dither=Image.Dither.FLOYDSTEINBERG)
    idx = np.asarray(rgb).astype(np.uint8).copy()
    palette = rgb.getpalette()[:239 * 3]
    palette += [0] * (239 * 3 - len(palette))
    alphas = [255] * 239
    partial = (a > 0) & (a < 255)
    if partial.any():
        px = np.asarray(im)[partial]                                  # N x 4
        edge = Image.frombytes("RGBA", (len(px), 1), np.ascontiguousarray(px, dtype=np.uint8).tobytes())
        edge = edge.quantize(colors=16, method=Image.Quantize.FASTOCTREE)
        eidx = np.asarray(edge).reshape(-1)
        epal = edge.getpalette("RGBA")[:16 * 4]
        epal += [0] * (16 * 4 - len(epal))
        idx[partial] = 239 + eidx
        for k in range(16):
            palette += epal[k * 4:k * 4 + 3]
            alphas.append(epal[k * 4 + 3])
    else:
        palette += [0] * 16 * 3
        alphas += [255] * 16
    idx[a == 0] = 255
    palette += [0, 0, 0]
    alphas.append(0)
    out = Image.frombytes("P", (idx.shape[1], idx.shape[0]), np.ascontiguousarray(idx).tobytes())
    out.putpalette(palette)
    out.info["transparency"] = bytes(alphas)
    return out


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
                q = quantize_rgba(im)
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
