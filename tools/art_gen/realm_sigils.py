"""Realm sigil generator.

Produces 512x512 stylized emblem PNGs for each realm, used as corner badges
on the map header. PyCairo throughout for clean curves and AA edges.

Usage: python realm_sigils.py [camelot|yggdrasil|jttw|all]
"""

from __future__ import annotations

import math
import os
import sys

import cairo

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "art_drafts")
SIZE = 512


# ---------------------------------------------------------------------------
# Camelot
# ---------------------------------------------------------------------------

YGGDRASIL_PALETTE = {
    "bg_outer": (0.04, 0.06, 0.12),
    "ring_outer": (0.40, 0.55, 0.78),
    "ring_inner": (0.18, 0.30, 0.50),
    "ring_hi": (0.78, 0.88, 1.00),
    "trunk": (0.18, 0.16, 0.20),
    "trunk_hi": (0.32, 0.32, 0.42),
    "branch": (0.20, 0.18, 0.22),
    "leaf_glow": (0.55, 0.78, 0.95),
    "leaf_glow_hi": (0.85, 0.95, 1.00),
    "rune": (0.78, 0.88, 1.00),
    "ink": (0.06, 0.08, 0.12),
}

JTTW_PALETTE = {
    "bg_outer": (0.04, 0.08, 0.06),
    "pagoda_body": (0.55, 0.18, 0.18),
    "pagoda_body_hi": (0.72, 0.28, 0.24),
    "pagoda_roof": (0.20, 0.10, 0.10),
    "pagoda_roof_hi": (0.35, 0.18, 0.16),
    # Pale jade-tinted mist for cloud forms, light enough to read as cloud,
    # tinted enough to stay in the realm's palette.
    "cloud": (0.78, 0.88, 0.82),
    "cloud_hi": (0.96, 0.98, 0.94),
    "cloud_dark": (0.48, 0.62, 0.55),
    "spire": (0.92, 0.74, 0.22),
    "ink": (0.06, 0.10, 0.06),
}


CAMELOT_PALETTE = {
    "bg_outer": (0.10, 0.06, 0.07),
    "shield_face": (0.55, 0.10, 0.10),
    "shield_face_hi": (0.72, 0.18, 0.16),
    "shield_border": (0.85, 0.65, 0.20),
    "shield_border_hi": (1.0, 0.85, 0.35),
    "shield_shadow": (0.06, 0.02, 0.02),
    "gold": (0.92, 0.74, 0.22),
    "gold_hi": (1.0, 0.92, 0.55),
    "gold_dark": (0.55, 0.40, 0.08),
    "ink": (0.10, 0.06, 0.04),
}


def _shield_path(ctx: cairo.Context, cx: float, cy: float,
                 width: float, height: float) -> None:
    """Heater-shield silhouette: curved shoulders at top, pointed tip at bottom."""
    half_w = width / 2.0
    # Top corners with rounded shoulder
    ctx.move_to(cx - half_w, cy - height / 2.0)
    ctx.line_to(cx + half_w, cy - height / 2.0)
    # Right shoulder curves down
    ctx.curve_to(
        cx + half_w, cy - height * 0.15,           # control 1
        cx + half_w * 0.85, cy + height * 0.15,    # control 2
        cx + half_w * 0.55, cy + height * 0.35,    # end
    )
    # Right flank to point
    ctx.curve_to(
        cx + half_w * 0.30, cy + height * 0.45,
        cx + half_w * 0.10, cy + height * 0.49,
        cx, cy + height * 0.50,
    )
    # Left flank from point
    ctx.curve_to(
        cx - half_w * 0.10, cy + height * 0.49,
        cx - half_w * 0.30, cy + height * 0.45,
        cx - half_w * 0.55, cy + height * 0.35,
    )
    # Left shoulder
    ctx.curve_to(
        cx - half_w * 0.85, cy + height * 0.15,
        cx - half_w, cy - height * 0.15,
        cx - half_w, cy - height / 2.0,
    )
    ctx.close_path()


def _crown_path(ctx: cairo.Context, cx: float, cy: float, w: float, h: float) -> None:
    """Simple stylized crown: flat band with three points (tall center, two flanking)."""
    half_w = w / 2.0
    base_y = cy + h * 0.40
    band_top = cy + h * 0.10
    ctx.move_to(cx - half_w, base_y)
    ctx.line_to(cx - half_w, band_top)
    # Left peak
    ctx.line_to(cx - half_w * 0.55, band_top - h * 0.30)
    ctx.line_to(cx - half_w * 0.20, band_top)
    # Center peak (tallest)
    ctx.line_to(cx, band_top - h * 0.55)
    ctx.line_to(cx + half_w * 0.20, band_top)
    # Right peak
    ctx.line_to(cx + half_w * 0.55, band_top - h * 0.30)
    ctx.line_to(cx + half_w, band_top)
    ctx.line_to(cx + half_w, base_y)
    ctx.close_path()


