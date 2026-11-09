#!/usr/bin/env python3
"""Bakes a prop rendered from a 3D model into the page look's one face, the way bake_sheet.py does a
character's strips: one value ramp, one ink outline, a rim from a window at the upper left, and an
accent ramp on what may carry one.

The model is rendered orthographic and transparent at SS times the art size, a value render and a
mask render (white where the accent material goes). This takes the render down to art pixels by
nearest neighbour, one sample from the middle of each SS block, so no pixel is a blend and no
colour is invented. Then:

    python tools/bake_prop.py sword_shaded_ss.png out.png --ss 8
    python tools/bake_prop.py scabbard_shaded_ss.png bare.png --ss 8 --mask scabbard_mask_ss.png \
        --rotate 90 --fittings ramp
    python tools/bake_prop.py scabbard_shaded_ss.png ornate.png --ss 8 --mask scabbard_mask_ss.png \
        --rotate 90 --body "#8A1C2B" --fittings "#D4A017"

--body and --fittings take an accent colour (a three-step ramp is made around it, darker, itself and
lighter) or `ramp` to stay on the page's neutral ramp. The same render gives the same silhouette and
the same shading under every colouring, so a bare and an ornate bake are one sprite.
--rotate turns it clockwise by 90, 180 or 270 degrees before the rim is cast, so the window stays at
the upper left whichever way the prop lies.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bake_sheet as bs  # noqa: E402

ALPHA_AT = 128


def reduce_nn(path, ss):
    im = np.array(Image.open(path).convert("RGBA"))
    return im[ss // 2::ss, ss // 2::ss]


def accent_ramp(spec):
    c = np.array(bs.h(spec), dtype=float)
    dark = tuple(int(v) for v in np.clip(c * 0.62, 0, 255))
    lit = tuple(int(v) for v in np.clip(c * 1.28 + 12, 0, 255))
    return [dark, tuple(int(v) for v in c), lit]


def bake(shaded, mask, body, fittings, floor, ceil):
    solid = shaded[..., 3] >= ALPHA_AT
    value = shaded[..., :3].astype(float).mean(axis=-1) / 255.0
    fit = (mask[..., 0] > 127) & solid if mask is not None else np.zeros_like(solid)
    up = np.zeros_like(solid)
    up[1:, :] = solid[:-1, :]
    up_left = np.zeros_like(solid)
    up_left[1:, 1:] = solid[:-1, :-1]
    lit = solid & (~up | ~up_left)

    lo, hi = value[solid].min(), value[solid].max()
    span = max(hi - lo, 1e-6)
    # Each distinct shade gets a place on the shared ramp, the same wherever it turns up.
    shades = np.unique(np.round(value[solid], 3))
    out = np.zeros(shaded.shape, dtype=np.uint8)
    body_ramp = None if body == "ramp" else accent_ramp(body)
    fit_ramp = None if fittings == "ramp" else accent_ramp(fittings)
    for y, x in zip(*np.where(solid)):
        t = (value[y, x] - lo) / span
        is_fit = fit[y, x]
        accent = fit_ramp if is_fit else body_ramp
        if accent is not None:
            rank = 2 if lit[y, x] else (1 if t > 0.5 else 0)
            out[y, x, :3] = accent[rank]
        else:
            place = int(round(floor + (ceil - floor) * t))
            if lit[y, x]:
                place = min(place + 1, len(bs.RAMP) - 1)
            out[y, x, :3] = bs.RAMP[place]
        out[y, x, 3] = 255
    near = np.zeros_like(solid)
    near[1:, :] |= solid[:-1, :]
    near[:-1, :] |= solid[1:, :]
    near[:, 1:] |= solid[:, :-1]
    near[:, :-1] |= solid[:, 1:]
    edge = near & ~solid
    out[edge, :3] = bs.INK
    out[edge, 3] = 255
    return out, len(shades)


def trim(a):
    ys, xs = np.where(a[..., 3] > 0)
    return a[ys.min():ys.max() + 1, xs.min():xs.max() + 1]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("shaded", help="the value render, at SS times art size")
    ap.add_argument("out", help="the baked PNG, trimmed to the prop and its ink")
    ap.add_argument("--ss", type=int, default=8, help="render size over art size")
    ap.add_argument("--mask", help="the mask render: white where the fittings are")
    ap.add_argument("--rotate", type=int, default=0, choices=(0, 90, 180, 270), help="clockwise, before the rim")
    ap.add_argument("--body", default="ramp", help="accent colour for the body, or ramp")
    ap.add_argument("--fittings", default="ramp", help="accent colour for the fittings, or ramp")
    ap.add_argument("--floor", type=int, default=2, help="darkest ramp step the prop uses, 0-6")
    ap.add_argument("--ceil", type=int, default=5, help="lightest ramp step before the rim, 0-6")
    args = ap.parse_args()
    shaded = reduce_nn(args.shaded, args.ss)
    mask = reduce_nn(args.mask, args.ss) if args.mask else None
    turns = (-args.rotate // 90) % 4  # np.rot90 turns counter-clockwise
    shaded = np.rot90(shaded, turns)
    mask = np.rot90(mask, turns) if mask is not None else None
    out, shades = bake(shaded, mask, args.body, args.fittings, args.floor, args.ceil)
    out = trim(out)
    Image.fromarray(out, "RGBA").save(args.out)
    print("%s: %dx%d art px, %d shades in the render" % (args.out, out.shape[1], out.shape[0], shades))


if __name__ == "__main__":
    main()
