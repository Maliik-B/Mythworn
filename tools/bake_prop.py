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

Pixel-perfect, from the same renders (the long axis must run top to bottom, so --clean comes before
--rotate does its turn):

    python tools/bake_prop.py sword_shaded_ss.png sword.png --ss 8 --clean
    python tools/bake_prop.py scabbard_shaded_ss.png ornate.png --ss 8 --mask scabbard_mask_ss.png         --rotate 90 --body "#8A1C2B" --fittings "#D4A017" --clean --fix tools/prop_fixes/scabbard.json

--body and --fittings take an accent colour (a three-step ramp is made around it, darker, itself and
lighter) or `ramp` to stay on the page's neutral ramp. The same render gives the same silhouette and
the same shading under every colouring, so a bare and an ornate bake are one sprite.

--clean makes the nearest-neighbour reduction a pixel-perfect sprite. A prop with a long straight axis
(a blade, a scabbard) is read as a stack of cross-sections and rebuilt: every row is centred on one
axis, its width snapped to the axis's parity (so the sprite is exactly mirror-symmetric), one-row
wobble in the width and one-row specks are smoothed away, equal-width rows are shaded alike so a
straight edge is exactly straight, shading is cut to a few flat bands, and the fittings become
whole-width bands with no orphan pixel. The outline is the ramp's own, cast around the result.
--fix takes a JSON file of hand corrections as data, keyed by long-axis row (before --rotate):
    {"width": {"13": 6}, "fit": {"4": true}, "drop": [0]}
`width` forces a row's fill width, `fit` forces a row in or out of the fittings, `drop` removes rows.
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


def _snap(w, parity):
    """The integer nearest w with the axis's parity, a tie going to the wider."""
    lo = int(np.floor(w))
    cands = [c for c in (lo - 1, lo, lo + 1, lo + 2) if c > 0 and c % 2 == parity]
    return min(cands, key=lambda c: (abs(c - w), -c))


def _runs(seq):
    out, start = [], 0
    for i in range(1, len(seq) + 1):
        if i == len(seq) or seq[i] != seq[start]:
            out.append((start, i - start, seq[start]))
            start = i
    return out