def _draw_cross_greek(ctx: cairo.Context, cx: float, cy: float, size: float,
                       fill: tuple[float, float, float]) -> None:
    """Clean Greek cross: equal arms, straight edges, slight inset at intersection.

    `size` is the half-length of each arm (so total cross spans 2*size).
    """
    s = size
    bar = s * 0.30  # arm thickness
    ctx.move_to(cx - bar, cy - s)
    ctx.line_to(cx + bar, cy - s)
    ctx.line_to(cx + bar, cy - bar)
    ctx.line_to(cx + s, cy - bar)
    ctx.line_to(cx + s, cy + bar)
    ctx.line_to(cx + bar, cy + bar)
    ctx.line_to(cx + bar, cy + s)
    ctx.line_to(cx - bar, cy + s)
    ctx.line_to(cx - bar, cy + bar)
    ctx.line_to(cx - s, cy + bar)
    ctx.line_to(cx - s, cy - bar)
    ctx.line_to(cx - bar, cy - bar)
    ctx.close_path()
    ctx.set_source_rgb(*fill)
    ctx.fill_preserve()
    ctx.set_source_rgba(0.10, 0.06, 0.04, 0.65)
    ctx.set_line_width(2.0)
    ctx.stroke()


def _draw_fleur_de_lis(ctx: cairo.Context, cx: float, cy: float, size: float,
                        fill: tuple[float, float, float]) -> None:
    """Stylized fleur-de-lis: three petals (tall center, two flanking) with a
    binding band at the lower third. `size` is roughly the half-height of the
    overall shape.
    """
    s = size

    # Central petal: pointed almond shape
    ctx.move_to(cx, cy - s)                                 # top point
    ctx.curve_to(cx + s * 0.18, cy - s * 0.65,
                 cx + s * 0.18, cy - s * 0.15,
                 cx, cy + s * 0.20)                          # right curve to mid
    ctx.curve_to(cx - s * 0.18, cy - s * 0.15,
                 cx - s * 0.18, cy - s * 0.65,
                 cx, cy - s)                                  # left curve back to top
    ctx.close_path()
    ctx.set_source_rgb(*fill)
    ctx.fill()

    # Side petals: curling outward and downward
    for sign in (-1, 1):
        ctx.move_to(cx, cy - s * 0.30)                       # tucked against center top
        ctx.curve_to(cx + sign * s * 0.10, cy - s * 0.45,
                     cx + sign * s * 0.55, cy - s * 0.65,
                     cx + sign * s * 0.85, cy - s * 0.05)     # outer top tip
        ctx.curve_to(cx + sign * s * 0.90, cy + s * 0.25,
                     cx + sign * s * 0.40, cy + s * 0.20,
                     cx + sign * s * 0.10, cy + s * 0.15)     # back to center
        ctx.curve_to(cx + sign * s * 0.05, cy + s * 0.05,
                     cx, cy - s * 0.10,
                     cx, cy - s * 0.30)
        ctx.close_path()
        ctx.set_source_rgb(*fill)
        ctx.fill()

    # Lower stem: sweeps below the binding band
    ctx.move_to(cx - s * 0.14, cy + s * 0.20)
    ctx.line_to(cx + s * 0.14, cy + s * 0.20)
    ctx.curve_to(cx + s * 0.10, cy + s * 0.60,
                 cx + s * 0.20, cy + s * 0.80,
                 cx, cy + s * 0.90)
    ctx.curve_to(cx - s * 0.20, cy + s * 0.80,
                 cx - s * 0.10, cy + s * 0.60,
                 cx - s * 0.14, cy + s * 0.20)
    ctx.close_path()
    ctx.set_source_rgb(*fill)
    ctx.fill()

    # Binding band across the middle, slightly darker for separation
    band_y = cy + s * 0.20
    band_h = s * 0.18
    ctx.rectangle(cx - s * 0.80, band_y - band_h / 2.0, s * 1.60, band_h)
    band_color = (fill[0] * 0.75, fill[1] * 0.70, fill[2] * 0.45)
    ctx.set_source_rgb(*band_color)
    ctx.fill()
    # Highlight stripe along the top of the band
    ctx.set_source_rgba(1.0, 0.95, 0.7, 0.5)
    ctx.set_line_width(1.5)
    ctx.move_to(cx - s * 0.78, band_y - band_h * 0.40)
    ctx.line_to(cx + s * 0.78, band_y - band_h * 0.40)
    ctx.stroke()

    # Outline the whole figure with a thin ink stroke for crispness
    ctx.set_source_rgba(0.10, 0.06, 0.04, 0.55)
    ctx.set_line_width(1.5)


