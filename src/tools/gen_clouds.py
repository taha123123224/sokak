"""Perspective-correct cumulus cloud dome for ProceduralSkyMaterial.sky_cover (equirectangular RGBA)."""
import numpy as np, os
from PIL import Image
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
rng = np.random.default_rng(12)
N = 1024


def tile_noise(cells):
    g = rng.random((cells, cells)).astype(np.float32)
    g = np.pad(g, 1, mode='wrap')
    im = Image.fromarray((g * 255).astype(np.uint8)).resize(((cells + 2) * (N // cells), (cells + 2) * (N // cells)), Image.BICUBIC)
    a = np.asarray(im, np.float32) / 255.0
    o = N // cells
    return a[o:o + N, o:o + N]


fbm = np.zeros((N, N), np.float32); amp = 1.0; tot = 0
for c in (4, 8, 16, 32, 64, 128):
    fbm += tile_noise(c) * amp; tot += amp; amp *= 0.5
fbm /= tot
fbm = (fbm - np.percentile(fbm, 1)) / (np.percentile(fbm, 99) - np.percentile(fbm, 1))


def sample(x, y):
    x = (x % 1.0) * N; y = (y % 1.0) * N
    x0 = np.floor(x).astype(int) % N; y0 = np.floor(y).astype(int) % N
    x1 = (x0 + 1) % N; y1 = (y0 + 1) % N
    fx = x - np.floor(x); fy = y - np.floor(y)
    return (fbm[y0, x0] * (1 - fx) * (1 - fy) + fbm[y0, x1] * fx * (1 - fy) + fbm[y1, x0] * (1 - fx) * fy + fbm[y1, x1] * fx * fy)


W, H = 2048, 1024
u = (np.arange(W) + 0.5) / W
v = (np.arange(H) + 0.5) / H
U, V = np.meshgrid(u, v)
az = U * 2 * np.pi
el = (0.5 - V) * np.pi
el_c = np.maximum(el, 0.015)
d = 1.0 / np.tan(el_c)                 # distance on cloud plane
px = np.cos(az) * d * 0.3
pz = np.sin(az) * d * 0.3
n = sample(px, pz)
detail = sample(px * 4.1 + 0.3, pz * 4.1 + 0.7)
dens = np.clip((n - 0.52) * 3.2 + (detail - 0.5) * 0.45, 0, 1)
dens = dens ** 1.3
fade = np.clip((el - 0.02) / 0.12, 0, 1) * np.clip(1.0 - (el - 0.9) / 0.6, 0.35, 1)
alpha = dens * fade * (el > 0)
shade = 0.78 + 0.22 * np.clip(1.0 - dens * 1.2 + (detail - 0.5), 0, 1)
rgb = np.stack([shade, shade * 0.985, shade * 0.97], -1)
img = np.concatenate([rgb, alpha[..., None]], -1)
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').save(os.path.join(ROOT, 'assets', 'tex', 'clouds.png'))
prev = Image.new('RGB', (W, H // 2), (70, 130, 210))
prev.paste(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').crop((0, 0, W, H // 2)), (0, 0), Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), 'RGBA').crop((0, 0, W, H // 2)))
prev.resize((1024, 256)).save('/tmp/clouds_prev.png')
print('clouds ok')
