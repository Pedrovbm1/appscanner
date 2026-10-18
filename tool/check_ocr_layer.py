import argparse
import json
import math
import sys

import pymupdf
from pypdf import PdfReader

PAGE_W, PAGE_H, MARGIN = 595.28, 841.89, 16.0
TOLERANCE = 0.05


def expected_boxes(data):
    box_w, box_h = PAGE_W - 2 * MARGIN, PAGE_H - 2 * MARGIN
    img_w, img_h = data["width"], data["height"]
    scale = min(box_w / img_w, box_h / img_h)
    off_x = MARGIN + (box_w - img_w * scale) / 2
    off_y = MARGIN + (box_h - img_h * scale) / 2
    for word in data["words"]:
        x0 = off_x + word["l"] * scale
        y0 = off_y + word["t"] * scale
        x1 = off_x + word["r"] * scale
        y1 = off_y + word["b"] * scale
        yield word["text"], ((x0 + x1) / 2, (y0 + y1) / 2)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf")
    parser.add_argument("ocr_json")
    parser.add_argument("--password", default="")
    parser.add_argument("--page", type=int, default=1)
    args = parser.parse_args()

    reader = PdfReader(args.pdf)
    if reader.is_encrypted:
        reader.decrypt(args.password)
    box = reader.pages[args.page - 1].mediabox
    print(f"pages={len(reader.pages)} page1={float(box.width):.2f}x{float(box.height):.2f}")

    with open(args.ocr_json, encoding="utf-8") as handle:
        data = json.load(handle)
    doc = pymupdf.open(args.pdf)
    if doc.needs_pass:
        doc.authenticate(args.password)
    actual = [
        (w[4], ((w[0] + w[2]) / 2, (w[1] + w[3]) / 2))
        for w in doc[args.page - 1].get_text("words")
    ]
    used = set()
    limit = PAGE_W * TOLERANCE
    hits = total = 0
    for text, (ex, ey) in expected_boxes(data):
        pool = [i for i, a in enumerate(actual) if i not in used and a[0] == text]
        pool = pool or [i for i in range(len(actual)) if i not in used]
        total += 1
        if not pool:
            print(f"{text!r:24} expected=({ex:7.1f},{ey:7.1f}) actual=missing")
            continue
        best = min(pool, key=lambda i: math.dist(actual[i][1], (ex, ey)))
        used.add(best)
        ax, ay = actual[best][1]
        dist = math.dist((ax, ay), (ex, ey))
        ok = dist <= limit
        hits += ok
        print(
            f"{text!r:24} expected=({ex:7.1f},{ey:7.1f}) "
            f"actual=({ax:7.1f},{ay:7.1f}) {actual[best][0]!r} d={dist:5.1f} {'OK' if ok else 'FAR'}"
        )
    pct = 100 * hits / total if total else 0
    print(f"words_json={total} words_pdf={len(actual)} within_5%={hits} ({pct:.1f}%)")
    return 0 if total and pct >= 90 else 1


if __name__ == "__main__":
    sys.exit(main())