def generate_camelot(out_path: str, emblem: str = "cross") -> str:
    """`emblem` may be 'cross' (Greek cross) or 'fleur' (fleur-de-lis)."""
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
    ctx = cairo.Context(surface)
    p = CAMELOT_PALETTE

    # Subtle dark circular background, gentler than v1 so it reads as halo, not disc
    bg_grad = cairo.RadialGradient(SIZE / 2, SIZE / 2, SIZE * 0.05,
                                    SIZE / 2, SIZE / 2, SIZE * 0.55)
    bg_grad.add_color_stop_rgba(0.0, *p["bg_outer"], 0.0)
    bg_grad.add_color_stop_rgba(0.65, *p["bg_outer"], 0.45)
    bg_grad.add_color_stop_rgba(1.0, *p["bg_outer"], 0.0)
    ctx.set_source(bg_grad)
    ctx.paint()

    # ----- Crown above shield -----
    crown_cx = SIZE / 2.0
    crown_cy = SIZE * 0.18
    crown_w = SIZE * 0.50
    crown_h = SIZE * 0.26

    # Crown shadow
    ctx.save()
    ctx.translate(4, 4)
    _crown_path(ctx, crown_cx, crown_cy, crown_w, crown_h)
    ctx.set_source_rgba(0, 0, 0, 0.55)
    ctx.fill()
    ctx.restore()

    # Crown body
    _crown_path(ctx, crown_cx, crown_cy, crown_w, crown_h)
    crown_grad = cairo.LinearGradient(crown_cx, crown_cy - crown_h * 0.5,
                                       crown_cx, crown_cy + crown_h * 0.5)
    crown_grad.add_color_stop_rgb(0.0, *p["gold_hi"])
    crown_grad.add_color_stop_rgb(0.55, *p["gold"])
    crown_grad.add_color_stop_rgb(1.0, *p["gold_dark"])
    ctx.set_source(crown_grad)
    ctx.fill_preserve()
    ctx.set_source_rgba(*p["ink"], 0.85)
    ctx.set_line_width(3)
    ctx.stroke()

    # Three jewels on the crown band
    for i, jx in enumerate([crown_cx - crown_w * 0.25, crown_cx, crown_cx + crown_w * 0.25]):
        jy = crown_cy + crown_h * 0.20
        # red gem
        ctx.set_source_rgb(0.85, 0.18, 0.18)
        ctx.arc(jx, jy, 7, 0, 2 * math.pi)
        ctx.fill()
        # highlight
        ctx.set_source_rgba(1.0, 0.85, 0.85, 0.7)
        ctx.arc(jx - 2, jy - 2, 2.5, 0, 2 * math.pi)
        ctx.fill()

    # ----- Shield -----
    shield_cx = SIZE / 2.0
    shield_cy = SIZE * 0.58
    shield_w = SIZE * 0.62
    shield_h = SIZE * 0.66

    # Shield shadow
    ctx.save()
    ctx.translate(5, 6)
    _shield_path(ctx, shield_cx, shield_cy, shield_w, shield_h)
    ctx.set_source_rgba(0, 0, 0, 0.55)
    ctx.fill()
    ctx.restore()

    # Shield face fill
    _shield_path(ctx, shield_cx, shield_cy, shield_w, shield_h)
    face_grad = cairo.RadialGradient(shield_cx, shield_cy - shield_h * 0.1,
                                      shield_w * 0.05,
                                      shield_cx, shield_cy, shield_w * 0.55)
    face_grad.add_color_stop_rgb(0.0, *p["shield_face_hi"])
    face_grad.add_color_stop_rgb(1.0, *p["shield_face"])
    ctx.set_source(face_grad)
    ctx.fill_preserve()

    # Shield gold border: thick outer + thin inner line for depth
    ctx.set_source_rgb(*p["shield_border"])
    ctx.set_line_width(10)
    ctx.stroke()
    _shield_path(ctx, shield_cx, shield_cy, shield_w, shield_h)
    ctx.set_source_rgba(*p["shield_border_hi"], 0.8)
    ctx.set_line_width(3)
    ctx.stroke()

    # Inner border line: ink, just inside the gold
    _shield_path(ctx, shield_cx, shield_cy, shield_w * 0.94, shield_h * 0.94)
    ctx.set_source_rgba(*p["ink"], 0.45)
    ctx.set_line_width(1.5)
    ctx.stroke()

    # ----- Central emblem on the shield face -----
    if emblem == "cross":
        # Drop shadow
        _draw_cross_greek(ctx, shield_cx + 2, shield_cy + 2 + shield_h * 0.02,
                          shield_w * 0.28, (0.10, 0.04, 0.04))
        # Main cross
        _draw_cross_greek(ctx, shield_cx, shield_cy + shield_h * 0.02,
                          shield_w * 0.28, p["gold"])
    elif emblem == "fleur":
        # Drop shadow
        _draw_fleur_de_lis(ctx, shield_cx + 2, shield_cy + 2 + shield_h * 0.02,
                           shield_w * 0.30, (0.10, 0.04, 0.04))
        # Main fleur
        _draw_fleur_de_lis(ctx, shield_cx, shield_cy + shield_h * 0.02,
                           shield_w * 0.30, p["gold"])
        # Highlight pass (slightly smaller, brighter gold offset up-left)
        _draw_fleur_de_lis(ctx, shield_cx - 1, shield_cy - 1 + shield_h * 0.02,
                           shield_w * 0.30 * 0.92, p["gold_hi"])
    else:
        raise ValueError(f"unknown emblem: {emblem}")

    surface.write_to_png(out_path)
    return out_path


