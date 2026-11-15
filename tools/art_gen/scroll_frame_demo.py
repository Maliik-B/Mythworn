"""Scroll-frame hybrid demo.

Generates a Skul-style narrative scene as:
  1. A PyCairo composition: scroll frame, atmospheric background, stylized
     silhouette of the scene's subject, text.
  2. The same composition run through OpenCV's edgePreservingFilter and a
     gentler stylization to test painterly post-processing.

Usage: python scroll_frame_demo.py
"""

from __future__ import annotations

import math
import os
import sys

import cairo
import cv2
import numpy as np

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "art_drafts")
WIDTH, HEIGHT = 1024, 640


def _palette_camelot() -> dict[str, tuple[float, float, float]]:
    return {
        "parchment": (0.93, 0.86, 0.66),
        "parchment_shadow": (0.71, 0.61, 0.39),
        "ink": (0.18, 0.12, 0.08),
        "deep_red": (0.50, 0.10, 0.10),
        "gold": (0.85, 0.65, 0.20),
        "sky": (0.28, 0.10, 0.10),
        "horizon": (0.42, 0.16, 0.12),
        "silhouette": (0.10, 0.06, 0.06),
        "castle_glow": (0.78, 0.32, 0.14),
    }


def draw_scroll_frame(ctx: cairo.Context, w: int, h: int, palette: dict) -> None:
    """Outer scroll/parchment frame with rolled edges at top and bottom."""
    ctx.set_source_rgb(0.06, 0.05, 0.09)
    ctx.paint()

    margin_x = 80
    margin_y = 60
    inner_x, inner_y = margin_x, margin_y
    inner_w, inner_h = w - margin_x * 2, h - margin_y * 2

    grad = cairo.RadialGradient(w / 2, h / 2, h * 0.2, w / 2, h / 2, h * 0.7)
    grad.add_color_stop_rgb(0.0, *palette["parchment"])
    grad.add_color_stop_rgb(1.0, *palette["parchment_shadow"])
    ctx.set_source(grad)
    ctx.rectangle(inner_x, inner_y, inner_w, inner_h)
    ctx.fill()

    for edge_y in (inner_y, inner_y + inner_h):
        ctx.save()
        ctx.set_source_rgb(0.45, 0.36, 0.20)
        ctx.translate(w / 2, edge_y)
        ctx.scale(1.0, 0.35)
        ctx.arc(0, 0, inner_w / 2 + 26, 0, 2 * math.pi)
        ctx.fill()
        ctx.restore()

        ctx.save()
        ctx.set_source_rgb(*palette["parchment"])
        ctx.translate(w / 2, edge_y)
        ctx.scale(1.0, 0.30)
        ctx.arc(0, 0, inner_w / 2 + 22, 0, 2 * math.pi)
        ctx.fill()
        ctx.restore()

        ctx.save()
        ctx.set_source_rgba(1.0, 0.95, 0.78, 0.6)
        ctx.set_line_width(2.0)
        ctx.translate(w / 2, edge_y)
        ctx.scale(1.0, 0.30)
        ctx.arc(0, -6, inner_w / 2 + 18, 0, math.pi)
        ctx.stroke()
        ctx.restore()

    ctx.set_source_rgba(*palette["ink"], 0.45)
    ctx.set_line_width(1.5)
    ctx.rectangle(inner_x + 14, inner_y + 14, inner_w - 28, inner_h - 28)
    ctx.stroke()


def draw_atmospheric_scene(ctx: cairo.Context, w: int, h: int, palette: dict,
                            scene_h_ratio: float = 0.55) -> None:
    """Inner scene: drawn into the top portion of the parchment, leaving the
    bottom band for text. `scene_h_ratio` controls how much vertical space the
    scene takes relative to the parchment height (default 55%).
    """
    inner_x = 110
    inner_y = 110
    inner_w = w - 220
    parchment_h = h - 220
    inner_h = int(parchment_h * scene_h_ratio)

    ctx.save()
    ctx.rectangle(inner_x, inner_y, inner_w, inner_h)
    ctx.clip()

    sky = cairo.LinearGradient(0, inner_y, 0, inner_y + inner_h * 0.7)
    sky.add_color_stop_rgb(0.0, *palette["sky"])
    sky.add_color_stop_rgb(1.0, *palette["horizon"])
    ctx.set_source(sky)
    ctx.rectangle(inner_x, inner_y, inner_w, inner_h * 0.75)
    ctx.fill()

    ctx.set_source_rgb(0.10, 0.05, 0.05)
    ctx.rectangle(inner_x, inner_y + inner_h * 0.75, inner_w, inner_h * 0.25)
    ctx.fill()

    cx = inner_x + inner_w * 0.5
    base_y = inner_y + inner_h * 0.75
    ctx.set_source_rgb(*palette["silhouette"])

    keep_w = 160
    keep_h = 110
    ctx.rectangle(cx - keep_w / 2, base_y - keep_h, keep_w, keep_h)
    ctx.fill()
    for i in range(6):
        x = cx - keep_w / 2 + i * (keep_w / 6) + 3
        ctx.rectangle(x, base_y - keep_h - 12, keep_w / 6 - 6, 12)
        ctx.fill()
    tower_w = 44
    tower_h = 190
    ctx.rectangle(cx - tower_w / 2, base_y - tower_h, tower_w, tower_h)
    ctx.fill()
    ctx.move_to(cx - tower_w / 2 - 6, base_y - tower_h)
    ctx.line_to(cx + tower_w / 2 + 6, base_y - tower_h)
    ctx.line_to(cx, base_y - tower_h - 50)
    ctx.close_path()
    ctx.fill()
    for side in (-1, 1):
        sx = cx + side * (keep_w / 2 + 28)
        ctx.rectangle(sx - 20, base_y - 140, 40, 140)
        ctx.fill()
        ctx.move_to(sx - 26, base_y - 140)
        ctx.line_to(sx + 26, base_y - 140)
        ctx.line_to(sx, base_y - 170)
        ctx.close_path()
        ctx.fill()

    glow = cairo.RadialGradient(cx, base_y - 80, 5, cx, base_y - 80, 200)
    glow.add_color_stop_rgba(0.0, *palette["castle_glow"], 0.85)
    glow.add_color_stop_rgba(0.6, palette["castle_glow"][0] * 0.5,
                              palette["castle_glow"][1] * 0.25,
                              palette["castle_glow"][2] * 0.18, 0.30)
    glow.add_color_stop_rgba(1.0, 0.0, 0.0, 0.0, 0.0)
    ctx.set_source(glow)
    ctx.set_operator(cairo.OPERATOR_SCREEN)
    ctx.rectangle(inner_x, inner_y, inner_w, inner_h)
    ctx.fill()
    ctx.set_operator(cairo.OPERATOR_OVER)

    rng = np.random.RandomState(seed=42)
    for _ in range(40):
        x = inner_x + rng.rand() * inner_w
        y = inner_y + rng.rand() * inner_h * 0.6
        size = 0.5 + rng.rand() * 1.5
        alpha = 0.2 + rng.rand() * 0.5
        ctx.set_source_rgba(0.95, 0.92, 0.75, alpha)
        ctx.arc(x, y, size, 0, 2 * math.pi)
        ctx.fill()

    ctx.restore()


