"""SOKAK: OPERASYON logo (wordmark + emblem) rendered with supersampling."""
import os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageChops
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
F = os.path.join(ROOT, 'assets', 'fonts')
OUT = os.path.join(ROOT, 'assets', 'ui')
S = 3


def grad(size, stops, vertical=True):
    w, h = size
    n = h if vertical else w
    arr = np.zeros((h, w, 4), np.float32)
    t = np.linspace(0, 1, n)
    cols = np.zeros((n, 4))
    for i in range(len(stops) - 1):
        (t0, c0), (t1, c1) = stops[i], stops[i + 1]
        m = (t >= t0) & (t <= t1)
        k = ((t[m] - t0) / max(t1 - t0, 1e-6))[:, None]
        cols[m] = np.array(c0) * (1 - k) + np.array(c1) * k
    if vertical:
        arr[:] = cols[:, None, :]
    else:
        arr[:] = cols[None, :, :]
    return Image.fromarray(arr.astype(np.uint8), 'RGBA')


def emblem(size=512):
    W = size * S
    im = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    c = W / 2
    def hexp(r, rot=math.pi / 6):
        return [(c + r * math.cos(rot + i * math.pi / 3), c + r * math.sin(rot + i * math.pi / 3)) for i in range(6)]
    # outer hex with metal gradient
    mask = Image.new('L', (W, W), 0); ImageDraw.Draw(mask).polygon(hexp(W * 0.46), fill=255)
    rim = grad((W, W), [(0, (255, 214, 140, 255)), (0.45, (255, 138, 31, 255)), (1, (120, 40, 5, 255))])
    im.paste(rim, (0, 0), mask)
    mask2 = Image.new('L', (W, W), 0); ImageDraw.Draw(mask2).polygon(hexp(W * 0.40), fill=255)
    core = grad((W, W), [(0, (36, 42, 56, 255)), (1, (8, 10, 16, 255))])
    im.paste(core, (0, 0), mask2)
    d = ImageDraw.Draw(im)
    d.line(hexp(W * 0.40) + [hexp(W * 0.40)[0]], fill=(255, 190, 110, 200), width=S * 3)
    # crosshair ring + street-sign 'S' arrow
    r = W * 0.24
    d.ellipse([c - r, c - r, c + r, c + r], outline=(255, 160, 60, 255), width=S * 7)
    for a in range(4):
        ang = a * math.pi / 2
        p0 = (c + math.cos(ang) * r * 0.75, c + math.sin(ang) * r * 0.75)
        p1 = (c + math.cos(ang) * r * 1.45, c + math.sin(ang) * r * 1.45)
        d.line([p0, p1], fill=(255, 160, 60, 255), width=S * 7)
    f = ImageFont.truetype(os.path.join(F, 'RussoOne-Regular.ttf'), int(W * 0.34))
    d.text((c + W * 0.005, c + W * 0.01), 'S', font=f, fill=(0, 0, 0, 160), anchor='mm')
    d.text((c, c), 'S', font=f, fill=(255, 255, 255, 255), anchor='mm')
    # gloss
    gl = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(gl).ellipse([c - W * 0.42, c - W * 0.62, c + W * 0.42, c - W * 0.02], fill=(255, 255, 255, 38))
    gl.putalpha(ImageChops.multiply(gl.split()[3], mask2))
    im = Image.alpha_composite(im, gl)
    # glow
    g = im.split()[3].filter(ImageFilter.GaussianBlur(S * 14))
    glow = Image.new('RGBA', (W, W), (255, 120, 20, 0)); glow.putalpha(g.point(lambda v: int(v * 0.55)))
    im = Image.alpha_composite(glow, im)
    return im.resize((size, size), Image.LANCZOS)


def wordmark(w=1400, h=420):
    W, H = w * S, h * S
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    f = ImageFont.truetype(os.path.join(F, 'RussoOne-Regular.ttf'), int(H * 0.56))
    txt = 'SOKAK'
    mask = Image.new('L', (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.text((W / 2, H * 0.42), txt, font=f, fill=255, anchor='mm')
    # italic shear
    mask = mask.transform(mask.size, Image.AFFINE, (1, 0.18, -H * 0.075, 0, 1, 0), Image.BICUBIC)
    # extrusion / shadow
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    for k in range(1, 18):
        layer = Image.new('RGBA', (W, H), (80 - k * 3, 26, 6, 255))
        sh.paste(layer, (k * S // 2 + k, k * S // 2 + k), mask)
    chrome = grad((W, H), [(0.0, (255, 250, 240, 255)), (0.38, (255, 200, 120, 255)), (0.5, (255, 138, 31, 255)), (0.62, (200, 80, 10, 255)), (1.0, (255, 180, 90, 255))])
    face = Image.new('RGBA', (W, H), (0, 0, 0, 0)); face.paste(chrome, (0, 0), mask)
    # inner stroke
    edge = mask.filter(ImageFilter.MaxFilter(5)).point(lambda v: 255 if v > 10 else 0)
    outline = Image.new('RGBA', (W, H), (20, 10, 4, 255)); ol = Image.new('RGBA', (W, H), (0, 0, 0, 0)); ol.paste(outline, (0, 0), edge)
    im = Image.alpha_composite(im, sh)
    im = Image.alpha_composite(im, ol)
    im = Image.alpha_composite(im, face)
    # bullet-hole accents in the K
    d = ImageDraw.Draw(im)
    # sub title bar
    fy = H * 0.82
    d.polygon([(W * 0.2, fy - H * 0.07), (W * 0.82, fy - H * 0.07), (W * 0.8, fy + H * 0.07), (W * 0.18, fy + H * 0.07)], fill=(255, 138, 31, 255))
    f2 = ImageFont.truetype(os.path.join(F, 'Rajdhani-Bold.ttf'), int(H * 0.12))
    sub = '  '.join(list('OPERASYON'))
    d.text((W / 2, fy), sub, font=f2, fill=(20, 10, 4, 255), anchor='mm')
    g = im.split()[3].filter(ImageFilter.GaussianBlur(S * 12))
    glow = Image.new('RGBA', (W, H), (255, 110, 20, 0)); glow.putalpha(g.point(lambda v: int(v * 0.45)))
    im = Image.alpha_composite(glow, im)
    return im.resize((w, h), Image.LANCZOS)


e = emblem(); e.save(os.path.join(OUT, 'emblem.png'))
wm = wordmark(); wm.save(os.path.join(OUT, 'logo.png'))
small = Image.new('RGBA', (900, 220), (0, 0, 0, 0))
small.alpha_composite(e.resize((200, 200)), (0, 10))
small.alpha_composite(wm.resize((700, 210)), (200, 5))
small.save(os.path.join(OUT, 'logo_bar.png'))
e.resize((256, 256)).save(os.path.join(ROOT, 'icon.png'))
prev = Image.new('RGBA', (1400, 720), (18, 22, 30, 255)); prev.alpha_composite(e.resize((300, 300)), (550, 0)); prev.alpha_composite(wm, (0, 300)); prev.convert('RGB').save('/tmp/logo.png')
print('logo ok')
