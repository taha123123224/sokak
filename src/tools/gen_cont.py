"""Shipping container face textures (normalized UV): corrugation shading, rust, dirt, stencil brand + ID."""
import os, sys, random
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.dirname(__file__))
from gen_textures import fnoise, bandnoise, smoothstep, normal_from_height
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'tex')
W, H = 2048, 880
COLS = {'red': (158, 34, 24), 'blue': (26, 70, 148), 'orange': (224, 112, 22), 'green': (34, 102, 56), 'grey': (132, 138, 140), 'yellow': (224, 184, 30), 'white': (224, 227, 227)}
BRANDS = {'red': 'BOĞAZ LINES', 'blue': 'ANADOLU', 'orange': 'SOKAK CARGO', 'green': 'MARMARA', 'grey': 'TRITON', 'yellow': 'KARADENİZ', 'white': 'EGE LOJİSTİK'}
font = ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'RussoOne-Regular.ttf'), 150)
font2 = ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'Rajdhani-Bold.ttf'), 54)
x = np.arange(W)[None, :] / W
y = np.arange(H)[:, None] / H
ribs = 34
corr = 0.5 + 0.5 * np.sin(x * ribs * 2 * np.pi)            # trapezoid corrugation
corr = np.clip((corr - 0.5) * 2.2 + 0.5, 0, 1)
height = corr * np.ones((H, W))
# top/bottom rails + edge seams
height[:30] = 0.7; height[-34:] = 0.7
normal = normal_from_height(height * 3.0, 6.0)
Image.fromarray(normal).save(os.path.join(OUT, 'cont_normal.png'))
rng = random.Random(4)
for name, c in COLS.items():
    base = np.ones((H, W, 3)) * np.array(c)[None, None, :] / 255
    shade = 0.82 + 0.22 * corr
    base *= shade[..., None]
    big = np.asarray(Image.fromarray((fnoise(1024, 2.4, rng.randint(0, 999)) * 255).astype(np.uint8)).resize((W, H)), np.float32) / 255
    base *= (0.9 + 0.14 * big)[..., None]
    # rust streaks running down from the top rail and around rib bottoms
    st = bandnoise(1024, 6, 120, rng.randint(0, 999))
    st = np.asarray(Image.fromarray((st * 255).astype(np.uint8)).resize((W // 12, H)).resize((W, H), Image.BICUBIC), np.float32) / 255
    rust = smoothstep(0.62, 0.9, st) * (1.0 - y) ** 1.5
    spots = smoothstep(0.78, 0.85, np.asarray(Image.fromarray((bandnoise(1024, 40, 200, rng.randint(0, 999)) * 255).astype(np.uint8)).resize((W, H)), np.float32) / 255)
    rc = np.array([0.42, 0.2, 0.09])
    base = base * (1 - 0.6 * rust[..., None]) + rc * 0.6 * rust[..., None]
    base = base * (1 - 0.8 * spots[..., None]) + rc * 0.8 * spots[..., None]
    # bottom dirt
    base *= (1 - 0.35 * smoothstep(0.75, 1.0, y))[..., None]
    img = Image.fromarray((np.clip(base, 0, 1) * 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    txtc = (240, 240, 235) if name not in ('white', 'yellow') else (30, 34, 40)
    d.text((W * 0.5, H * 0.45), BRANDS[name], font=font, fill=txtc, anchor='mm')
    code = 'S%sKU %06d %d' % ('KOKAUL'[rng.randint(0, 5)], rng.randint(100000, 999999), rng.randint(0, 9))
    d.text((W * 0.93, H * 0.12), code, font=font2, fill=txtc, anchor='rm')
    d.text((W * 0.93, H * 0.2), '22G1   MAX GROSS 30.480 KG', font=ImageFont.truetype(os.path.join(ROOT, 'assets', 'fonts', 'Rajdhani-Bold.ttf'), 30), fill=txtc, anchor='rm')
    # weather the stencil a little
    arr = np.asarray(img, np.float32) / 255
    arr = arr * (1 - 0.25 * rust[..., None]) + rc * 0.25 * rust[..., None]
    Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, f'cont_{name}.png'))
    print('container', name)
# puddle alpha
n = 512
yy, xx = np.mgrid[0:n, 0:n] / n
r = np.hypot(xx - 0.5, yy - 0.5)
a = smoothstep(0.48, 0.3, r + (fnoise(n, 2.2, 77) - 0.5) * 0.35)
rgba = np.zeros((n, n, 4)); rgba[..., :3] = 0.05; rgba[..., 3] = a * 0.6
Image.fromarray((rgba * 255).astype(np.uint8)).save(os.path.join(OUT, 'puddle.png'))
a2 = smoothstep(0.5, 0.15, r + (fnoise(n, 2.0, 78) - 0.5) * 0.5)
rgba[..., :3] = 0.03; rgba[..., 3] = a2 * 0.7
Image.fromarray((rgba * 255).astype(np.uint8)).save(os.path.join(OUT, 'oilstain.png'))
print('ok')
