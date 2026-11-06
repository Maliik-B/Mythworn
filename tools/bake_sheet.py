#!/usr/bin/env python3
"""Bakes a sprite sheet into the page look's one face: one value ramp, one ink outline, a rim from a
window at the upper left, and lapis on the one object that may carry it. A sheet goes in, a sprite set
comes out under assets/sprites/baked/<name>/ with the same file names, and the line for SPRITE_SETS
in combat_scene.gd is printed, ready to paste over the slot.

A sheet from a pack, with its strips found by name and its frames taken as square:

    python tools/bake_sheet.py caedmon "D:/somewhere/Ghost Warrior 4" --lapis-auto

Lapis goes on cloth or a shield only, never on skin or eyes, and only one object on a body carries it.
--lapis-auto takes the largest patch of the sheet's strongest colour, and prints what it took: look at
the result. To name it yourself, give the sheet's own colours:

    --lapis-blob "#6a6a67,#4f4e46"  the largest patch of them in each frame (a shield in grey armour)
    --lapis-blob "#1f3c88" --lapis-patches 2   the two largest (a tunic the belt cuts in two)
    --lapis-all "#1f3c88"           every pixel of these colours

Other options: --cell 184x137 for frames that are not square; --strip break=Plant.png:25:8 to name a
strip, with frame count and fps if they cannot be worked out; --preview out.png for a look at it.
--owned re-bakes every sheet the game already has, from the table below.
"""
import argparse
import colorsys
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_ROOT = os.path.join(ROOT, "assets", "sprites", "baked")


def h(s):
    s = s.strip().lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


RAMP = [h(x) for x in ("#1E1B18", "#2A2622", "#3D3A35", "#5A5750", "#6F7274", "#8C8676", "#CFC8B8")]
INK = h("#1E1B18")
LAPIS_RAMP = [h("#1A3274"), h("#1F3C88"), h("#2E55B8")]
LAPIS_RIM = 2

ALPHA_MIN = 32
BLOB_MIN = 12  # a patch smaller than this is a highlight, not an object
SKIN_HUES = (10.0, 62.0)
LOOK_FOR = (
    ("idle", r"^idle"),
    ("attack", r"^attack"),
    ("hit", r"^(take ?|get ?)?hit"),
    ("death", r"^death"),
)
DEFAULT_FPS = {"idle": 8, "attack": 18, "hit": 8, "death": 10, "break": 8}

# Every sheet the game has now. key: (source folder, cell, {state: file}, lapis colours, patches)
MONSTERS = "assets/sprites/enemies/monsters_main/Monsters_Creatures_Fantasy/"
OWNED = {
    "goblin": (MONSTERS + "Goblin", None, {}, [], 1),
    "skeleton": (MONSTERS + "Skeleton", None, {}, ["#6a6a67", "#4f4e46", "#83837b", "#8e8e8e"], 1),
    "flyingeye": (MONSTERS + "Flying eye", None, {"idle": "Flight.png"}, [], 1),
    "mushroom": (MONSTERS + "Mushroom", None, {}, [], 1),
    "worm": ("assets/sprites/enemies/fire_worm/Fire Worm/Sprites/Worm", None, {}, [], 1),
    "wizard2": ("assets/sprites/bosses/evil_wizard_2/EVil Wizard 2/Sprites", None, {}, [], 1),
    "medieval_warrior": ("assets/sprites/enemies/camelot/man_at_arms", (184, 137), {}, [], 1),
    "man_at_arms_whole": ("assets/sprites/enemies/camelot/man_at_arms_whole", (184, 137), {}, ["#1f3c88"], 2),
    "caedmon": ("assets/sprites/enemies/camelot/man_at_arms_whole", (184, 137), {}, ["#1f3c88"], 2),
}


def lum(c):
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def find_strips(source, named):
    files = sorted(f for f in os.listdir(source) if f.lower().endswith(".png"))
    strips = {}
    for state, pattern in LOOK_FOR:
        if state in named:
            continue
        for f in files:
            if re.match(pattern, f.lower()):
                strips[state] = {"file": f}
                break
    for state, spec in named.items():
        parts = spec.split(":")
        strips[state] = {"file": parts[0]}
        if len(parts) > 1:
            strips[state]["frames"] = int(parts[1])
        if len(parts) > 2:
            strips[state]["fps"] = int(parts[2])
    if "idle" not in strips:
        sys.exit("no idle strip found in %s (found %s); name it with --strip idle=File.png" % (source, files))
    return strips