# ---------------------------------------------------------------------------
# Yggdrasil: World Tree inside a runic circle
# ---------------------------------------------------------------------------

def _draw_runic_ring(ctx: cairo.Context, cx: float, cy: float, r_outer: float,
                      r_inner: float, p: dict) -> None:
    """Two concentric circles + four large rune marks at cardinal positions.

    Previous iteration had 8 small rune marks that vanished at corner-badge
    size. This version uses 4 large bold runes (Algiz, Othala, sun-cross,
    bind-rune): recognizable as runes even when scaled to 110px.
    """
    # Outer fill ring
    ctx.arc(cx, cy, r_outer, 0, 2 * math.pi)
    ctx.set_source_rgb(*p["ring_outer"])
    ctx.fill()
    # Inner ring border
    ctx.arc(cx, cy, r_inner, 0, 2 * math.pi)
    ctx.set_source_rgb(*p["ring_inner"])
    ctx.fill()
    # Inner disc: darker so the tree pops
    ctx.arc(cx, cy, r_inner * 0.94, 0, 2 * math.pi)
    ctx.set_source_rgb(0.05, 0.08, 0.15)
    ctx.fill()

    # Ring highlight stripe along the outer ring's upper edge, suggests
    # carved depth catching distant aurora light.
    ctx.set_source_rgba(*p["ring_hi"], 0.55)
    ctx.set_line_width(3.0)
    ctx.arc(cx, cy, (r_outer + r_inner) / 2.0, math.pi * 1.15, math.pi * 1.85)
    ctx.stroke()

    # Four large rune marks at N / E / S / W. Bold, iconic, sized to survive
    # corner-badge scaling. Each rune is ~22% of r_outer wide.
    ctx.set_source_rgba(*p["rune"], 0.95)
    ctx.set_line_width(6.0)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    rune_r = r_outer * 0.86
    rune_size = r_outer * 0.13

    # NORTH: Algiz ᛉ, vertical bar with two angled branches at top (life/protection)
    nx, ny = cx, cy - rune_r
    s = rune_size
    ctx.move_to(nx, ny + s)
    ctx.line_to(nx, ny - s)
    ctx.stroke()
    ctx.move_to(nx, ny - s * 0.2)
    ctx.line_to(nx - s * 0.7, ny - s * 0.95)
    ctx.stroke()
    ctx.move_to(nx, ny - s * 0.2)
    ctx.line_to(nx + s * 0.7, ny - s * 0.95)
    ctx.stroke()

    # EAST: Sun-cross, circle with cross inside (also reads as a clean glyph)
    ex, ey = cx + rune_r, cy
    ctx.arc(ex, ey, s * 0.75, 0, 2 * math.pi)
    ctx.stroke()
    ctx.move_to(ex - s * 0.75, ey)
    ctx.line_to(ex + s * 0.75, ey)
    ctx.stroke()
    ctx.move_to(ex, ey - s * 0.75)
    ctx.line_to(ex, ey + s * 0.75)
    ctx.stroke()

    # SOUTH: Othala ᛟ, closed diamond on top with two short angled legs
    # splaying outward from the bottom point (heritage / homeland)
    sx, sy = cx, cy + rune_r
    # Diamond outline (closed shape)
    ctx.move_to(sx, sy - s * 0.95)         # top
    ctx.line_to(sx + s * 0.55, sy - s * 0.20)  # right
    ctx.line_to(sx, sy + s * 0.20)         # center-bottom of diamond
    ctx.line_to(sx - s * 0.55, sy - s * 0.20)  # left
    ctx.close_path()
    ctx.stroke()
    # Two legs splaying down-outward from the diamond's bottom point
    ctx.move_to(sx, sy + s * 0.20)
    ctx.line_to(sx + s * 0.70, sy + s * 0.85)
    ctx.stroke()
    ctx.move_to(sx, sy + s * 0.20)
    ctx.line_to(sx - s * 0.70, sy + s * 0.85)
    ctx.stroke()

    # WEST: Tiwaz ᛏ, clean vertical bar with two diagonal arms from the top,
    # forming an arrow pointing up. (Norse rune of strength/sacrifice.)
    wx, wy = cx - rune_r, cy
    # Vertical bar
    ctx.move_to(wx, wy + s)
    ctx.line_to(wx, wy - s)
    ctx.stroke()
    # Two diagonal arms from top, splaying down-outward
    ctx.move_to(wx, wy - s)
    ctx.line_to(wx - s * 0.55, wy - s * 0.35)
    ctx.stroke()
    ctx.move_to(wx, wy - s)
    ctx.line_to(wx + s * 0.55, wy - s * 0.35)
    ctx.stroke()


