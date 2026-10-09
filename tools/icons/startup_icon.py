"""Row icon for Startup Screen: blue tile, dark CarPlay screen behind, white video card with a
play triangle popping up in front (the accepted CarSplash logo idea, simplified for 29pt)."""
import os, sys
from PIL import Image, ImageDraw, ImageFont
from bubble_icon import tile, pt, rgb, S, PT, export, font

BLUE = "#0A59F7"
DARK = (38, 42, 52, 255)
WHITE = (255, 255, 255, 255)

def screen(d, box, r=2.6, dock=True, apps=3):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(pt(x0, y0, x1, y1), radius=r * S, fill=DARK)
    if dock:   # dock bar on the left + a row of app tiles
        d.rounded_rectangle(pt(x0 + 1.3, y0 + 1.3, x0 + 3.1, y1 - 1.3), radius=0.8 * S, fill=(120, 126, 140, 255))
        for i in range(apps):
            ax = x0 + 4.4 + i * 3.4
            d.rounded_rectangle(pt(ax, y0 + 1.5, ax + 2.4, y0 + 3.9), radius=0.7 * S, fill=(120, 126, 140, 255))

def card(d, box, r=2.4, play=BLUE, tri=3.6):
    x0, y0, x1, y1 = box
    d.rounded_rectangle(pt(x0, y0, x1, y1), radius=r * S, fill=WHITE)
    cx, cy = (x0 + x1) / 2 + 0.3, (y0 + y1) / 2
    d.polygon(pt(cx - tri * 0.8, cy - tri, cx - tri * 0.8, cy + tri, cx + tri * 0.9, cy), fill=rgb(play) + (255,))

def T1():   # screen back-left, card front-right (CarSplash logo layout)
    im = tile(BLUE); d = ImageDraw.Draw(im)
    screen(d, (3.5, 5, 20, 17.5))
    card(d, (10.5, 10, 25.5, 24))
    return im

def T2():   # bigger card, screen peeking at top-left
    im = tile(BLUE); d = ImageDraw.Draw(im)
    screen(d, (3, 4, 18, 15), apps=2)
    card(d, (8.5, 9, 26, 25), tri=4.2)
    return im

def T3():   # card only: white video card with blue play (no screen)
    im = tile(BLUE); d = ImageDraw.Draw(im)
    card(d, (4.5, 7, 24.5, 22), r=3, tri=4.6)
    return im

VARIANTS = {"T1 screen+card": T1, "T2 big card": T2, "T3 card only": T3}

if __name__ == "__main__":
    out = sys.argv[1]
    pick = sys.argv[2] if len(sys.argv) > 2 else None
    if pick:
        import bubble_icon; bubble_icon.OUT = out
        export(VARIANTS[pick](), "StartupScreenIcon"); print("exported", pick)
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
        sheet.save(os.path.join(out, "startup_icons.png")); print("sheet")
