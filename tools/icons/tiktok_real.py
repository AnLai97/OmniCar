"""TikTok row icon from the real glyph: the Simple Icons TikTok path (CC0) rasterized with a tiny
SVG-path flattener, laid on the dark tile in white over cyan / red offset copies."""
import os, re, sys
from PIL import Image, ImageDraw, ImageFont
from bubble_icon import tile, S, PT, export

CYAN, RED, WHITE = (37, 244, 238, 255), (254, 44, 85, 255), (255, 255, 255, 255)

def parse_path(d):
    """Flatten an SVG path (M/m L/l H/h V/v C/c S/s Z/z, implicit repeats) into subpath polygons."""
    tokens = re.findall(r"[MmLlHhVvCcSsZz]|-?\d*\.?\d+(?:e-?\d+)?", d)
    polys, cur, pos, start, cmd, prev_c2 = [], [], (0.0, 0.0), (0.0, 0.0), None, None
    i = 0
    def num(): nonlocal i; v = float(tokens[i]); i += 1; return v
    def bezier(p0, p1, p2, p3, n=24):
        for k in range(1, n + 1):
            t = k / n; u = 1 - t
            cur.append((u*u*u*p0[0] + 3*u*u*t*p1[0] + 3*u*t*t*p2[0] + t*t*t*p3[0],
                        u*u*u*p0[1] + 3*u*u*t*p1[1] + 3*u*t*t*p2[1] + t*t*t*p3[1]))
    while i < len(tokens):
        if re.match(r"[A-Za-z]", tokens[i]): cmd = tokens[i]; i += 1
        rel = cmd.islower(); c = cmd.upper()
        if c == "M":
            x, y = num(), num()
            if rel: x += pos[0]; y += pos[1]
            if cur: polys.append(cur)
            cur = [(x, y)]; pos = start = (x, y); cmd = "l" if rel else "L"
        elif c == "L":
            x, y = num(), num()
            if rel: x += pos[0]; y += pos[1]
            cur.append((x, y)); pos = (x, y)
        elif c == "H":
            x = num(); x = x + pos[0] if rel else x
            cur.append((x, pos[1])); pos = (x, pos[1])
        elif c == "V":
            y = num(); y = y + pos[1] if rel else y
            cur.append((pos[0], y)); pos = (pos[0], y)
        elif c in "CS":
            if c == "C":
                x1, y1 = num(), num()
            else:
                x1, y1 = (2*pos[0]-prev_c2[0], 2*pos[1]-prev_c2[1]) if prev_c2 else pos
                if rel: x1 -= pos[0]; y1 -= pos[1]
            x2, y2, x, y = num(), num(), num(), num()
            if rel:
                x1 += pos[0]; y1 += pos[1]; x2 += pos[0]; y2 += pos[1]; x += pos[0]; y += pos[1]
            bezier(pos, (x1, y1), (x2, y2), (x, y)); pos = (x, y); prev_c2 = (x2, y2); continue
        elif c == "Z":
            if cur: polys.append(cur); cur = []
            pos = start
        prev_c2 = None
    if cur: polys.append(cur)
    return polys

def glyph_polys(svg_path):
    d = re.search(r'd="([^"]+)"', open(svg_path, encoding="utf-8").read()).group(1)
    return parse_path(d)

def draw_glyph(d, polys, box, color, dx=0, dy=0):
    xs = [x for p in polys for x, _ in p]; ys = [y for p in polys for _, y in p]
    x0, y0, x1, y1 = min(xs), min(ys), max(xs), max(ys)
    bx0, by0, bx1, by1 = box
    k = min((bx1 - bx0) / (x1 - x0), (by1 - by0) / (y1 - y0))
    ox = bx0 + ((bx1 - bx0) - (x1 - x0) * k) / 2 - x0 * k + dx
    oy = by0 + ((by1 - by0) - (y1 - y0) * k) / 2 - y0 * k + dy
    for p in polys:
        d.polygon([((x * k + ox) * S, (y * k + oy) * S) for x, y in p], fill=color)

def icon(svg, bg="#161616", box=(6.5, 5.5, 22.5, 23.5), off=0.9):
    im = tile(bg); d = ImageDraw.Draw(im); polys = glyph_polys(svg)
    draw_glyph(d, polys, box, CYAN, -off, -off)
    draw_glyph(d, polys, box, RED, off, off)
    draw_glyph(d, polys, box, WHITE)
    return im

if __name__ == "__main__":
    svg = sys.argv[1]; out = sys.argv[2]; pick = sys.argv[3] if len(sys.argv) > 3 else None
    variants = {"R1 dark": lambda: icon(svg), "R2 black": lambda: icon(svg, bg="#000000"),
                "R3 bigger": lambda: icon(svg, box=(5.5, 4.5, 23.5, 24.5), off=1.0)}
    if pick:
        import bubble_icon; bubble_icon.OUT = out
        export(variants[pick](), "TikTokIcon"); print("exported", pick)
    else:
        cell = 260
        sheet = Image.new("RGB", (40 + cell * len(variants), 330), (241, 243, 245))
        d = ImageDraw.Draw(sheet); f = ImageFont.truetype("arialbd.ttf", 22)
        for i, (name, fn) in enumerate(variants.items()):
            im = fn(); x = 40 + i * cell
            big = im.resize((174, 174), Image.LANCZOS); sheet.paste(big, (x, 30), big)
            for s, px in ((87, x), (58, x + 100), (29, x + 170)):
                sm = im.resize((s, s), Image.LANCZOS); sheet.paste(sm, (px, 220), sm)
            d.text((x, 300), name, fill=(30, 30, 30), font=f)
        sheet.save(os.path.join(out, "tiktok_real.png")); print("sheet")