def load_strips(source, strips, cell):
    for state, strip in strips.items():
        path = os.path.join(source, strip["file"])
        im = np.array(Image.open(path).convert("RGBA"))
        fh = cell[1] if cell else im.shape[0]
        fw = cell[0] if cell else im.shape[0]
        if im.shape[1] % fw != 0 or im.shape[0] != fh:
            sys.exit("%s is %dx%d, which is not whole frames of %dx%d; give --cell" % (
                strip["file"], im.shape[1], im.shape[0], fw, fh))
        strip["image"] = im
        strip["fw"], strip["fh"] = fw, fh
        strip["frames"] = strip.get("frames", im.shape[1] // fw)
        strip["fps"] = strip.get("fps", DEFAULT_FPS.get(state, 10))


def sheet_palette(strips):
    weights = {}
    for strip in strips.values():
        a = strip["image"]
        cols, counts = np.unique(a[a[..., 3] > ALPHA_MIN][:, :3], axis=0, return_counts=True)
        for c, n in zip(cols, counts):
            k = tuple(int(v) for v in c)
            weights[k] = weights.get(k, 0) + int(n)
    return weights


def ramp_index(colours, floor, ceil):
    """Each of the sheet's colours gets one place on the ramp, the same in every strip."""
    ls = np.array([lum(c) for c in colours])
    lo, hi = np.percentile(ls, 4), np.percentile(ls, 98)
    out = {}
    for c, l in zip(colours, ls):
        x = float(np.clip((l - lo) / max(1.0, hi - lo), 0, 1))
        out[c] = int(round(floor + (ceil - floor) * (x ** 0.9)))
    return out


def blobs(mask):
    seen = np.zeros_like(mask)
    found = []
    for y, x in zip(*np.where(mask)):
        if seen[y, x]:
            continue
        stack = [(y, x)]
        seen[y, x] = True
        comp = []
        while stack:
            cy, cx = stack.pop()
            comp.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1] and mask[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        found.append(comp)
    return found


def colour_mask(frame, wanted):
    mask = np.zeros(frame.shape[:2], dtype=bool)
    for c in wanted:
        mask |= (frame[..., 3] > ALPHA_MIN) & np.all(frame[..., :3] == c, axis=-1)
    return mask


def auto_lapis(strips, weights):
    """The sheet's strongest colour family that makes a real patch in the first idle frame."""
    families = {}
    for c, n in weights.items():
        hue, sat, val = colorsys.rgb_to_hsv(*(v / 255.0 for v in c))
        # Orange through yellow is skin, leather and gold: never lapis, even when it is the biggest.
        if sat > 0.25 and val > 0.12 and not SKIN_HUES[0] <= hue * 360.0 <= SKIN_HUES[1]:
            families.setdefault(int(hue * 12) % 12, []).append(c)
    strip = strips["idle"]
    frame = strip["image"][:strip["fh"], :strip["fw"]]
    best = []
    best_size = 0
    for colours in families.values():
        found = blobs(colour_mask(frame, colours))
        size = max((len(b) for b in found), default=0)
        if size > best_size:
            best, best_size = colours, size
    if best_size < BLOB_MIN:
        return []
    print("  --lapis-auto took %s, a patch of %d px. Check it is cloth or a shield." % (
        ",".join("#%02x%02x%02x" % c for c in best), best_size))
    return best


def bake_frame(frame, places, lapis_all, lapis_blob, patches, lapis_ranks):
    fh, fw = frame.shape[:2]
    solid = frame[..., 3] > ALPHA_MIN
    lapis = colour_mask(frame, lapis_all)
    if lapis_blob:
        found = sorted(blobs(colour_mask(frame, lapis_blob)), key=len, reverse=True)
        for patch in found[:patches]:
            if len(patch) >= BLOB_MIN:
                for y, x in patch:
                    lapis[y, x] = True
    up = np.zeros_like(solid)
    up[1:, :] = solid[:-1, :]
    up_left = np.zeros_like(solid)
    up_left[1:, 1:] = solid[:-1, :-1]
    lit = solid & (~up | ~up_left)
    out = np.zeros_like(frame)
    for y, x in zip(*np.where(solid)):
        c = tuple(int(v) for v in frame[y, x, :3])
        if lapis[y, x]:
            rank = LAPIS_RIM if lit[y, x] else lapis_ranks.get(c, 1)
            out[y, x, :3] = LAPIS_RAMP[rank]
        else:
            place = places[c]
            if lit[y, x]:
                place = min(place + 1, len(RAMP) - 1)
            out[y, x, :3] = RAMP[place]
        out[y, x, 3] = 255
    near = np.zeros_like(solid)
    near[1:, :] |= solid[:-1, :]
    near[:-1, :] |= solid[1:, :]
    near[:, 1:] |= solid[:, :-1]
    near[:, :-1] |= solid[:, 1:]
    edge = near & ~solid
    out[edge, :3] = INK
    out[edge, 3] = 255
    return out


def bake(name, source, cell, named, lapis_all, lapis_blob, patches, lapis_auto, floor, ceil, preview):
    strips = find_strips(source, named)
    load_strips(source, strips, cell)
    weights = sheet_palette(strips)
    colours = sorted(weights)
    places = ramp_index(colours, floor, ceil)
    if lapis_auto:
        found = auto_lapis(strips, weights)
        lapis_blob = found if not lapis_blob else lapis_blob
    # Within what may carry lapis, darker colours take the darker lapis.
    candidates = sorted(set(lapis_all) | set(lapis_blob), key=lum)
    lapis_ranks = {}
    for i, c in enumerate(candidates):
        lapis_ranks[c] = min(int(i * 2 / max(1, len(candidates) - 1)), 1) if len(candidates) > 1 else 1
    out_dir = os.path.join(OUT_ROOT, name)
    os.makedirs(out_dir, exist_ok=True)
    for strip in strips.values():
        fw, fh = strip["fw"], strip["fh"]
        src = strip["image"]
        out = np.zeros_like(src)
        for i in range(src.shape[1] // fw):
            out[:, i * fw:(i + 1) * fw] = bake_frame(src[:, i * fw:(i + 1) * fw], places, lapis_all, lapis_blob, patches, lapis_ranks)
        Image.fromarray(out, "RGBA").save(os.path.join(out_dir, strip["file"]))
    idle = strips["idle"]
    anims = ", ".join('"%s": ["%s", %d, %d]' % (s, strips[s]["file"], strips[s]["frames"], strips[s]["fps"]) for s in strips)
    res = "res://assets/sprites/baked/%s/" % name
    print("%s: %d colours, %d strips, %dx%d" % (name, len(colours), len(strips), idle["fw"], idle["fh"]))
    line = '"%s": {"dir": "%s", "baked": "%s", "lapis": %s, "fw": %d, "fh": %d, "anims": {%s}},' % (
        name, res, res, "true" if (lapis_all or lapis_blob) else "false", idle["fw"], idle["fh"], anims)
    if preview:
        im = Image.open(os.path.join(out_dir, idle["file"])).convert("RGBA").crop((0, 0, idle["fw"], idle["fh"]))
        scale = 4
        sheet = Image.new("RGBA", (idle["fw"] * scale, idle["fh"] * scale), h("#D3C9B1") + (255,))
        sheet.alpha_composite(im.resize(sheet.size, Image.NEAREST))
        sheet.convert("RGB").save(preview)
    return line


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name", nargs="?", help="the sprite set's key, and its folder under assets/sprites/baked/")
    ap.add_argument("source", nargs="?", help="the folder holding the sheet's PNG strips")
    ap.add_argument("--cell", help="frame size as WxH, when frames are not square")
    ap.add_argument("--strip", action="append", default=[], help="state=File.png[:frames[:fps]]")
    ap.add_argument("--lapis-all", default="", help="source colours that all become lapis")
    ap.add_argument("--lapis-blob", default="", help="source colours whose largest patch per frame becomes lapis")
    ap.add_argument("--lapis-patches", type=int, default=1, help="how many of the largest patches --lapis-blob takes")
    ap.add_argument("--lapis-auto", action="store_true", help="take the sheet's strongest colour; check the result")
    ap.add_argument("--floor", type=int, default=0, help="darkest ramp step to use, 0-6")
    ap.add_argument("--ceil", type=int, default=len(RAMP) - 1, help="lightest ramp step to use, 0-6")
    ap.add_argument("--preview", help="write a large first idle frame on the page colour to this path")
    ap.add_argument("--owned", action="store_true", help="re-bake every sheet in the table in this file")
    args = ap.parse_args()
    if args.owned:
        for name, (source, cell, named, lapis, patches) in OWNED.items():
            bake(name, os.path.join(ROOT, source), cell, dict(named), [], [h(c) for c in lapis], patches,
                False, args.floor, args.ceil, None)
        return
    if not args.name or not args.source:
        ap.error("give a name and a source folder, or --owned")
    cell = tuple(int(v) for v in args.cell.lower().split("x")) if args.cell else None
    named = dict(s.split("=", 1) for s in args.strip)
    line = bake(args.name, args.source, cell, named,
        [h(c) for c in args.lapis_all.split(",") if c], [h(c) for c in args.lapis_blob.split(",") if c],
        args.lapis_patches, args.lapis_auto, args.floor, args.ceil, args.preview)
    print("Paste this over the slot in SPRITE_SETS (combat_scene.gd), then run Godot's --import:")
    print("    " + line)


if __name__ == "__main__":
    main()