def _draw_world_tree(ctx: cairo.Context, cx: float, cy: float, height: float,
                      p: dict) -> None:
    """Vertical world tree: bold silhouette designed to survive corner-badge
    scaling. Thick trunk, 3 large branches up, 3 large roots down. Glowing
    leaf orbs at branch tips. Previous version had 7 thin branches with tiny
    leaves that vanished at small sizes; this version uses fewer but bolder
    elements.
    """
    half_h = height / 2.0
    trunk_w = height * 0.14  # was 0.08, much thicker now
    trunk_top = cy - half_h * 0.45
    trunk_bottom = cy + half_h * 0.20

    # ----- Trunk (filled shape with slight taper) -----
    ctx.set_source_rgb(*p["trunk"])
    ctx.move_to(cx - trunk_w * 0.5, trunk_top)
    ctx.line_to(cx + trunk_w * 0.5, trunk_top)
    ctx.line_to(cx + trunk_w * 0.55, trunk_bottom)
    ctx.line_to(cx - trunk_w * 0.55, trunk_bottom)
    ctx.close_path()
    ctx.fill()

    # Trunk highlight: narrow stripe on the left side suggesting light
    ctx.set_source_rgb(*p["trunk_hi"])
    ctx.move_to(cx - trunk_w * 0.40, trunk_top + 6)
    ctx.line_to(cx - trunk_w * 0.20, trunk_top + 6)
    ctx.line_to(cx - trunk_w * 0.22, trunk_bottom - 6)
    ctx.line_to(cx - trunk_w * 0.42, trunk_bottom - 6)
    ctx.close_path()
    ctx.fill()

    # ----- Three bold branches up: left, center-tall, right -----
    ctx.set_source_rgb(*p["branch"])
    ctx.set_line_width(height * 0.045)  # very thick: survives downscaling
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)

    # Anchor where branches sprout (near the top of the trunk)
    sprout_y = trunk_top + 8

    # Left branch: curves up and out
    ctx.move_to(cx, sprout_y)
    ctx.curve_to(cx - height * 0.10, sprout_y - height * 0.05,
                 cx - height * 0.22, sprout_y - height * 0.18,
                 cx - height * 0.30, sprout_y - height * 0.32)
    ctx.stroke()

    # Right branch: mirror
    ctx.move_to(cx, sprout_y)
    ctx.curve_to(cx + height * 0.10, sprout_y - height * 0.05,
                 cx + height * 0.22, sprout_y - height * 0.18,
                 cx + height * 0.30, sprout_y - height * 0.32)
    ctx.stroke()

    # Center branch: tall straight up
    ctx.move_to(cx, sprout_y)
    ctx.line_to(cx, sprout_y - height * 0.40)
    ctx.stroke()

    # ----- Glowing leaf orbs at branch tips: large, with halos -----
    tips = [
        (cx - height * 0.30, sprout_y - height * 0.32),
        (cx + height * 0.30, sprout_y - height * 0.32),
        (cx, sprout_y - height * 0.40),
    ]
    # Outer halo glow
    for tx, ty in tips:
        halo = cairo.RadialGradient(tx, ty, 4, tx, ty, height * 0.060)
        halo.add_color_stop_rgba(0.0, *p["leaf_glow"], 0.75)
        halo.add_color_stop_rgba(1.0, *p["leaf_glow"], 0.0)
        ctx.set_source(halo)
        ctx.arc(tx, ty, height * 0.060, 0, 2 * math.pi)
        ctx.fill()
    # Solid orb core
    for tx, ty in tips:
        ctx.set_source_rgb(*p["leaf_glow"])
        ctx.arc(tx, ty, height * 0.030, 0, 2 * math.pi)
        ctx.fill()
        # Inner highlight
        ctx.set_source_rgb(*p["leaf_glow_hi"])
        ctx.arc(tx - 2, ty - 2, height * 0.013, 0, 2 * math.pi)
        ctx.fill()

    # ----- Three bold roots down -----
    ctx.set_source_rgb(*p["branch"])
    ctx.set_line_width(height * 0.040)

    # Left root: curves down and out
    ctx.move_to(cx, trunk_bottom)
    ctx.curve_to(cx - height * 0.08, trunk_bottom + height * 0.05,
                 cx - height * 0.20, trunk_bottom + height * 0.12,
                 cx - height * 0.28, trunk_bottom + height * 0.20)
    ctx.stroke()

    # Right root: mirror
    ctx.move_to(cx, trunk_bottom)
    ctx.curve_to(cx + height * 0.08, trunk_bottom + height * 0.05,
                 cx + height * 0.20, trunk_bottom + height * 0.12,
                 cx + height * 0.28, trunk_bottom + height * 0.20)
    ctx.stroke()

    # Center root: straight down
    ctx.move_to(cx, trunk_bottom)
    ctx.line_to(cx, trunk_bottom + height * 0.22)
    ctx.stroke()