def clean(shaded, mask, ss_shaded, ss, fix, levels=6):
    """Rebuilds a prop with a vertical long axis as a symmetric stack of flat cross-sections.
    `shaded` and `mask` are the art-pixel reductions; `ss_shaded` the render at `ss` times, for sub-pixel widths."""
    fix = fix or {}
    solid = shaded[..., 3] >= ALPHA_AT
    ys, xs = np.where(solid)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    solid, shaded = solid[y0:y1, x0:x1], shaded[y0:y1, x0:x1]
    mask = mask[y0:y1, x0:x1] if mask is not None else None
    value = shaded[..., :3].astype(float).mean(axis=-1) / 255.0
    rows = solid.shape[0]

    # Sub-pixel width of each row from the render: the coverage of its art row, in art pixels.
    cover = (ss_shaded[..., 3] >= ALPHA_AT)
    width = np.array([cover[(y0 + r) * ss:(y0 + r + 1) * ss].sum() / float(ss * ss) for r in range(rows)])
    width = np.maximum(width, 1.0)

    # The axis's parity is the width most rows share, a lone guard row or a flare does not vote.
    counts = np.bincount(solid.sum(axis=1).astype(int))
    parity = int(np.argmax(counts)) % 2
    # The shaft is one width: the mean of the middle half of the length, snapped. A row clearly
    # wider than that (a collar, a ring, a guard) is a bulge and takes at least one step up; the
    # render's gentle taper is not stepped down, a straight object stays straight.
    mid = width[rows // 4: rows - rows // 4]
    shaft = float(mid.mean())
    base = _snap(shaft, parity)
    w = []
    for v in width:
        s = _snap(v, parity)
        w.append(max(s, base + 2) if v >= shaft + 0.6 else s)
    for k, v in (fix.get("width") or {}).items():
        w[int(k)] = int(v)
    # One-row specks and one-pixel-a-side wobble: a row that is not an extreme by two or more takes
    # the median of itself and its neighbours; a lone row between equal neighbours joins them.
    for _ in range(2):
        nw = list(w)
        for r in range(1, rows - 1):
            a, b, c = w[r - 1], w[r], w[r + 1]
            med = sorted((a, b, c))[1]
            if a == c and b != a and abs(b - a) <= 2:
                nw[r] = a
            elif abs(b - med) <= 2 and b != a and b != c:
                nw[r] = med
        w = nw
    keep = [r for r in range(rows) if r not in set(fix.get("drop") or [])]

    # The fittings, row by row: a majority of the row, then no lone row in or out.
    if mask is not None:
        fit = [bool((mask[r, :, 0] > 127)[solid[r]].mean() > 0.5) if solid[r].any() else False for r in range(rows)]
        for k, v in (fix.get("fit") or {}).items():
            fit[int(k)] = bool(v)
        for r in range(1, rows - 1):
            if fit[r - 1] == fit[r + 1] and fit[r] != fit[r - 1]:
                fit[r] = fit[r - 1]
    else:
        fit = [False] * rows

    # Flat shading: one cross-section profile for the body and one for the fittings, each the median
    # across all its rows of the render resampled to a fixed number of steps, then resampled to each
    # row's width. Rows of one width are shaded alike, so an edge is a straight line and the lit side
    # is the same side everywhere.
    PROF = 8
    prof = {}
    for kind in (False, True):
        samples = []
        for r in range(rows):
            if fit[r] != kind or not solid[r].any():
                continue
            cols = np.where(solid[r])[0]
            seg = value[r, cols]
            idx = np.minimum((np.arange(PROF) * len(seg) / PROF + len(seg) / (2.0 * PROF)).astype(int), len(seg) - 1)
            samples.append(seg[idx])
        if samples:
            prof[kind] = np.median(np.array(samples), axis=0)
    cw = max(w) + 2 + (max(w) + 2 + parity) % 2
    centre = cw / 2.0
    out_val = np.zeros((rows, cw))
    out_solid = np.zeros((rows, cw), dtype=bool)
    out_fit = np.zeros((rows, cw), dtype=bool)
    lo, hi = value[solid].min(), value[solid].max()
    for r in range(rows):
        wid, isfit = w[r], fit[r]
        p = prof.get(isfit, prof.get(not isfit))
        idx = np.minimum((np.arange(wid) * PROF / wid + PROF / (2.0 * wid)).astype(int), PROF - 1)
        left = int(round(centre - wid / 2.0))
        out_solid[r, left:left + wid] = True
        # A bulge (a guard, a ring, a locket) is a band across the shaft, one flat value.
        out_val[r, left:left + wid] = np.median(p) if wid > base else p[idx]
        out_fit[r, left:left + wid] = isfit
    # Cut the shading to a few flat bands, the same bands under every colouring.
    bands = np.round((out_val - lo) / max(hi - lo, 1e-6) * (levels - 1)) / (levels - 1)
    rowsel = np.array([r in set(keep) for r in range(rows)])
    img = np.zeros((rows, cw, 4), dtype=np.uint8)
    img[..., :3] = (bands[..., None] * 255).astype(np.uint8)
    img[..., 3] = np.where(out_solid, 255, 0)
    m = np.zeros((rows, cw, 4), dtype=np.uint8)
    m[..., 0] = np.where(out_fit, 255, 0)
    m[..., 3] = img[..., 3]
    pad = ((2, 2), (2, 2), (0, 0))
    return np.pad(img[rowsel], pad), np.pad(m[rowsel], pad)


def accent_ramp(spec):
    c = np.array(bs.h(spec), dtype=float)
    dark = tuple(int(v) for v in np.clip(c * 0.62, 0, 255))
    lit = tuple(int(v) for v in np.clip(c * 1.28 + 12, 0, 255))
    return [dark, tuple(int(v) for v in c), lit]


def bake(shaded, mask, body, fittings, floor, ceil, flat_rim=False):
    solid = shaded[..., 3] >= ALPHA_AT
    value = shaded[..., :3].astype(float).mean(axis=-1) / 255.0
    fit = (mask[..., 0] > 127) & solid if mask is not None else np.zeros_like(solid)
    up = np.zeros_like(solid)
    up[1:, :] = solid[:-1, :]
    up_left = np.zeros_like(solid)
    up_left[1:, 1:] = solid[:-1, :-1]
    left = np.zeros_like(solid)
    left[:, 1:] = solid[:, :-1]
    # A cleaned prop is lit on every top edge and every left edge, so a straight edge is one colour.
    lit = solid & (~up | ~left) if flat_rim else solid & (~up | ~up_left)
    if flat_rim:  # a highlight is a line: a lit pixel with no lit neighbour is just the corner of one
        nb = np.zeros_like(lit)
        nb[1:, :] |= lit[:-1, :]
        nb[:-1, :] |= lit[1:, :]
        nb[:, 1:] |= lit[:, :-1]
        nb[:, :-1] |= lit[:, 1:]
        lit &= nb

    lo, hi = value[solid].min(), value[solid].max()
    span = max(hi - lo, 1e-6)
    # Each distinct shade gets a place on the shared ramp, the same wherever it turns up.
    shades = np.unique(np.round(value[solid], 3))
    out = np.zeros(shaded.shape, dtype=np.uint8)
    lo_k = {k: value[solid & (fit == k)].min() for k in (False, True) if (solid & (fit == k)).any()}
    hi_k = {k: value[solid & (fit == k)].max() for k in (False, True) if (solid & (fit == k)).any()}
    body_ramp = None if body == "ramp" else accent_ramp(body)
    fit_ramp = None if fittings == "ramp" else accent_ramp(fittings)
    for y, x in zip(*np.where(solid)):
        t = (value[y, x] - lo) / span
        is_fit = fit[y, x]
        accent = fit_ramp if is_fit else body_ramp
        if accent is not None:
            tk = (value[y, x] - lo_k[bool(is_fit)]) / max(hi_k[bool(is_fit)] - lo_k[bool(is_fit)], 1e-6)
            rank = 2 if lit[y, x] else (1 if tk > 0.4 else 0)
            out[y, x, :3] = accent[rank]
        else:
            place = int(round(floor + (ceil - floor) * t))
            if lit[y, x]:
                place = min(ceil + 1 if flat_rim else place + 1, len(bs.RAMP) - 1)
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


def check(out):
    """Reports what pixel-perfect asks: a mirror-symmetric silhouette, no pixel alone in its colour,
    the page's ink for every outline pixel, and the palette's size."""
    solid = out[..., 3] > 0
    ink = (out[..., :3] == np.array(bs.INK)).all(axis=-1) & solid
    # The long axis is the longer side; symmetry is about the other.
    long_h = out.shape[1] > out.shape[0]
    sym = bool((solid == (solid[::-1] if long_h else solid[:, ::-1])).all())
    lone = 0
    for y, x in zip(*np.where(solid & ~ink)):
        same = False
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < out.shape[0] and 0 <= xx < out.shape[1] and solid[yy, xx] and (out[yy, xx] == out[y, x]).all():
                same = True
        lone += 0 if same else 1
    colours = len({tuple(c) for c in out[solid]})
    return "symmetric %s, lone pixels %d, %d colours (ink included)" % (sym, lone, colours)


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
    ap.add_argument("--clean", action="store_true", help="rebuild as a symmetric stack of flat cross-sections")
    ap.add_argument("--fix", help="JSON of hand corrections by long-axis row, see the top of this file")
    ap.add_argument("--floor", type=int, default=2, help="darkest ramp step the prop uses, 0-6")
    ap.add_argument("--ceil", type=int, default=5, help="lightest ramp step before the rim, 0-6")
    args = ap.parse_args()
    shaded = reduce_nn(args.shaded, args.ss)
    mask = reduce_nn(args.mask, args.ss) if args.mask else None
    if args.clean:
        import json
        fix = json.load(open(args.fix)) if args.fix else None
        render = np.array(Image.open(args.shaded).convert("RGBA"))
        shaded, mask = clean(shaded, mask, render, args.ss, fix)
    turns = (-args.rotate // 90) % 4  # np.rot90 turns counter-clockwise
    shaded = np.rot90(shaded, turns)
    mask = np.rot90(mask, turns) if mask is not None else None
    out, shades = bake(shaded, mask, args.body, args.fittings, args.floor, args.ceil, args.clean)
    out = trim(out)
    Image.fromarray(out, "RGBA").save(args.out)
    print("%s: %dx%d art px, %d shades in the render" % (args.out, out.shape[1], out.shape[0], shades))
    if args.clean:
        print("  " + check(out))


if __name__ == "__main__":
    main()
