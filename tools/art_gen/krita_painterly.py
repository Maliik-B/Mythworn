"""Krita painterly post-process: runs INSIDE Krita's Scripter.

IMPORTANT: known limit of Krita's Python API
=============================================
Krita's Python scripting CANNOT paint brush strokes, invoke drawing tools,
or simulate stylus input. The API is filter-only; we can apply filters
(oilpaint, blur, edge detection, etc.) to existing pixels but not "paint
watercolor" the way a human with a stylus would. The actual brush engine
is for human input; the scriptable surface is the same kind of surface
OpenCV exposes, just with Krita's filter implementations.

What this means for our experiment:
- Output here is "vector base + filter passes"
- Same fundamental shape as the OpenCV stylization test we ran earlier
- Quality may be a bit better than OpenCV (oilpaint is purpose-built) but
  it will NOT look like real watercolor illustration
- Krita's best painterly filters (watercolor, pencil drawing) live in the
  G'MIC plugin, which is GUI-dialog-driven and hard to script

If these results are compelling, great. If they're not, that's our cue
that procedural painterly is genuinely capped where the OpenCV test
suggested, and commissioned art is the right next move for narrative scenes.

How to run this:
1. Generate the source vector scene first:
     python tools/art_gen/scroll_frame_demo.py
   This produces art_drafts/scroll_camelot_vector.png

2. Open Krita.

3. Open Tools → Scripts → Scripter.

4. Copy this entire file's contents into the Scripter window.

5. Press the "Run" button (green play icon).

6. Outputs land in art_drafts/ next to the source:
     scroll_camelot_krita_oilpaint.png: Oilify filter, light settings
     scroll_camelot_krita_oilpaint_heavy.png: Oilify with heavier settings
     scroll_camelot_krita_edge.png: Edge detection (more graphic)
     scroll_camelot_krita_blur+oil.png: Soft blur then oilify
"""

from __future__ import annotations

import os

# 'krita' module is available when running inside Krita's Scripter
from krita import Krita, InfoObject  # noqa: F401  (provided by Krita runtime)


PROJECT_ROOT = r"D:\Applications\Fable"
SRC_PATH = os.path.join(PROJECT_ROOT, "art_drafts", "scroll_camelot_vector.png")
OUT_DIR = os.path.join(PROJECT_ROOT, "art_drafts")


def _open_fresh(path: str):
    """Open the source image in a new Krita document each time so we always
    start from a clean state: no compounding filter applications.
    """
    app = Krita.instance()
    doc = app.openDocument(path)
    if doc is None:
        raise RuntimeError(f"Could not open: {path}")
    app.activeWindow().addView(doc)
    return doc


def _apply_filter(doc, filter_name: str, props: dict | None = None):
    """Apply a named Krita filter to the document's active node."""
    f = Krita.instance().filter(filter_name)
    if f is None:
        raise RuntimeError(f"Filter not found: {filter_name}")
    if props:
        config = f.configuration()
        for k, v in props.items():
            config.setProperty(k, v)
        f.setConfiguration(config)
    node = doc.activeNode()
    f.apply(node, 0, 0, doc.width(), doc.height())
    doc.refreshProjection()


def _export(doc, out_path: str):
    """Export the current document state as PNG."""
    info = InfoObject()
    info.setProperty("compression", 6)
    info.setProperty("forceSRGB", True)
    info.setProperty("alpha", True)
    doc.exportImage(out_path, info)


def run():
    if not os.path.exists(SRC_PATH):
        raise RuntimeError(
            f"Source not found: {SRC_PATH}\n"
            "Run `python tools/art_gen/scroll_frame_demo.py` first."
        )

    # Variant 1: oilify (default-ish settings)
    doc = _open_fresh(SRC_PATH)
    _apply_filter(doc, "oilpaint", {"brushSize": 3, "smooth": 30})
    _export(doc, os.path.join(OUT_DIR, "scroll_camelot_krita_oilpaint.png"))
    doc.close()

    # Variant 2: oilify with heavier settings
    doc = _open_fresh(SRC_PATH)
    _apply_filter(doc, "oilpaint", {"brushSize": 6, "smooth": 60})
    _export(doc, os.path.join(OUT_DIR, "scroll_camelot_krita_oilpaint_heavy.png"))
    doc.close()

    # Variant 3: edge detection (NPR-like)
    doc = _open_fresh(SRC_PATH)
    _apply_filter(doc, "edge detection", {"horizRadius": 2, "vertRadius": 2})
    _export(doc, os.path.join(OUT_DIR, "scroll_camelot_krita_edge.png"))
    doc.close()

    # Variant 4: light gaussian blur followed by oilify (softens then paints)
    doc = _open_fresh(SRC_PATH)
    _apply_filter(doc, "gaussian blur", {"horizRadius": 2.0, "vertRadius": 2.0})
    _apply_filter(doc, "oilpaint", {"brushSize": 4, "smooth": 30})
    _export(doc, os.path.join(OUT_DIR, "scroll_camelot_krita_blur+oil.png"))
    doc.close()

    print("[krita_painterly] Done. Outputs in:", OUT_DIR)


run()