def generate_yggdrasil(out_path: str) -> str:
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
    ctx = cairo.Context(surface)
    p = YGGDRASIL_PALETTE

    # Subtle halo
    bg_grad = cairo.RadialGradient(SIZE / 2, SIZE / 2, SIZE * 0.05,
                                    SIZE / 2, SIZE / 2, SIZE * 0.55)
    bg_grad.add_color_stop_rgba(0.0, *p["bg_outer"], 0.0)
    bg_grad.add_color_stop_rgba(0.65, *p["bg_outer"], 0.45)
    bg_grad.add_color_stop_rgba(1.0, *p["bg_outer"], 0.0)
    ctx.set_source(bg_grad)
    ctx.paint()

    cx, cy = SIZE / 2.0, SIZE / 2.0
    _draw_runic_ring(ctx, cx, cy, r_outer=SIZE * 0.42, r_inner=SIZE * 0.36, p=p)
    # Tree slightly smaller than the inner disc so there's breathing room
    # between branch tips and the cardinal runes on the ring.
    _draw_world_tree(ctx, cx, cy, height=SIZE * 0.54, p=p)

    surface.write_to_png(out_path)
    return out_path


# ---------------------------------------------------------------------------
# Journey to the West: Pagoda with cloud frame
# ---------------------------------------------------------------------------

