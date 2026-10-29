"""SOKAK app icon: hex shield, Istanbul skyline (Galata tower, mosque, minarets), stencil 'S' in a crosshair."""
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
import math, os
R = os.path.join(os.path.dirname(__file__), '..')
N = 1024
S = 4  # supersample


def hexpts(cx, cy, r, rot=30):
    return [(cx + r * math.cos(math.radians(rot + i * 60)), cy + r * math.sin(math.radians(rot + i * 60))) for i in range(6)]


def grad(w, h, c0, c1, vertical=True):
    g = Image.new('RGBA', (w, h))
    d = ImageDraw.Draw(g)
    for i in range(h if vertical else w):
        t = i / max((h if vertical else w) - 1, 1)
        c = tuple(int(c0[k] + (c1[k] - c0[k]) * t) for k in range(4))
        if vertical:
            d.line([(0, i), (w, i)], fill=c)
        else:
            d.line([(i, 0), (i, h)], fill=c)
    return g


def mask_poly(pts, size):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    return m


W = N * S
c = W / 2
img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
# outer glow
glow = Image.new('L', (W, W), 0)
ImageDraw.Draw(glow).polygon(hexpts(c, c, W * 0.47), fill=255)
glow = glow.filter(ImageFilter.GaussianBlur(W * 0.025))
img.paste(Image.new('RGBA', (W, W), (255, 120, 20, 150)), (0, 0), glow)
# rim (orange bevel)
rim = grad(W, W, (255, 196, 70, 255), (196, 70, 10, 255))
img.paste(rim, (0, 0), mask_poly(hexpts(c, c, W * 0.455), (W, W)))
dark_rim = mask_poly(hexpts(c, c, W * 0.415), (W, W))
img.paste(Image.new('RGBA', (W, W), (40, 16, 4, 255)), (0, 0), dark_rim)
# inner field: night-blue gradient
field = grad(W, W, (40, 54, 78, 255), (8, 11, 18, 255))
fm = mask_poly(hexpts(c, c, W * 0.40), (W, W))
img.paste(field, (0, 0), fm)
# sunset glow behind skyline
sun = Image.new('L', (W, W), 0)
ImageDraw.Draw(sun).ellipse([c - W * 0.3, c + W * 0.02, c + W * 0.3, c + W * 0.5], fill=200)
sun = ImageChops.multiply(sun.filter(ImageFilter.GaussianBlur(W * 0.06)), fm)
img.paste(Image.new('RGBA', (W, W), (255, 110, 30, 255)), (0, 0), sun.point(lambda v: int(v * 0.55)))
# skyline silhouette (Galata tower left, mosque with dome + minarets right, houses)
sk = Image.new('L', (W, W), 0)
d = ImageDraw.Draw(sk)
base = c + W * 0.27
u = W / 100.0
d.rectangle([c - 36 * u, base - 6 * u, c + 36 * u, base + 20 * u], fill=255)
for (x, w, h) in [(-33, 7, 9), (-26, 6, 12), (-20, 8, 8), (17, 7, 10), (24, 9, 7), (30, 6, 11)]:
    d.rectangle([c + x * u, base - h * u, c + (x + w) * u, base], fill=255)
    d.polygon([(c + x * u, base - h * u), (c + (x + w / 2) * u, base - (h + 3) * u), (c + (x + w) * u, base - h * u)], fill=255)
