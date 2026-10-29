"""Generates kill medals (HUD badges) and blood FX sprites with PIL (supersampled).
Outputs: assets/ui/medals/*.png, assets/fx/blood_drop.png, blood_splat{0,1,2}.png, blood_screen.png
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MED = os.path.join(ROOT, 'assets', 'ui', 'medals')
FX = os.path.join(ROOT, 'assets', 'fx')
os.makedirs(MED, exist_ok=True)
S = 4          # supersample
N = 512        # output size
W = N * S
FONT_DIRS = [os.path.join(ROOT, 'assets', 'fonts'), '/usr/share/fonts']


def font(name, size):
    for d in FONT_DIRS:
        for r, _, fs in os.walk(d):
            for f in fs:
                if f.lower().startswith(name.lower()) and f.endswith('.ttf'):
                    return ImageFont.truetype(os.path.join(r, f), size)
    return ImageFont.load_default()


def poly_hex(cx, cy, r, rot=0.0):
    return [(cx + r * math.cos(rot + i * math.pi / 3), cy + r * math.sin(rot + i * math.pi / 3)) for i in range(6)]


def shield(cx, cy, r):
    # pointed-bottom shield
    pts = []
    for i in range(0, 181, 6):
        a = math.radians(180 + i)
        pts.append((cx + r * math.cos(a), cy - r * 0.15 + r * 0.75 * math.sin(a)))
    pts += [(cx + r, cy + r * 0.25), (cx + r * 0.55, cy + r * 0.75), (cx, cy + r), (cx - r * 0.55, cy + r * 0.75), (cx - r, cy + r * 0.25)]
    return pts


def lin_grad(size, c0, c1, vertical=True):
    g = Image.new('RGBA', size)
    d = ImageDraw.Draw(g)
    n = size[1] if vertical else size[0]
    for i in range(n):
        t = i / max(n - 1, 1)
        c = tuple(int(c0[k] + (c1[k] - c0[k]) * t) for k in range(4))
        if vertical:
            d.line([(0, i), (size[0], i)], fill=c)
        else:
            d.line([(i, 0), (i, size[1])], fill=c)
    return g


def metal(size, base, hi):
    """Brushed metallic vertical gradient with a bright band."""
    g = Image.new('RGBA', size)
    d = ImageDraw.Draw(g)
    h = size[1]
    for i in range(h):
        t = i / h
        k = 0.5 + 0.5 * math.cos((t - 0.3) * math.pi * 2.2)
        k = k ** 2
        c = tuple(int(base[j] + (hi[j] - base[j]) * k) for j in range(3)) + (255,)
        d.line([(0, i), (size[0], i)], fill=c)
    return g


def fill_shape(img, pts, tex):
    m = Image.new('L', img.size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    img.paste(tex, (0, 0), m)
    return m


def glow(img, color, radius):
    a = img.split()[3].filter(ImageFilter.GaussianBlur(radius))
    g = Image.new('RGBA', img.size, color)
    g.putalpha(a.point(lambda v: min(255, int(v * 1.6))))
    out = Image.alpha_composite(g, img)
    return out


def skull(d, cx, cy, s, col, hole=(0, 0, 0, 0)):
    # cranium
    d.ellipse([cx - s, cy - s * 1.05, cx + s, cy + s * 0.75], fill=col)
    # cheeks / jaw
    d.rounded_rectangle([cx - s * 0.62, cy + s * 0.25, cx + s * 0.62, cy + s * 1.15], radius=s * 0.22, fill=col)
    # eyes
    for sx in (-1, 1):
        ex = cx + sx * s * 0.4
        d.polygon([(ex - s * 0.3, cy - s * 0.02), (ex + s * 0.3, cy - s * 0.02), (ex + s * 0.25 * sx * 0 + s * 0.22, cy + s * 0.32),
                   (ex - s * 0.22, cy + s * 0.32)], fill=hole)
        d.ellipse([ex - s * 0.3, cy - s * 0.2, ex + s * 0.3, cy + s * 0.34], fill=hole)
    # nose
    d.polygon([(cx, cy + s * 0.38), (cx - s * 0.13, cy + s * 0.62), (cx + s * 0.13, cy + s * 0.62)], fill=hole)
    # teeth gaps
    for i in range(-2, 3):
        x = cx + i * s * 0.2
        d.rectangle([x - s * 0.025, cy + s * 0.8, x + s * 0.025, cy + s * 1.15], fill=hole)


def crosshair(d, cx, cy, r, col, w):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=w)
    for a in range(4):
        ang = a * math.pi / 2
        x0, y0 = cx + math.cos(ang) * r * 0.55, cy + math.sin(ang) * r * 0.55
        x1, y1 = cx + math.cos(ang) * r * 1.35, cy + math.sin(ang) * r * 1.35
        d.line([(x0, y0), (x1, y1)], fill=col, width=w)


def knife_icon(d, cx, cy, s, col):
    ang = math.radians(-40)
    def R(x, y):
        return (cx + x * math.cos(ang) - y * math.sin(ang), cy + x * math.sin(ang) + y * math.cos(ang))
    blade = [R(-s * 0.1, -s * 0.16), R(s * 1.1, -s * 0.16), R(s * 1.35, 0.0), R(s * 1.0, s * 0.16), R(-s * 0.1, s * 0.16)]
    d.polygon(blade, fill=col)
    guard = [R(-s * 0.16, -s * 0.32), R(-s * 0.06, -s * 0.32), R(-s * 0.06, s * 0.32), R(-s * 0.16, s * 0.32)]
    d.polygon(guard, fill=col)
    handle = [R(-s * 1.0, -s * 0.13), R(-s * 0.18, -s * 0.13), R(-s * 0.18, s * 0.13), R(-s * 1.0, s * 0.13)]
    d.polygon(handle, fill=col)


def grenade_icon(d, cx, cy, s, col, hole):
    d.ellipse([cx - s * 0.7, cy - s * 0.6, cx + s * 0.7, cy + s * 1.0], fill=col)
    d.rectangle([cx - s * 0.28, cy - s * 0.9, cx + s * 0.28, cy - s * 0.5], fill=col)
    d.polygon([(cx + s * 0.2, cy - s * 0.88), (cx + s * 0.9, cy - s * 0.55), (cx + s * 0.85, cy + s * 0.2), (cx + s * 0.7, cy + s * 0.15),
               (cx + s * 0.7, cy - s * 0.42), (cx + s * 0.2, cy - s * 0.66)], fill=col)
    d.ellipse([cx - s * 0.75, cy - s * 1.15, cx - s * 0.25, cy - s * 0.65], outline=col, width=int(s * 0.1))
    for i in (-1, 0, 1):
        d.line([(cx - s * 0.7, cy + s * 0.2 + i * s * 0.3), (cx + s * 0.7, cy + s * 0.2 + i * s * 0.3)], fill=hole, width=int(s * 0.06))


def wings(img, cx, cy, r, col, tiers):
    d = ImageDraw.Draw(img)
    for side in (-1, 1):
        for k in range(tiers):
            y = cy - r * 0.35 + k * r * 0.32
            x0 = cx + side * r * 0.85
            x1 = cx + side * (r * 1.55 - k * r * 0.18)
            pts = [(x0, y), (x1, y - r * 0.12), (x1 - side * r * 0.12, y + r * 0.12), (x0, y + r * 0.22)]
            d.polygon(pts, fill=col)


def medal(name, kind, rim_base, rim_hi, core0, core1, icon_col, label=None, tiers=0, num=None):
    img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    cx = cy = W / 2
    r = W * (0.29 if tiers else 0.34)
    if tiers:
        wl = Image.new('RGBA', (W, W), (0, 0, 0, 0))
        wings(wl, cx, cy, r, rim_hi + (255,), tiers)
        wl2 = Image.new('RGBA', (W, W), (0, 0, 0, 0))
        wings(wl2, cx, cy + S * 3, r, (0, 0, 0, 160), tiers)
        img = Image.alpha_composite(img, wl2)
        img = Image.alpha_composite(img, wl)
    # outer rim
    rim = metal((W, W), rim_base, rim_hi)
    shape = shield(cx, cy, r) if kind in ('head', 'streak') else poly_hex(cx, cy, r, math.pi / 6)
    shadow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).polygon([(x, y + S * 6) for x, y in shape], fill=(0, 0, 0, 170))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(S * 6)))
    layer = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    fill_shape(layer, shape, rim)
    # inner core
    inner = shield(cx, cy, r * 0.84) if kind in ('head', 'streak') else poly_hex(cx, cy, r * 0.84, math.pi / 6)
    core = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    rg = Image.new('RGBA', (W, W))
    dr = ImageDraw.Draw(rg)
    for i in range(60, 0, -1):
        t = i / 60
        c = tuple(int(core1[k] + (core0[k] - core1[k]) * t) for k in range(3)) + (255,)
        rr = r * 1.1 * t
        dr.ellipse([cx - rr, cy - rr * 1.1 - r * 0.15, cx + rr, cy + rr * 1.1 - r * 0.15], fill=c)
    fill_shape(core, inner, rg)
    # inner bevel line
    ImageDraw.Draw(core).line(inner + [inner[0]], fill=rim_hi + (200,), width=S * 3)
    layer = Image.alpha_composite(layer, core)
    # icon
    ic = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    di = ImageDraw.Draw(ic)
    hole = (0, 0, 0, 0)
    if kind in ('kill', 'multi', 'head', 'streak'):
        skull(di, cx, cy - r * 0.12, r * 0.38, icon_col + (255,), hole)
    elif kind == 'knife':
        knife_icon(di, cx, cy, r * 0.6, icon_col + (255,))
    elif kind == 'grenade':
        grenade_icon(di, cx, cy, r * 0.42, icon_col + (255,), hole)
    # punch holes properly: draw skull on separate layer where hole alpha=0 means transparent
    if kind == 'head':
        ch = Image.new('RGBA', (W, W), (0, 0, 0, 0))
        crosshair(ImageDraw.Draw(ch), cx, cy - r * 0.05, r * 0.52, (255, 60, 40, 255), S * 7)
        ic = Image.alpha_composite(ic, ch)
    ic = glow(ic, icon_col + (150,), S * 8)
    layer = Image.alpha_composite(layer, ic)
    # glossy highlight
    gl = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(gl).ellipse([cx - r * 0.9, cy - r * 1.35, cx + r * 0.9, cy - r * 0.15], fill=(255, 255, 255, 46))
    m = Image.new('L', (W, W), 0)
    ImageDraw.Draw(m).polygon(inner, fill=255)
    gl.putalpha(ImageChops.multiply(gl.split()[3], m))
    layer = Image.alpha_composite(layer, gl)
    img = Image.alpha_composite(img, layer)
    # number badge
    if num:
        f = font('Rajdhani-Bold', int(W * 0.17))
        d = ImageDraw.Draw(img)
        bx, by, br = cx, cy + r * 0.62, r * 0.3
        d.ellipse([bx - br, by - br, bx + br, by + br], fill=(20, 12, 8, 255), outline=rim_hi + (255,), width=S * 5)
        d.text((bx, by + S * 2), num, font=f, fill=(255, 240, 210, 255), anchor='mm')
    img = glow(img, rim_hi + (110,), S * 14)
    img = img.resize((N, N), Image.LANCZOS)
    img.save(os.path.join(MED, name + '.png'))
    print('medal', name)


GOLD = ((150, 95, 20), (255, 225, 120))
SILVER = ((110, 115, 125), (240, 245, 255))
RED = ((140, 20, 15), (255, 120, 90))
PURPLE = ((80, 30, 140), (220, 160, 255))
CYAN = ((10, 90, 130), (140, 235, 255))

medal('kill', 'kill', *SILVER, (40, 44, 52), (12, 14, 18), (235, 238, 245))
medal('head', 'head', *GOLD, (80, 20, 10), (20, 6, 4), (255, 236, 200))
medal('double', 'multi', *RED, (70, 12, 10), (18, 4, 4), (255, 225, 210), tiers=1, num='2')
medal('triple', 'multi', *GOLD, (70, 40, 6), (20, 10, 2), (255, 236, 190), tiers=2, num='3')
medal('quad', 'multi', *PURPLE, (45, 14, 80), (12, 4, 22), (240, 220, 255), tiers=3, num='4')
medal('penta', 'multi', *CYAN, (6, 50, 70), (2, 12, 18), (220, 250, 255), tiers=3, num='5')
medal('knife', 'knife', *SILVER, (60, 20, 18), (15, 5, 5), (255, 235, 230))
medal('grenade', 'grenade', *GOLD, (40, 50, 20), (10, 14, 4), (255, 240, 200))
medal('streak', 'streak', *RED, (90, 25, 8), (24, 6, 2), (255, 210, 150), tiers=2)


# ---------------------------------------------------------------- blood sprites (noise based, realistic)
import numpy as np


def vnoise(w, h, cell, rnd):
    g = rnd.random((h // cell + 3, w // cell + 3)).astype(np.float32)
    im = Image.fromarray((g * 255).astype(np.uint8)).resize(((w // cell + 3) * cell, (h // cell + 3) * cell), Image.BICUBIC)
    return np.asarray(im, dtype=np.float32)[:h, :w] / 255.0


def fbm(w, h, rnd, base=64, oct=5):
    t = np.zeros((h, w), np.float32); a = 1.0; s = 0.0
    c = base
    for _ in range(oct):
        t += vnoise(w, h, max(2, c), rnd) * a; s += a; a *= 0.5; c //= 2
    return t / s


def colorize(mask, wet=True):
    """mask float 0..1 -> RGBA blood with darker rims and glossy core."""
    h, w = mask.shape
    m = np.clip(mask, 0, 1)
    blur = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(max(2, w // 120))), np.float32) / 255
    edge = np.clip(1.0 - blur, 0, 1)
    r = 120 - 70 * edge
    g = 4 + 2 * (1 - edge)
    b = 6 + 2 * (1 - edge)
    rgba = np.zeros((h, w, 4), np.float32)
    rgba[..., 0] = r; rgba[..., 1] = g; rgba[..., 2] = b
    rgba[..., 3] = m * 255 * (0.82 + 0.18 * edge)
    return Image.fromarray(np.clip(rgba, 0, 255).astype(np.uint8), 'RGBA')


def splat(size, seed, density=1.0):
    rnd = np.random.default_rng(seed)
    w = size
    yy, xx = np.mgrid[0:w, 0:w].astype(np.float32)
    c = w / 2
    d = np.hypot(xx - c, yy - c) / (w / 2)
    n = fbm(w, w, rnd, base=w // 6)
    core = (1.0 - d * 1.55) + (n - 0.5) * 1.1
    m = np.clip((core - 0.05) * 8, 0, 1)
    img = Image.fromarray((m * 255).astype(np.uint8))
    dr = ImageDraw.Draw(img)
    # spatter: elongated droplets radiating out
    for i in range(int(70 * density)):
        a = rnd.random() * math.tau
        rr = w * (0.22 + rnd.random() ** 1.6 * 0.26)
        s = w * (0.004 + rnd.random() ** 2 * 0.022)
        x, y = c + math.cos(a) * rr, c + math.sin(a) * rr
        el = 1.0 + rnd.random() * 2.2
        pts = [(x + math.cos(a) * s * el * math.cos(t) - math.sin(a) * s * math.sin(t),
                y + math.sin(a) * s * el * math.cos(t) + math.cos(a) * s * math.sin(t)) for t in np.linspace(0, math.tau, 18)]
        dr.polygon(pts, fill=255)
    img = img.filter(ImageFilter.GaussianBlur(1.0))
    return colorize(np.asarray(img, np.float32) / 255)


for i in range(3):
    splat(512, 11 + i * 7, 1.0 + i * 0.3).save(os.path.join(FX, f'blood_splat{i}.png'))
# particle sprite: soft droplet mist
rnd = np.random.default_rng(3)
w = 128
yy, xx = np.mgrid[0:w, 0:w].astype(np.float32)
d = np.hypot(xx - w / 2, yy - w / 2) / (w / 2)
m = np.clip((1 - d * 1.3) + (fbm(w, w, rnd, base=24) - 0.5) * 0.9, 0, 1) ** 0.8
colorize(m).save(os.path.join(FX, 'blood_drop.png'))

# screen splatter: soft wet blood at the edges, transparent centre
SW, SH = 1600, 900
rnd = np.random.default_rng(5)
yy, xx = np.mgrid[0:SH, 0:SW].astype(np.float32)
ex = np.abs(xx - SW / 2) / (SW / 2)
ey = np.abs(yy - SH / 2) / (SH / 2)
edge = np.maximum(ex ** 2.2, ey ** 2.6 * 0.85)
n = fbm(SW, SH, rnd, base=180, oct=6)
m = np.clip((edge * 1.1 + (n - 0.5) * 1.6 - 0.78) * 2.2, 0, 1)
img = Image.fromarray((m * 255).astype(np.uint8))
dr = ImageDraw.Draw(img)
rr = random.Random(9)
for i in range(9):   # drips running down from the top band
    x = rr.choice([rr.randint(20, 300), rr.randint(SW - 300, SW - 20)])
    y0 = rr.randint(0, 90); ln = rr.randint(40, 150); wd = rr.randint(7, 13)
    for k in range(ln):
        ww = wd * (1 - k / ln * 0.5)
        dr.ellipse([x - ww / 2, y0 + k - ww / 2, x + ww / 2, y0 + k + ww / 2], fill=235)
    dr.ellipse([x - wd, y0 + ln - wd, x + wd, y0 + ln + wd * 1.3], fill=240)
img = img.filter(ImageFilter.GaussianBlur(1.5))
scr = colorize(np.asarray(img, np.float32) / 255)
a = np.asarray(scr.split()[3], np.float32) * 0.9
scr.putalpha(Image.fromarray(a.astype(np.uint8)))
scr.save(os.path.join(FX, 'blood_screen.png'))
print('blood sprites ok')
