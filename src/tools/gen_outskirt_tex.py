"""v4.8 textures for the map surroundings: a tileable apartment facade bay (1 storey x 2 windows) and an aerial
forest-canopy tile. Procedural (numpy), so they tile perfectly and cost nothing to regenerate."""
import numpy as np, os
from PIL import Image, ImageFilter
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'assets', 'tex')
rng = np.random.default_rng(48)

def tnoise(n, cells, seed):
    r = np.random.default_rng(seed)
    g = r.random((cells, cells)).astype(np.float32)
    g = np.pad(g, 1, mode='wrap')
    im = Image.fromarray((g * 255).astype(np.uint8)).resize(((cells + 2) * (n // cells),) * 2, Image.BICUBIC)
    a = np.asarray(im, np.float32) / 255.0
    o = n // cells
    return a[o:o + n, o:o + n]

def fbm(n, seed, oct=(4, 8, 16, 32, 64)):
    s = 0; t = 0; a = 1.0
    for i, c in enumerate(oct):
        s = s + tnoise(n, c, seed + i) * a; t += a; a *= 0.55
    return s / t

# ---------------------------------------------------------------- facade bay 512x512 (6.2 m x 3 m -> 2 windows)
N = 512
plaster = np.array([0.86, 0.82, 0.73])
f = fbm(N, 3)
img = np.ones((N, N, 3)) * plaster * (0.88 + 0.22 * f[..., None])
# floor slab band at the bottom (tiles vertically)
y, x = np.mgrid[0:N, 0:N]
slab = (y > N - 26)
img[slab] = img[slab] * 0.82
img[(y > N - 28) & (y < N - 24)] *= 0.65
for cx in (N * 0.25, N * 0.75):
    x0, x1 = int(cx - 72), int(cx + 72)
    y0, y1 = 70, 400
    # frame
    img[y0:y1, x0:x1] = np.array([0.93, 0.93, 0.92])
    # glass with sky reflection gradient
    gy = np.linspace(0, 1, y1 - y0 - 16)[:, None, None]
    glass = np.array([0.33, 0.4, 0.46]) * (1.0 - 0.55 * gy) + np.array([0.05, 0.06, 0.07]) * gy
    g2 = glass + 0.06 * (fbm(N, 9)[y0 + 8:y1 - 8, x0 + 8:x1 - 8, None] - 0.5)
    img[y0 + 8:y1 - 8, x0 + 8:x1 - 8] = g2
    # mullion
    img[y0:y1, int(cx) - 4:int(cx) + 4] = np.array([0.92, 0.92, 0.91])
    # sill + shadow under it
    img[y1:y1 + 10, x0 - 8:x1 + 8] = np.array([0.78, 0.77, 0.74])
    img[y1 + 10:y1 + 22, x0 - 8:x1 + 8] *= 0.8
    # balcony railing
    r0 = 300
    img[r0:r0 + 6, x0 - 6:x1 + 6] = np.array([0.35, 0.36, 0.38])
    for bx in range(x0, x1, 14):
        img[r0:y1, bx:bx + 3] = np.array([0.38, 0.39, 0.41])
    # soft dirt streaks below the window
    st = np.clip(1.0 - (y - y1) / 110.0, 0, 1) * ((y > y1 + 10) & (x > x0) & (x < x1))
    img *= (1.0 - 0.12 * st * (0.5 + f))[..., None]
img = np.clip(img, 0, 1)
Image.fromarray((img * 255).astype(np.uint8)).save(os.path.join(OUT, 'facade_apt.png'))

# ---------------------------------------------------------------- aerial forest canopy 512x512
N = 512
base = fbm(N, 21)
can = np.zeros((N, N, 3))
can[:] = np.array([0.12, 0.2, 0.09])
can *= (0.75 + 0.5 * base[..., None])
yy, xx = np.mgrid[0:N, 0:N]
for i in range(1400):
    cx, cy = rng.random() * N, rng.random() * N
    r = rng.uniform(7, 17)
    con = rng.random() < 0.6
    col = np.array([0.1, 0.19, 0.1]) if con else np.array([0.18, 0.3, 0.12])
    col = col * rng.uniform(0.75, 1.3)
    x0, x1 = int(cx - r - 1), int(cx + r + 2); y0, y1 = int(cy - r - 1), int(cy + r + 2)
    sx = np.arange(x0, x1) % N; sy = np.arange(y0, y1) % N
    dx = (np.arange(x0, x1)[None, :] - cx); dy = (np.arange(y0, y1)[:, None] - cy)
    d = np.sqrt(dx * dx + dy * dy) / r
    m = np.clip(1.0 - d, 0, 1)
    if con:
        m = m ** 0.7
    # lit from the upper left, dark rim
    light = np.clip(0.75 - 0.45 * (dx + dy) / r / 1.4, 0.35, 1.25)
    sub = can[np.ix_(sy, sx)]
    a = (m > 0)[..., None] * np.clip(m * 3, 0, 1)[..., None]
    sub = sub * (1 - a) + (col * light[..., None] * (0.7 + 0.3 * m[..., None])) * a
    can[np.ix_(sy, sx)] = sub
can = np.clip(can, 0, 1)
im = Image.fromarray((can * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.6))
im.save(os.path.join(OUT, 'forest_canopy.png'))
print("ok")