# Galata tower
tx = c - 15 * u
d.rectangle([tx - 3.2 * u, base - 26 * u, tx + 3.2 * u, base], fill=255)
d.rectangle([tx - 4 * u, base - 28 * u, tx + 4 * u, base - 25 * u], fill=255)
d.polygon([(tx - 4 * u, base - 28 * u), (tx, base - 37 * u), (tx + 4 * u, base - 28 * u)], fill=255)
# mosque
mx = c + 6 * u
d.rectangle([mx - 9 * u, base - 9 * u, mx + 9 * u, base], fill=255)
d.pieslice([mx - 8 * u, base - 18 * u, mx + 8 * u, base - 2 * u], 180, 360, fill=255)
d.rectangle([mx - 0.5 * u, base - 21 * u, mx + 0.5 * u, base - 17 * u], fill=255)
for mxx in (mx - 12 * u, mx + 12 * u):
    d.rectangle([mxx - 1.2 * u, base - 27 * u, mxx + 1.2 * u, base], fill=255)
    d.polygon([(mxx - 1.4 * u, base - 27 * u), (mxx, base - 33 * u), (mxx + 1.4 * u, base - 27 * u)], fill=255)
    d.rectangle([mxx - 1.9 * u, base - 21 * u, mxx + 1.9 * u, base - 20 * u], fill=255)
sk = ImageChops.multiply(sk, fm)
img.paste(Image.new('RGBA', (W, W), (12, 8, 10, 255)), (0, 0), sk)
# crosshair ring + ticks (orange)
ch = Image.new('L', (W, W), 0)
d = ImageDraw.Draw(ch)
rr = W * 0.205
cy = c - W * 0.045
d.ellipse([c - rr, cy - rr, c + rr, cy + rr], outline=255, width=int(W * 0.014))
for a in range(4):
    ang = math.radians(a * 90)
    x0, y0 = c + math.cos(ang) * rr * 0.82, cy + math.sin(ang) * rr * 0.82
    x1, y1 = c + math.cos(ang) * rr * 1.32, cy + math.sin(ang) * rr * 1.32
    d.line([(x0, y0), (x1, y1)], fill=255, width=int(W * 0.016))
ch = ImageChops.multiply(ch, fm)
img.paste(Image.new('RGBA', (W, W), (255, 150, 40, 255)), (0, 0), ch)
# stencil "S"
font = ImageFont.truetype(os.path.join(R, 'assets/fonts/RussoOne-Regular.ttf'), int(W * 0.36))
sm = Image.new('L', (W, W), 0)
ds = ImageDraw.Draw(sm)
bb = ds.textbbox((0, 0), 'S', font=font)
tx0 = c - (bb[2] - bb[0]) / 2 - bb[0]
ty0 = cy - (bb[3] - bb[1]) / 2 - bb[1]
ds.text((tx0, ty0), 'S', font=font, fill=255)
# stencil bridges
cut = Image.new('L', (W, W), 255)
dc = ImageDraw.Draw(cut)
dc.rectangle([c - W * 0.006, cy - W * 0.2, c + W * 0.006, cy - W * 0.085], fill=0)
dc.rectangle([c - W * 0.006, cy + W * 0.085, c + W * 0.006, cy + W * 0.2], fill=0)
sm = ImageChops.multiply(sm, cut)
shadow = sm.filter(ImageFilter.GaussianBlur(W * 0.01))
img.paste(Image.new('RGBA', (W, W), (0, 0, 0, 200)), (int(W * 0.008), int(W * 0.012)), shadow)
sg = grad(W, W, (255, 255, 255, 255), (255, 205, 120, 255))
img.paste(sg, (0, 0), sm)
# glossy highlight on the top half of the field
hl = Image.new('L', (W, W), 0)
ImageDraw.Draw(hl).ellipse([c - W * 0.5, c - W * 0.9, c + W * 0.5, c - W * 0.05], fill=40)
hl = ImageChops.multiply(hl.filter(ImageFilter.GaussianBlur(W * 0.02)), fm)
img.paste(Image.new('RGBA', (W, W), (255, 255, 255, 255)), (0, 0), hl)
out = img.resize((N, N), Image.LANCZOS)
out.save(os.path.join(R, 'assets/ui/icon_1024.png'))
out.resize((512, 512), Image.LANCZOS).save(os.path.join(R, 'assets/ui/emblem.png'))
out.resize((256, 256), Image.LANCZOS).save(os.path.join(R, 'icon.png'))
out.save(os.path.join(R, 'icon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print('icon ok')
