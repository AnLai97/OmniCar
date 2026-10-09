"""Row icon for the Speed Bubble feature: HarmonyOS color tile (like OMCIcon draws for SF Symbols)
with a white speech bubble holding a red speed-limit ring. Renders variants, a preview sheet, and
exports 29/58/87 px PNGs."""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

S = 8                     # supersample: draw at 29*S then downscale
PT = 29
N = PT * S
OUT = sys.argv[1] if len(sys.argv) > 1 else "."

def rgb(h): h = h.lstrip("#"); return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def tile(color):
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, N - 1, N - 1), radius=8.5 * S, fill=rgb(color) + (255,))
    # top sheen: white 22% -> 0 over the full height (matches OMCIcon)
    sheen = Image.new("L", (1, N))
    for y in range(N): sheen.putpixel((0, y), int(255 * 0.22 * (1 - y / N)))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, N - 1, N - 1), radius=8.5 * S, fill=255)
    white = Image.new("RGBA", (N, N), (255, 255, 255, 255))
    im.paste(white, (0, 0), Image.composite(sheen.resize((N, N)), Image.new("L", (N, N), 0), mask))
    return im

def pt(*v): return [x * S for x in v]

def font(size):
    for name in ("arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try: return ImageFont.truetype(name, int(size * S))
        except OSError: pass
    return ImageFont.load_default()

def bubble(d, box, tail="bl", r=4.2):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(pt(x0, y0, x1, y1), radius=r * S, fill=(255, 255, 255, 255))
    if tail == "bl":
        d.polygon(pt(x0 + 3.2, y1 - 1.5, x0 + 2.2, y1 + 3.2, x0 + 7.5, y1 - 0.6), fill=(255, 255, 255, 255))
    elif tail == "br":
        d.polygon(pt(x1 - 3.2, y1 - 1.5, x1 - 2.2, y1 + 3.2, x1 - 7.5, y1 - 0.6), fill=(255, 255, 255, 255))

def ring(d, cx, cy, r, w, color="#E53935", text=None, tsize=5.2):
    d.ellipse(pt(cx - r, cy - r, cx + r, cy + r), outline=rgb(color) + (255,), width=int(w * S))
    if text:
        f = font(tsize)
        d.text(pt(cx, cy + 0.2), text, fill=(32, 32, 32, 255), font=f, anchor="mm")

def V1(color="#36B37E"):   # bubble with limit ring "60" alone
    im = tile(color); d = ImageDraw.Draw(im)
    bubble(d, (4.5, 5.5, 24.5, 20.5))
    ring(d, 14.5, 13, 5.3, 1.5, text="60", tsize=5.6)
    return im

def V2(color="#36B37E"):   # bubble: limit ring on the left + bold speed on the right
    im = tile(color); d = ImageDraw.Draw(im)
    bubble(d, (3.5, 6, 25.5, 20))
    ring(d, 9.3, 13, 4.3, 1.4)
    d.text(pt(19.2, 13.1), "58", fill=(32, 32, 32, 255), font=font(8.2), anchor="mm")
    return im

def V3(color="#36B37E"):   # bubble with ring "60" + small speed text under? no: ring + "58" stacked
    im = tile(color); d = ImageDraw.Draw(im)
    bubble(d, (4.5, 4.5, 24.5, 21.5))
    ring(d, 10, 12.8, 4.6, 1.5, text="60", tsize=4.6)
    d.text(pt(19.6, 13), "58", fill=(32, 32, 32, 255), font=font(7.6), anchor="mm")
    return im

def V4(color="#36B37E"):   # ring only, bigger, bubble tail bottom-right
    im = tile(color); d = ImageDraw.Draw(im)
    bubble(d, (4.5, 5, 24.5, 20), tail="br")
    ring(d, 14.5, 12.5, 5.6, 1.7, text="60", tsize=5.8)
    return im

VARIANTS = {"V1 ring60": V1, "V2 ring+58": V2, "V3 ring60+58": V3, "V4 ring60 br": V4}

def export(im, base):
    for scale, suffix in ((1, ""), (2, "@2x"), (3, "@3x")):
        im.resize((PT * scale, PT * scale), Image.LANCZOS).save(os.path.join(OUT, f"{base}{suffix}.png"))

def sign(d, cx, cy, r, w, text="60", tsize=7.5):
    d.ellipse(pt(cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, 255))
    d.ellipse(pt(cx - r, cy - r, cx + r, cy + r), outline=rgb("#E53935") + (255,), width=int(w * S))
    d.text(pt(cx, cy + 0.3), text, fill=(20, 20, 20, 255), font=font(tsize), anchor="mm")

def S1(color="#36B37E"):   # limit sign alone, big
    im = tile(color); d = ImageDraw.Draw(im); sign(d, 14.5, 14.5, 10, 2.4, tsize=8.6); return im

def S2(color="#36B37E"):   # limit sign, a bit smaller, thinner ring
    im = tile(color); d = ImageDraw.Draw(im); sign(d, 14.5, 14.5, 9, 2.0, tsize=7.8); return im

VARIANTS.clear(); VARIANTS.update({"S1 sign big": S1, "S2 sign": S2})


if __name__ == "__main__":
    pick = sys.argv[2] if len(sys.argv) > 2 else None
    if pick:
        export(VARIANTS[pick](), "SpeedBubbleIcon")
        print("exported", pick)
    else:
        cell = 260
        sheet = Image.new("RGB", (40 + cell * len(VARIANTS), 330), (241, 243, 245))
        d = ImageDraw.Draw(sheet); f = ImageFont.truetype("arialbd.ttf", 22)
        for i, (name, fn) in enumerate(VARIANTS.items()):
            im = fn(); x = 40 + i * cell
            big = im.resize((174, 174), Image.LANCZOS); sheet.paste(big, (x, 30), big)
            for s, px in ((87, x), (58, x + 100), (29, x + 170)):
                sm = im.resize((s, s), Image.LANCZOS); sheet.paste(sm, (px, 220), sm)
            d.text((x, 300), name, fill=(30, 30, 30), font=f)
        sheet.save(os.path.join(OUT, "bubble_icons.png")); print("sheet")
