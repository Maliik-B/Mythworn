"""Realm horizon-silhouette generator.

Produces 1920x320 horizontal-strip PNGs with transparent background, used as
the map's distant-horizon parallax layer. The silhouette gives the map real
depth: instead of a flat color, the player sees realm-iconic shapes
receding into haze at the bottom of the screen.

Sits BELOW the realm motif overlay in the map's layer stack but ABOVE the
solid bg color.

Usage: python realm_horizons.py [camelot|yggdrasil|jttw|all]
"""

from __future__ import annotations

import math
import os
import random
import sys

import cairo

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "art_drafts")
WIDTH, HEIGHT = 1920, 320


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def _new_surface() -> tuple[cairo.ImageSurface, cairo.Context]:
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
    ctx = cairo.Context(surface)
    return surface, ctx


def _atmospheric_fade(ctx: cairo.Context, fill: tuple[float, float, float],
                       alpha_top: float = 0.0,
                       alpha_bottom: float = 0.0,
                       y_start: float = 0.0,
                       y_end: float | None = None) -> None:
    """Apply a vertical alpha gradient to the silhouette to suggest receding
    atmospheric haze. The silhouette is more opaque at the bottom (close to
    the viewer) and fades toward the top (further away in the sky).
    """
    if y_end is None:
        y_end = HEIGHT
    grad = cairo.LinearGradient(0, y_start, 0, y_end)
    grad.add_color_stop_rgba(0.0, *fill, alpha_top)
    grad.add_color_stop_rgba(1.0, *fill, alpha_bottom)
    ctx.set_source(grad)
    ctx.rectangle(0, 0, WIDTH, HEIGHT)
    ctx.fill()


# ---------------------------------------------------------------------------
# Camelot: distant castle skyline
# ---------------------------------------------------------------------------

CAMELOT_SILHOUETTE = (0.10, 0.06, 0.06)
CAMELOT_HAZE = (0.38, 0.14, 0.12)


def generate_camelot(out_path: str) -> str:
    surface, ctx = _new_surface()

    # Far background: atmospheric haze gradient, slight warm dusk tint
    _atmospheric_fade(ctx, CAMELOT_HAZE, alpha_top=0.0, alpha_bottom=0.18)

    # ----- Distant city silhouette (back layer, slightly hazed) -----
    rng = random.Random(42)
    ctx.set_source_rgba(*CAMELOT_SILHOUETTE, 0.45)
    ground_y = HEIGHT * 0.78
    # Series of rooftops/walls with occasional spires
    x = -20
    while x < WIDTH + 20:
        building_w = rng.randint(40, 100)
        building_h = rng.randint(50, 110)
        ctx.rectangle(x, ground_y - building_h, building_w, building_h + 30)
        ctx.fill()
        # Occasional spire
        if rng.random() < 0.30:
            spire_x = x + building_w / 2
            spire_h = building_h + rng.randint(40, 90)
            ctx.move_to(spire_x - 8, ground_y - building_h)
            ctx.line_to(spire_x + 8, ground_y - building_h)
            ctx.line_to(spire_x, ground_y - spire_h)
            ctx.close_path()
            ctx.fill()
        x += building_w - rng.randint(6, 14)  # slight overlap

    # ----- Mid-ground keep & towers (more opaque) -----
    ctx.set_source_rgba(*CAMELOT_SILHOUETTE, 0.85)
    keep_cx = WIDTH * 0.62
    keep_base_y = HEIGHT * 0.92
    keep_w = 280
    keep_h = 150
    ctx.rectangle(keep_cx - keep_w / 2, keep_base_y - keep_h, keep_w, keep_h + 30)
    ctx.fill()
    # Crenellations on the keep
    for i in range(7):
        x_pos = keep_cx - keep_w / 2 + i * (keep_w / 7) + 6
        ctx.rectangle(x_pos, keep_base_y - keep_h - 16, keep_w / 7 - 12, 16)
        ctx.fill()
    # Central tower
    tower_w = 60
    tower_h = 260
    ctx.rectangle(keep_cx - tower_w / 2, keep_base_y - tower_h, tower_w, tower_h + 30)
    ctx.fill()
    # Tower spire
    ctx.move_to(keep_cx - tower_w / 2 - 8, keep_base_y - tower_h)
    ctx.line_to(keep_cx + tower_w / 2 + 8, keep_base_y - tower_h)
    ctx.line_to(keep_cx, keep_base_y - tower_h - 60)
    ctx.close_path()
    ctx.fill()
    # Flanking towers
    for sign in (-1, 1):
        sx = keep_cx + sign * (keep_w / 2 + 30)
        ctx.rectangle(sx - 24, keep_base_y - 200, 48, 230)
        ctx.fill()
        ctx.move_to(sx - 30, keep_base_y - 200)
        ctx.line_to(sx + 30, keep_base_y - 200)
        ctx.line_to(sx, keep_base_y - 240)
        ctx.close_path()
        ctx.fill()

    # ----- Foreground rolling hills / ground sweep -----
    ctx.set_source_rgba(*CAMELOT_SILHOUETTE, 0.95)
    ctx.move_to(0, HEIGHT)
    ctx.line_to(0, HEIGHT * 0.88)
    # Gentle wave along the bottom
    for x in range(0, WIDTH + 1, 50):
        y = HEIGHT * 0.88 + math.sin(x * 0.008) * 6 - 4
        ctx.line_to(x, y)
    ctx.line_to(WIDTH, HEIGHT)
    ctx.close_path()
    ctx.fill()

    surface.write_to_png(out_path)
    return out_path


