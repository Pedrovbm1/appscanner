"""Generate the app icon + splash artwork for Escaner.

Run from anywhere:  python assets/icon/make_icon.py
Outputs (next to this script):
  icon.png             1024x1024  legacy/full icon (teal rounded square + sheet)
  icon_foreground.png  1024x1024  adaptive foreground (transparent, safe zone)
  splash.png            512x512   sheet only, transparent (splash screen)
Everything is drawn at 4x and downscaled with LANCZOS for clean antialiasing.
"""
from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent
SS = 4  # supersampling factor

TEAL = (0x00, 0x79, 0x6B, 255)
WHITE = (255, 255, 255, 255)
FOLD = (0xD7, 0xE3, 0xE1, 255)      # folded corner (light grey-teal)
SHADOW = (0x00, 0x4D, 0x40, 90)     # soft drop shadow under the sheet
LINE = (0xB0, 0xBE, 0xC5, 255)      # grey text lines
ACCENT = (0x80, 0xCB, 0xC4, 255)    # scan line
ACCENT_GLOW = (0x80, 0xCB, 0xC4, 60)


def draw_sheet(canvas: Image.Image, cx: float, cy: float, h: float, shadow: bool) -> None:
    """Draw the document sheet centred at (cx, cy) with height h (canvas px)."""
    w = h * 0.78
    x0, y0 = cx - w / 2, cy - h / 2
    x1, y1 = cx + w / 2, cy + h / 2
    r = h * 0.06          # corner radius
    f = w * 0.30          # folded-corner size

    def sheet_mask(dx: float, dy: float) -> Image.Image:
        """Alpha mask of the sheet (rounded rect with top-right corner cut)."""
        m = Image.new("L", canvas.size, 0)
        md = ImageDraw.Draw(m)
        md.rounded_rectangle((x0 + dx, y0 + dy, x1 + dx, y1 + dy), r, fill=255)
        md.polygon([(x1 - f + dx, y0 + dy - 2), (x1 + dx + 2, y0 + dy - 2),
                    (x1 + dx + 2, y0 + f + dy)], fill=0)
        return m

    if shadow:
        off = h * 0.025
        m = sheet_mask(off, off * 1.6).point(lambda v: v * SHADOW[3] // 255)
        sh = Image.new("RGBA", canvas.size, SHADOW[:3] + (0,))
        sh.putalpha(m)
        canvas.alpha_composite(sh)

    body = Image.new("RGBA", canvas.size, WHITE[:3] + (0,))
    body.putalpha(sheet_mask(0, 0))
    canvas.alpha_composite(body)

    d = ImageDraw.Draw(canvas)
    # Folded corner triangle.
    d.polygon([(x1 - f, y0), (x1 - f, y0 + f), (x1, y0 + f)], fill=FOLD)

    # Three short grey text lines.
    lh = h * 0.045
    lx = x0 + w * 0.16
    widths = [0.50, 0.68, 0.42]
    ys = [y0 + h * 0.40, y0 + h * 0.55, y0 + h * 0.70]
    for frac, ly in zip(widths, ys):
        d.rounded_rectangle((lx, ly, lx + w * frac, ly + lh), lh / 2, fill=LINE)

    # Scan line: soft glow + bright bar, slightly wider than the sheet.
    sy = y0 + h * 0.475 + lh / 2
    ext = w * 0.08
    glow = h * 0.04
    d.rounded_rectangle((x0 - ext, sy - glow, x1 + ext, sy + glow), glow, fill=ACCENT_GLOW)
    bar = h * 0.018
    d.rounded_rectangle((x0 - ext, sy - bar, x1 + ext, sy + bar), bar, fill=ACCENT)


def render(size: int, bg: bool, sheet_h_frac: float, shadow: bool) -> Image.Image:
    big = size * SS
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    if bg:
        ImageDraw.Draw(img).rounded_rectangle((0, 0, big - 1, big - 1), big * 0.22, fill=TEAL)
    draw_sheet(img, big / 2, big / 2, big * sheet_h_frac, shadow)
    return img.resize((size, size), Image.LANCZOS)


def main() -> None:
    # Legacy icon: sheet fills ~60% of the height.
    render(1024, bg=True, sheet_h_frac=0.60, shadow=True).save(OUT / "icon.png")
    # Adaptive foreground: launcher masks to the inner 72/108 and the safe
    # zone is a 66/108 (~61%) circle, so keep the sheet + scan line inside it.
    render(1024, bg=False, sheet_h_frac=0.42, shadow=True).save(OUT / "icon_foreground.png")
    # Splash: Android 12 crops the splash icon to a circle (~2/3 of the image),
    # so the sheet stays small and centred.
    render(512, bg=False, sheet_h_frac=0.50, shadow=False).save(OUT / "splash.png")
    print("wrote icon.png, icon_foreground.png, splash.png to", OUT)


if __name__ == "__main__":
    main()
