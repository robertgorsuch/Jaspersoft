#!/usr/bin/env python3
"""Rasterize page 1 of a PDF and optionally diff it against a baseline PNG.

Used by verify_report.ps1 for visual-regression checks. Exit codes:
  0  rendered (no baseline) | baseline saved | diff within threshold
  3  diff exceeds threshold
  2  error
Prints one status line: RENDERED | BASELINE_SAVED | MEANDIFF <n>.
"""
import argparse
import os
import sys


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdf", required=True)
    ap.add_argument("--png", required=True, help="output PNG of page 1")
    ap.add_argument("--baseline", help="baseline PNG to compare against")
    ap.add_argument("--max-diff", type=float, default=2.0,
                    help="max allowed mean abs pixel diff (0-255)")
    ap.add_argument("--update", action="store_true", help="(re)write the baseline")
    ap.add_argument("--scale", type=float, default=2.0)
    a = ap.parse_args()

    try:
        import pypdfium2 as pdfium
    except ImportError:
        sys.stderr.write("pypdfium2 not installed (pip install pypdfium2 Pillow)\n")
        sys.exit(2)

    img = pdfium.PdfDocument(a.pdf)[0].render(scale=a.scale).to_pil().convert("RGB")
    os.makedirs(os.path.dirname(os.path.abspath(a.png)) or ".", exist_ok=True)
    img.save(a.png)

    if not a.baseline:
        print("RENDERED")
        return 0
    if a.update or not os.path.exists(a.baseline):
        os.makedirs(os.path.dirname(os.path.abspath(a.baseline)) or ".", exist_ok=True)
        img.save(a.baseline)
        print("BASELINE_SAVED")
        return 0

    from PIL import Image, ImageChops
    base = Image.open(a.baseline).convert("RGB")
    if base.size != img.size:
        base = base.resize(img.size)
    diff = ImageChops.difference(base, img)
    try:
        import numpy as np
        mean = float(np.asarray(diff).mean())
    except Exception:
        # numpy-free, no deprecated getdata(): mean grey level from the histogram
        hist = diff.convert("L").histogram()
        total = sum(i * h for i, h in enumerate(hist))
        count = sum(hist)
        mean = (total / count) if count else 0.0
    print(f"MEANDIFF {mean:.3f}")
    return 0 if mean <= a.max_diff else 3


if __name__ == "__main__":
    sys.exit(main())