# ---------------------------------------------------------------------------
# Yggdrasil: jagged mountains with distant world-tree silhouette
# ---------------------------------------------------------------------------

YGGDRASIL_SILHOUETTE = (0.10, 0.14, 0.22)
YGGDRASIL_HAZE = (0.20, 0.32, 0.50)


def generate_yggdrasil(out_path: str) -> str:
    surface, ctx = _new_surface()

    # Cold haze gradient
    _atmospheric_fade(ctx, YGGDRASIL_HAZE, alpha_top=0.0, alpha_bottom=0.20)

    # ----- Far mountain range (low alpha, distant) -----
    rng = random.Random(7)
    ctx.set_source_rgba(*YGGDRASIL_SILHOUETTE, 0.35)
    base_y = HEIGHT * 0.82
    ctx.move_to(0, HEIGHT)
    ctx.line_to(0, base_y)
    x = 0
    while x < WIDTH:
        peak_w = rng.randint(80, 180)
        peak_h = rng.randint(40, 110)
        ctx.line_to(x + peak_w / 2, base_y - peak_h)
        ctx.line_to(x + peak_w, base_y)
        x += peak_w
    ctx.line_to(WIDTH, HEIGHT)
    ctx.close_path()
    ctx.fill()

    # World-tree silhouette removed: at horizon-strip resolution it
    # reads as a glitch shape rather than a tree. Better to let the mountains
    # carry the realm identity at this scale.

    # ----- Standing-stone monolith: Norse focal element nestled in the peaks -----
    # A solitary tall rectangular stone with two small "arms" near the top
    # suggesting carved runes. Sits between the far and mid mountain layers.
    stone_x = WIDTH * 0.34
    stone_base = HEIGHT * 0.88
    stone_h = 175
    stone_w = 30
    ctx.set_source_rgba(*YGGDRASIL_SILHOUETTE, 0.78)
    # Main slab: slightly trapezoidal (wider at bottom)
    ctx.move_to(stone_x - stone_w * 0.5, stone_base - stone_h)
    ctx.line_to(stone_x + stone_w * 0.5, stone_base - stone_h)
    ctx.line_to(stone_x + stone_w * 0.7, stone_base)
    ctx.line_to(stone_x - stone_w * 0.7, stone_base)
    ctx.close_path()
    ctx.fill()
    # Top "arms": slight notches at the top corners suggesting a megalith
    arm_w = stone_w * 0.45
    arm_h = stone_h * 0.10
    ctx.rectangle(stone_x - stone_w * 0.5 - arm_w, stone_base - stone_h,
                  arm_w, arm_h)
    ctx.fill()
    ctx.rectangle(stone_x + stone_w * 0.5, stone_base - stone_h,
                  arm_w, arm_h)
    ctx.fill()
    # Faint rune-carving on the front, a single vertical line + cross-bar
    ctx.set_source_rgba(0.55, 0.78, 0.95, 0.40)
    ctx.set_line_width(2.0)
    ctx.move_to(stone_x, stone_base - stone_h * 0.85)
    ctx.line_to(stone_x, stone_base - stone_h * 0.25)
    ctx.stroke()
    ctx.move_to(stone_x - stone_w * 0.3, stone_base - stone_h * 0.55)
    ctx.line_to(stone_x + stone_w * 0.3, stone_base - stone_h * 0.55)
    ctx.stroke()

    # ----- Mid-ground mountains (more opaque, sharper peaks) -----
    ctx.set_source_rgba(*YGGDRASIL_SILHOUETTE, 0.75)
    base_y = HEIGHT * 0.92
    ctx.move_to(0, HEIGHT)
    ctx.line_to(0, base_y)
    x = -30
    while x < WIDTH + 30:
        peak_w = rng.randint(120, 240)
        peak_h = rng.randint(70, 170)
        # Asymmetric peak: taller on one side
        ctx.line_to(x + peak_w * 0.4, base_y - peak_h)
        ctx.line_to(x + peak_w, base_y)
        x += peak_w * 0.7  # overlap
    ctx.line_to(WIDTH, HEIGHT)
    ctx.close_path()
    ctx.fill()

    # ----- Snow-cap highlight: small accent stroke at each peak's summit -----
    # The previous version drew the full peak outline as the highlight, which
    # produced a zigzag wireframe artifact across the whole image. Now we
    # draw only a SHORT "V" at the summit so it reads as a snowy cap.
    ctx.set_source_rgba(0.78, 0.88, 1.0, 0.40)
    ctx.set_line_width(2.0)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    x = -30
    rng2 = random.Random(7)
    base_y = HEIGHT * 0.92
    while x < WIDTH + 30:
        peak_w = rng2.randint(120, 240)
        peak_h = rng2.randint(70, 170)
        summit_x = x + peak_w * 0.4
        summit_y = base_y - peak_h
        # Tiny V at the summit, left edge to apex to right edge
        ctx.move_to(summit_x - peak_w * 0.06, summit_y + peak_h * 0.12)
        ctx.line_to(summit_x, summit_y)
        ctx.line_to(summit_x + peak_w * 0.06, summit_y + peak_h * 0.12)
        ctx.stroke()
        x += peak_w * 0.7

    surface.write_to_png(out_path)
    return out_path


