"""Rank emblems (original designs, Turkish military rank names) -> assets/ui/ranks/r<N>.png"""
from PIL import Image, ImageDraw, ImageFilter
import math, os
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'ui', 'ranks')
os.makedirs(OUT, exist_ok=True)
# name, tier colour, insignia kind, count
RANKS = [
    ("Er I", (176, 112, 64), "chev", 1), ("Er II", (176, 112, 64), "chev", 2), ("Er III", (176, 112, 64), "chev", 3),
    ("Onbaşı I", (178, 190, 205), "chev", 2), ("Onbaşı II", (178, 190, 205), "chev", 3),
    ("Çavuş I", (236, 186, 70), "chevbar", 2), ("Çavuş II", (236, 186, 70), "chevbar", 3),
    ("Astsubay I", (236, 186, 70), "chevstar", 1), ("Astsubay II", (236, 186, 70), "chevstar", 2),
    ("Teğmen", (70, 210, 200), "star", 1), ("Üsteğmen", (70, 210, 200), "star", 2), ("Yüzbaşı", (70, 210, 200), "star", 3),
    ("Binbaşı", (170, 110, 255), "wstar", 1), ("Yarbay", (170, 110, 255), "wstar", 2), ("Albay", (170, 110, 255), "wstar", 3),
    ("Tuğgeneral", (255, 80, 70), "gstar", 1), ("Korgeneral", (255, 80, 70), "gstar", 3), ("Mareşal", (255, 196, 40), "marshal", 1),
]
S = 512


def star(d, cx, cy, r, fill, rot=-90):
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * 0.42
        a = math.radians(rot + i * 36)
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    d.polygon(pts, fill=fill)


def chevron(d, cx, cy, w, h, t, fill):
    d.polygon([(cx - w, cy), (cx, cy - h), (cx + w, cy), (cx + w, cy + t), (cx, cy - h + t), (cx - w, cy + t)], fill=fill)


def shield(col, glow):
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # outer glow
    g = Image.new('RGBA', (S, S), (0, 0, 0, 0)); gd = ImageDraw.Draw(g)
    poly = [(S * .5, S * .06), (S * .86, S * .18), (S * .84, S * .58), (S * .5, S * .94), (S * .16, S * .58), (S * .14, S * .18)]
    gd.polygon(poly, fill=col + (int(150 * glow),))
    g = g.filter(ImageFilter.GaussianBlur(22))
    im.alpha_composite(g)
    d = ImageDraw.Draw(im)
    d.polygon(poly, fill=(14, 16, 22, 255))
    inner = [(S * .5, S * .11), (S * .815, S * .215), (S * .795, S * .565), (S * .5, S * .885), (S * .205, S * .565), (S * .185, S * .215)]
    # metallic rim gradient
    rim = Image.new('RGBA', (S, S), (0, 0, 0, 0)); rd = ImageDraw.Draw(rim)
    for y in range(S):
        k = y / S
        c = tuple(int(min(255, v * (1.25 - 0.6 * k))) for v in col) + (255,)
        rd.line([(0, y), (S, y)], fill=c)
    mask = Image.new('L', (S, S), 0); md = ImageDraw.Draw(mask)
    md.polygon(poly, fill=255); md.polygon(inner, fill=0)
    im.paste(rim, (0, 0), mask)
    # inner field dark gradient
    fld = Image.new('RGBA', (S, S), (0, 0, 0, 0)); fdd = ImageDraw.Draw(fld)
    for y in range(S):
        k = y / S
        fdd.line([(0, y), (S, y)], fill=(int(20 + 30 * (1 - k)), int(24 + 30 * (1 - k)), int(34 + 36 * (1 - k)), 255))
    m2 = Image.new('L', (S, S), 0); ImageDraw.Draw(m2).polygon(inner, fill=255)
    im.paste(fld, (0, 0), m2)
    return im


def emblem(i, name, col, kind, n):
    glow = 0.35 + i / len(RANKS) * 0.65
    im = shield(col, glow)
    d = ImageDraw.Draw(im)
    light = tuple(min(255, int(c * 1.25 + 30)) for c in col) + (255,)
    cx = S / 2
    if kind in ('chev', 'chevbar', 'chevstar'):
        for k in range(n):
            chevron(d, cx, S * 0.56 + k * 52 - (n - 1) * 26, 120, 82, 30, light)
        if kind == 'chevbar':
            d.rounded_rectangle([cx - 105, S * 0.66 + (n - 1) * 26, cx + 105, S * 0.66 + (n - 1) * 26 + 24], 8, fill=light)
        if kind == 'chevstar':
            star(d, cx, S * 0.3, 52, light)
    elif kind in ('star', 'wstar', 'gstar'):
        offs = {1: [0], 2: [-70, 70], 3: [-110, 0, 110]}[n]
        for k, ox in enumerate(offs):
            star(d, cx + ox, S * 0.47 - (12 if (n == 3 and ox == 0) else 0), 62 if n < 3 else 52, light)
        if kind in ('wstar', 'gstar'):
            for k in range(11):
                ang = math.radians(15 + k * 15)
                px, py = cx + 150 * math.cos(ang), S * 0.47 + 120 * math.sin(ang)
                d.ellipse([px - 15, py - 9, px + 15, py + 9], fill=light)
        if kind == 'gstar':
            d.rounded_rectangle([cx - 120, S * 0.68, cx + 120, S * 0.72], 6, fill=light)
    elif kind == 'marshal':
        star(d, cx, S * 0.44, 110, light)
        star(d, cx, S * 0.44, 60, (255, 240, 200, 255))
        for k in range(13):
            ang = math.radians(10 + k * 13.3)
            px, py = cx + 165 * math.cos(ang), S * 0.44 + 140 * math.sin(ang)
            d.ellipse([px - 18, py - 11, px + 18, py + 11], fill=light)
    im = im.resize((256, 256), Image.LANCZOS)
    im.save(os.path.join(OUT, 'r%d.png' % i))


for i, r in enumerate(RANKS):
    emblem(i, *r)
sheet = Image.new('RGBA', (256 * 6, 256 * 3), (20, 22, 28, 255))
for i in range(len(RANKS)):
    sheet.alpha_composite(Image.open(os.path.join(OUT, 'r%d.png' % i)), ((i % 6) * 256, (i // 6) * 256))
sheet.convert('RGB').resize((768, 384)).save('/tmp/ranks_sheet.jpg')
print('ok', len(RANKS))