def draw_narrative_text(ctx: cairo.Context, w: int, h: int, palette: dict,
                         title: str, body: str,
                         scene_h_ratio: float = 0.55) -> None:
    """Narrative text in the parchment band below the scene."""
    parchment_h = h - 220
    text_top = 110 + int(parchment_h * scene_h_ratio) + 24
    ctx.set_source_rgb(*palette["ink"])
    ctx.select_font_face("Georgia", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    ctx.set_font_size(30)
    extents = ctx.text_extents(title)
    ctx.move_to((w - extents.width) / 2, text_top)
    ctx.show_text(title)

    ctx.select_font_face("Georgia", cairo.FONT_SLANT_ITALIC, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(16)
    ty = text_top + 32
    for line in body.split("\n"):
        extents = ctx.text_extents(line)
        ctx.move_to((w - extents.width) / 2, ty)
        ctx.show_text(line)
        ty += 22


def generate_vector_scene(out_path: str) -> str:
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
    ctx = cairo.Context(surface)
    palette = _palette_camelot()

    draw_scroll_frame(ctx, WIDTH, HEIGHT, palette)
    draw_atmospheric_scene(ctx, WIDTH, HEIGHT, palette)
    draw_narrative_text(
        ctx, WIDTH, HEIGHT, palette,
        title="The Throne Sits Empty",
        body=(
            "Word travels faster than horses now. Camelot's king has not\n"
            "been seen since dusk; a sickness in the keep, they say. You\n"
            "stand at the gates with the road still warm under your boots."
        ),
    )
    surface.write_to_png(out_path)
    return out_path


def apply_painterly_filter(in_path: str, out_path: str, mode: str = "edge",
                            sigma_s: float = 20.0, sigma_r: float = 0.20) -> str:
    """Read a PNG, apply OpenCV painterly post-processing.

    mode='edge'      -> edgePreservingFilter (gentle, preserves structure)
    mode='stylize'   -> stylization (watercolor, more abstract)
    mode='detail'    -> detailEnhance (sharpens details)
    """
    img = cv2.imread(in_path)
    if img is None:
        raise FileNotFoundError(in_path)
    if mode == "edge":
        out = cv2.edgePreservingFilter(img, flags=cv2.RECURS_FILTER,
                                       sigma_s=sigma_s, sigma_r=sigma_r)
    elif mode == "stylize":
        out = cv2.stylization(img, sigma_s=sigma_s, sigma_r=sigma_r)
    elif mode == "detail":
        out = cv2.detailEnhance(img, sigma_s=sigma_s, sigma_r=sigma_r)
    else:
        raise ValueError(mode)
    cv2.imwrite(out_path, out)
    return out_path


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    vec_path = os.path.join(OUT_DIR, "scroll_camelot_vector.png")
    generate_vector_scene(vec_path)
    print("vector:    ", vec_path)

    for mode, params in [
        ("edge", dict(sigma_s=20.0, sigma_r=0.20)),
        ("stylize", dict(sigma_s=15.0, sigma_r=0.20)),
        ("stylize", dict(sigma_s=30.0, sigma_r=0.35)),
    ]:
        suffix = f"{mode}_s{params['sigma_s']:.0f}_r{params['sigma_r']:.2f}"
        out_path = os.path.join(OUT_DIR, f"scroll_camelot_{suffix}.png")
        apply_painterly_filter(vec_path, out_path, mode=mode, **params)
        print(f"{suffix:30}", out_path)


if __name__ == "__main__":
    main()