def _draw_cloud_form(ctx: cairo.Context, cx: float, cy: float, scale: float,
                      fill: tuple[float, float, float],
                      hi: tuple[float, float, float]) -> None:
    """Stylized East-Asian ruyi cloud, elongated horizontal scroll with curling
    tail ends. Drawn as a flowing band with spiral tips rather than stacked
    bubbles, closer to classical Chinese cloud iconography.

    The cloud reads as a horizontal wisp: thin in the middle, with two spiral
    curls flanking it.
    """
    s = scale
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)

    # Build the cloud as a single closed path forming a horizontal wisp with
    # two scrolling curls at the ends. We sweep along the top, then come back
    # along a softer bottom curve.
    ctx.set_source_rgb(*fill)

    # Left spiral curl: eye-shape at the left tip
    cl_x, cl_y = cx - 1.05 * s, cy
    ctx.arc(cl_x, cl_y, 0.28 * s, 0, 2 * math.pi)
    ctx.fill()
    # Right spiral curl
    cr_x, cr_y = cx + 1.05 * s, cy
    ctx.arc(cr_x, cr_y, 0.28 * s, 0, 2 * math.pi)
    ctx.fill()

    # Main horizontal body: a thick lozenge connecting the two curls
    ctx.move_to(cl_x, cl_y - 0.18 * s)
    # Top edge: gentle rise to a small crest in the middle, then dip
    ctx.curve_to(cx - 0.55 * s, cy - 0.45 * s,
                 cx + 0.05 * s, cy - 0.40 * s,
                 cx + 0.35 * s, cy - 0.25 * s)
    ctx.curve_to(cx + 0.65 * s, cy - 0.10 * s,
                 cx + 0.85 * s, cy - 0.20 * s,
                 cr_x, cr_y - 0.18 * s)
    # Right side of right curl (already drawn via arc), to bottom of right curl
    ctx.line_to(cr_x, cr_y + 0.18 * s)
    # Bottom edge: soft scallop returning leftward
    ctx.curve_to(cx + 0.75 * s, cy + 0.35 * s,
                 cx + 0.25 * s, cy + 0.30 * s,
                 cx - 0.05 * s, cy + 0.20 * s)
    ctx.curve_to(cx - 0.40 * s, cy + 0.10 * s,
                 cx - 0.75 * s, cy + 0.30 * s,
                 cl_x, cl_y + 0.18 * s)
    ctx.close_path()
    ctx.fill()

    # Inner curl marks on each tip, gives them a "scroll spiral" feel
    ctx.set_source_rgba(*hi, 0.55)
    ctx.set_line_width(max(1.5, s * 0.04))
    for spiral_x, spiral_y, sign in [(cl_x, cl_y, -1), (cr_x, cr_y, 1)]:
        ctx.arc(spiral_x, spiral_y, 0.16 * s,
                math.pi * 0.6 if sign < 0 else math.pi * 1.6,
                math.pi * 1.9 if sign < 0 else math.pi * 0.9)
        ctx.stroke()

    # Top-edge highlight rim: bright stripe tracing the top of the wisp
    ctx.set_source_rgba(*hi, 0.70)
    ctx.set_line_width(max(1.8, s * 0.05))
    ctx.move_to(cl_x, cl_y - 0.18 * s)
    ctx.curve_to(cx - 0.55 * s, cy - 0.45 * s,
                 cx + 0.05 * s, cy - 0.40 * s,
                 cx + 0.35 * s, cy - 0.25 * s)
    ctx.curve_to(cx + 0.65 * s, cy - 0.10 * s,
                 cx + 0.85 * s, cy - 0.20 * s,
                 cr_x, cr_y - 0.18 * s)
    ctx.stroke()


