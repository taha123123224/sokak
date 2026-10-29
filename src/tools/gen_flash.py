"""Muzzle flash sprites (front star, side cone) - additive, supersampled."""
import os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'fx')
S = 4


def front(seed, n=256):
    rr = random.Random(seed)
    W = n * S
    im = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = W / 2
    prongs = rr.choice([4, 5, 6])
    for k in range(prongs):
        a = k / prongs * math.tau + rr.uniform(-0.25, 0.25)
        L = W * rr.uniform(0.32, 0.47)
        w = W * rr.uniform(0.035, 0.06)
        tip = (c + math.cos(a) * L, c + math.sin(a) * L)
        l = (c + math.cos(a + math.pi / 2) * w, c + math.sin(a + math.pi / 2) * w)
        r = (c + math.cos(a - math.pi / 2) * w, c + math.sin(a - math.pi / 2) * w)
        d.polygon([l, tip, r], fill=(255, 170, 60, 200))
    im = im.filter(ImageFilter.GaussianBlur(S * 3))
    core = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    cd = ImageDraw.Draw(core)
    for i in range(30, 0, -1):
        rad = W * 0.16 * i / 30
        a = int(255 * (1 - i / 30) ** 0.6)
        cd.ellipse([c - rad, c - rad, c + rad, c + rad], fill=(255, 235 - i * 2, 180 - i * 4, a))
    im = Image.alpha_composite(im, core.filter(ImageFilter.GaussianBlur(S * 2)))
    # sparks
    for k in range(24):
        a = rr.uniform(0, math.tau); r0 = W * rr.uniform(0.08, 0.2); r1 = r0 + W * rr.uniform(0.05, 0.15)
        d2 = ImageDraw.Draw(im)
        d2.line([(c + math.cos(a) * r0, c + math.sin(a) * r0), (c + math.cos(a) * r1, c + math.sin(a) * r1)], fill=(255, 220, 140, 180), width=S * 2)
    return im.resize((n, n), Image.LANCZOS)


def side(seed, w=512, h=128):
    rr = random.Random(seed)
    W, H = w * S, h * S
    im = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for k in range(7):
        x1 = W * rr.uniform(0.45, 0.95)
        off = H * rr.uniform(-0.22, 0.22)
        h0 = H * rr.uniform(0.06, 0.14)
        d.polygon([(0, H / 2 - h0), (x1 * 0.55, H / 2 + off * 0.5 - h0 * 1.4), (x1, H / 2 + off), (x1 * 0.55, H / 2 + off * 0.5 + h0 * 1.4), (0, H / 2 + h0)], fill=(255, 200, 110, 60))
    im = im.filter(ImageFilter.GaussianBlur(S * 4))
    g = Image.new('RGBA', (W, H), (0, 0, 0, 0)); gd = ImageDraw.Draw(g)
    for i in range(20, 0, -1):
        rx = W * 0.3 * i / 20; ry = H * 0.25 * i / 20
        gd.ellipse([-rx * 0.2, H / 2 - ry, rx, H / 2 + ry], fill=(255, 240, 190, int(255 * (1 - i / 20))))
    im = Image.alpha_composite(im, g.filter(ImageFilter.GaussianBlur(S * 2)))
    return im.resize((w, h), Image.LANCZOS)


for i in range(3):
    front(i).save(os.path.join(OUT, f'flash{i}.png'))
    side(i).save(os.path.join(OUT, f'flash_side{i}.png'))
front(0).save(os.path.join(OUT, 'flash.png')); side(0).save(os.path.join(OUT, 'flash_side.png'))
prev = Image.new('RGBA', (768 + 512, 256), (20, 25, 30, 255))
for i in range(3): prev.alpha_composite(front(i), (i * 256, 0))
prev.alpha_composite(side(1), (768, 64))
prev.convert('RGB').save('/tmp/flash.png'); print('ok')