# ---------------------------------------------------------------------------
# Journey to the West: layered misty mountain peaks
# ---------------------------------------------------------------------------

# Less-saturated silhouette so it reads as "blue-green mountain" rather than
# "green foliage." East-Asian landscape painting often uses very dark
# blue-greens for distant peaks.
JTTW_SILHOUETTE = (0.08, 0.16, 0.14)
JTTW_HAZE = (0.32, 0.50, 0.42)


def _jttw_peak_path(ctx: cairo.Context, x: float, peak_w: float, peak_h: float,
                     base_y: float, lean: float) -> None:
    """Sharp asymmetric mountain peak in the style of classical Chinese
    landscape painting. The summit is a point, not a curve. The two flanks
    curve in slightly toward the summit, suggesting brush-stroke geometry.

    `lean` in [-0.5, 0.5] shifts the summit horizontally for asymmetry.
    """
    summit_x = x + peak_w * (0.5 + lean)
    summit_y = base_y - peak_h
    # Left flank: slight inward curve toward the summit
    ctx.curve_to(x + peak_w * 0.15, base_y - peak_h * 0.30,
                 x + peak_w * (0.30 + lean * 0.6), base_y - peak_h * 0.75,
                 summit_x, summit_y)
    # Right flank: slight inward curve from the summit
    ctx.curve_to(x + peak_w * (0.70 + lean * 0.6), base_y - peak_h * 0.75,
                 x + peak_w * 0.85, base_y - peak_h * 0.30,
                 x + peak_w, base_y)


def _draw_distant_pagoda(ctx: cairo.Context, cx: float, base_y: float,
                          height: float, alpha: float) -> None:
    """Small distant pagoda silhouette, 3 tiered roofs with a thin spire.
    Used as a focal element in the JttW horizon, nestled among the peaks.
    """
    ctx.set_source_rgba(*JTTW_SILHOUETTE, alpha)
    # Stacked roofs (3 tiers), each narrower than the one below
    tier_w_base = height * 0.45
    y = base_y
    for i in range(3):
        tier_w = tier_w_base * (1.0 - i * 0.18)
        tier_body_h = height * 0.10
        tier_roof_h = height * 0.06
        overhang = tier_w * 0.18
        # Body
        ctx.rectangle(cx - tier_w / 2, y - tier_body_h, tier_w, tier_body_h)
        ctx.fill()
        # Roof: trapezoid with overhang
        ctx.move_to(cx - tier_w / 2 - overhang, y - tier_body_h)
        ctx.line_to(cx + tier_w / 2 + overhang, y - tier_body_h)
        ctx.line_to(cx + tier_w / 2 * 0.85, y - tier_body_h - tier_roof_h)
        ctx.line_to(cx - tier_w / 2 * 0.85, y - tier_body_h - tier_roof_h)
        ctx.close_path()
        ctx.fill()
        y -= tier_body_h + tier_roof_h
    # Crowning spire
    ctx.move_to(cx - 2, y)
    ctx.line_to(cx + 2, y)
    ctx.line_to(cx, y - height * 0.08)
    ctx.close_path()
    ctx.fill()