def _draw_pagoda(ctx: cairo.Context, cx: float, cy: float, height: float,
                  p: dict) -> None:
    """Three-tiered pagoda. cy is the BASE y; pagoda rises upward from here."""
    base_y = cy
    # Tier sizes: bottom widest, top narrowest. Each tier = body + roof.
    tier_specs = [
        # (body_w, body_h, roof_overhang, roof_h)
        (height * 0.45, height * 0.20, height * 0.10, height * 0.10),  # bottom
        (height * 0.38, height * 0.18, height * 0.09, height * 0.09),  # middle
        (height * 0.30, height * 0.16, height * 0.08, height * 0.08),  # top
    ]
    y = base_y
    for body_w, body_h, overhang, roof_h in tier_specs:
        # Body
        body_x = cx - body_w / 2.0
        ctx.rectangle(body_x, y - body_h, body_w, body_h)
        body_grad = cairo.LinearGradient(body_x, y - body_h, body_x + body_w, y)
        body_grad.add_color_stop_rgb(0.0, *p["pagoda_body_hi"])
        body_grad.add_color_stop_rgb(1.0, *p["pagoda_body"])
        ctx.set_source(body_grad)
        ctx.fill()
        # Body ink outline
        ctx.set_source_rgba(*p["ink"], 0.7)
        ctx.set_line_width(2.0)
        ctx.rectangle(body_x, y - body_h, body_w, body_h)
        ctx.stroke()

        # Doorway / window: small darker rectangle in the middle
        door_w = body_w * 0.20
        door_h = body_h * 0.50
        ctx.rectangle(cx - door_w / 2.0, y - door_h - body_h * 0.10, door_w, door_h)
        ctx.set_source_rgb(0.10, 0.06, 0.06)
        ctx.fill()

        # Roof: curving pagoda roof. Drawn as a polygon with upward-curving ends.
        roof_top_y = y - body_h - roof_h
        roof_left = cx - body_w / 2.0 - overhang
        roof_right = cx + body_w / 2.0 + overhang
        ctx.move_to(roof_left, y - body_h)
        ctx.curve_to(roof_left + overhang * 0.6, roof_top_y + roof_h * 0.4,
                     cx - body_w * 0.3, roof_top_y,
                     cx, roof_top_y)
        ctx.curve_to(cx + body_w * 0.3, roof_top_y,
                     roof_right - overhang * 0.6, roof_top_y + roof_h * 0.4,
                     roof_right, y - body_h)
        ctx.close_path()
        roof_grad = cairo.LinearGradient(0, roof_top_y, 0, y - body_h)
        roof_grad.add_color_stop_rgb(0.0, *p["pagoda_roof_hi"])
        roof_grad.add_color_stop_rgb(1.0, *p["pagoda_roof"])
        ctx.set_source(roof_grad)
        ctx.fill_preserve()
        ctx.set_source_rgba(*p["ink"], 0.85)
        ctx.set_line_width(2.0)
        ctx.stroke()

        # Advance up to the next tier
        y -= body_h + roof_h

    # Crowning spire: a slender pointed shape on top
    spire_base = y
    spire_top = y - height * 0.12
    ctx.move_to(cx - 5, spire_base)
    ctx.line_to(cx + 5, spire_base)
    ctx.line_to(cx, spire_top)
    ctx.close_path()
    ctx.set_source_rgb(*p["spire"])
    ctx.fill()
    # Spire orb
    ctx.arc(cx, spire_top + 6, 6, 0, 2 * math.pi)
    ctx.fill()


def generate_jttw(out_path: str) -> str:
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, SIZE, SIZE)
    ctx = cairo.Context(surface)
    p = JTTW_PALETTE

    # Subtle halo
    bg_grad = cairo.RadialGradient(SIZE / 2, SIZE / 2, SIZE * 0.05,
                                    SIZE / 2, SIZE / 2, SIZE * 0.55)
    bg_grad.add_color_stop_rgba(0.0, *p["bg_outer"], 0.0)
    bg_grad.add_color_stop_rgba(0.65, *p["bg_outer"], 0.45)
    bg_grad.add_color_stop_rgba(1.0, *p["bg_outer"], 0.0)
    ctx.set_source(bg_grad)
    ctx.paint()

    cx = SIZE / 2.0
    # BACKGROUND clouds: drifting in the upper half, behind the pagoda.
    # Drawn first so the pagoda overlaps them naturally.
    _draw_cloud_form(ctx, cx - SIZE * 0.30, SIZE * 0.28, SIZE * 0.12,
                      p["cloud_dark"], p["cloud_hi"])
    _draw_cloud_form(ctx, cx + SIZE * 0.30, SIZE * 0.36, SIZE * 0.11,
                      p["cloud_dark"], p["cloud_hi"])

    # Pagoda: base near the bottom-third, rises through center
    _draw_pagoda(ctx, cx, SIZE * 0.82, height=SIZE * 0.85, p=p)

    # FOREGROUND cloud: a single wisp drifting across the pagoda's mid-height,
    # to suggest the pagoda is among the clouds rather than on a hillside.
    _draw_cloud_form(ctx, cx + SIZE * 0.18, SIZE * 0.55, SIZE * 0.10,
                      p["cloud"], p["cloud_hi"])
    _draw_cloud_form(ctx, cx - SIZE * 0.22, SIZE * 0.65, SIZE * 0.09,
                      p["cloud"], p["cloud_hi"])

    surface.write_to_png(out_path)
    return out_path


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    targets = sys.argv[1:] or ["all"]
    if "all" in targets or "camelot" in targets:
        for emblem in ("cross", "fleur"):
            path = generate_camelot(
                os.path.join(OUT_DIR, f"sigil_camelot_{emblem}.png"), emblem=emblem)
            print(f"camelot_{emblem}: {path}")
    if "all" in targets or "yggdrasil" in targets:
        path = generate_yggdrasil(os.path.join(OUT_DIR, "sigil_yggdrasil.png"))
        print(f"yggdrasil:     {path}")
    if "all" in targets or "jttw" in targets:
        path = generate_jttw(os.path.join(OUT_DIR, "sigil_jttw.png"))
        print(f"jttw:          {path}")


if __name__ == "__main__":
    main()