def generate_jttw(out_path: str) -> str:
    surface, ctx = _new_surface()

    # Jade-tinted mist gradient
    _atmospheric_fade(ctx, JTTW_HAZE, alpha_top=0.0, alpha_bottom=0.18)

    # Pre-pick positions for dominant "lonely peaks" that punch through the
    # ridgeline at irregular intervals. These give the silhouette focal points
    # the eye can rest on, instead of a uniform texture wall.
    rng = random.Random(13)
    lonely_xs = [
        WIDTH * 0.18,
        WIDTH * 0.52,
        WIDTH * 0.83,
    ]

    # ----- Three layers of misty peaks at decreasing distance -----
    for layer_idx, (alpha, base_ratio, peak_h_range, peak_w_range,
                     lonely_h_mult, draw_lonely) in enumerate([
        (0.30, 0.70, (110, 200), (160, 280), 1.20, False),  # Far: short and stubby
        (0.58, 0.84, (160, 260), (140, 240), 1.30, True),   # Mid: focal "lonely peaks" here
        (0.88, 0.97, (190, 300), (130, 220), 1.55, True),   # Near: tallest focal peaks
    ]):
        ctx.set_source_rgba(*JTTW_SILHOUETTE, alpha)
        base_y = HEIGHT * base_ratio
        ctx.move_to(0, HEIGHT)
        ctx.line_to(0, base_y)
        x = -40
        while x < WIDTH + 40:
            peak_w = rng.randint(*peak_w_range)
            peak_h = rng.randint(*peak_h_range)
            lean = (rng.random() - 0.5) * 0.4

            # If a lonely peak position falls inside this run, replace this
            # regular peak with a taller, narrower dramatic one centered on it.
            for lx in lonely_xs:
                if draw_lonely and x <= lx < x + peak_w:
                    peak_w = int(peak_w * 0.85)
                    peak_h = int(peak_h * lonely_h_mult)
                    lean = (lx - (x + peak_w / 2)) / peak_w * 1.6  # bias toward target
                    lean = max(-0.45, min(0.45, lean))
                    break

            _jttw_peak_path(ctx, x, peak_w, peak_h, base_y, lean)
            x += peak_w * 0.55
        ctx.line_to(WIDTH, HEIGHT)
        ctx.close_path()
        ctx.fill()

        # After the FAR layer, draw distant pagodas peeking through the mist
        # at horizon-line depth. They'll sit between the far and mid peaks.
        if layer_idx == 0:
            _draw_distant_pagoda(ctx, WIDTH * 0.30, HEIGHT * 0.78, 110, 0.50)
            _draw_distant_pagoda(ctx, WIDTH * 0.72, HEIGHT * 0.78, 95, 0.45)

        # Mist band between this layer and the next, pale jade haze
        if layer_idx < 2:
            mist = cairo.LinearGradient(0, base_y - 30, 0, base_y + 50)
            mist.add_color_stop_rgba(0.0, 0.78, 0.90, 0.84, 0.0)
            mist.add_color_stop_rgba(0.5, 0.78, 0.90, 0.84, 0.38)
            mist.add_color_stop_rgba(1.0, 0.78, 0.90, 0.84, 0.0)
            ctx.set_source(mist)
            ctx.rectangle(0, base_y - 30, WIDTH, 80)
            ctx.fill()

    surface.write_to_png(out_path)
    return out_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    targets = sys.argv[1:] or ["all"]
    if "all" in targets or "camelot" in targets:
        path = generate_camelot(os.path.join(OUT_DIR, "horizon_camelot.png"))
        print("camelot:   ", path)
    if "all" in targets or "yggdrasil" in targets:
        path = generate_yggdrasil(os.path.join(OUT_DIR, "horizon_yggdrasil.png"))
        print("yggdrasil: ", path)
    if "all" in targets or "jttw" in targets:
        path = generate_jttw(os.path.join(OUT_DIR, "horizon_jttw.png"))
        print("jttw:      ", path)


if __name__ == "__main__":
    main()
