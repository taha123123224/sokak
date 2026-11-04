"""v2.7 map textures (tileable, 1024px): albedo + normal + orm (R=ao G=rough B=metal) + height
  dirt        construction-site soil: packed earth, pebbles, cracks, damp patches
  gravel2     crushed stone gravel
  dryground   dry Gallipoli grassland: straw-coloured grass strokes over soil
  rawconc     raw formwork concrete: panel seams, tie holes, water stains, honeycombing
  ashlar      cut-stone fortress masonry (rectangular blocks in courses, weathered)
  grass_tuft.png  alpha card for scattered grass clumps
"""
import numpy as np, os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'tex')
N = 1024
rng = np.random.default_rng(27)


def fnoise(n=N, beta=2.0, seed=None):
    """periodic fractal noise via FFT (1/f^beta), normalised 0..1"""
    r = np.random.default_rng(seed)
    kx = np.fft.fftfreq(n)[:, None]; ky = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(kx * kx + ky * ky); k[0, 0] = 1
    ph = np.exp(2j * np.pi * r.random((n, n)))
    f = ph / k ** (beta / 2)
    f[0, 0] = 0
    a = np.real(np.fft.ifft2(f))
    a = (a - a.min()) / (a.max() - a.min())
    return a


def band(n, lo, hi, seed):
    """noise restricted to a frequency band (cycles per image)"""
    r = np.random.default_rng(seed)
    kx = np.fft.fftfreq(n)[:, None] * n; ky = np.fft.fftfreq(n)[None, :] * n
    k = np.sqrt(kx * kx + ky * ky)
    m = ((k >= lo) & (k <= hi)).astype(float)
    f = np.exp(2j * np.pi * r.random((n, n))) * m
    a = np.real(np.fft.ifft2(f))
    return (a - a.min()) / (a.max() - a.min() + 1e-9)


def blur_wrap(a, rad):
    """periodic gaussian blur via FFT"""
    n = a.shape[0]
    kx = np.fft.fftfreq(n)[:, None]; ky = np.fft.fftfreq(n)[None, :]
    g = np.exp(-2 * (np.pi ** 2) * (rad ** 2) * (kx * kx + ky * ky))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def normal_from(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + 1)
    nx, ny, nz = -dx / l, dy / l, nz / l
    return np.stack([nx * 0.5 + 0.5, ny * 0.5 + 0.5, nz * 0.5 + 0.5], -1)


def save(name, alb, h, rough, nstr=6.0, ao=None, metal=None):
    alb = np.clip(alb, 0, 1)
    Image.fromarray((alb * 255).astype(np.uint8)).save(os.path.join(OUT, name + '_albedo.png'), optimize=True)
    Image.fromarray((normal_from(h, nstr) * 255).astype(np.uint8)).save(os.path.join(OUT, name + '_normal.png'), optimize=True)
    if ao is None:
        ao = np.clip(0.55 + 0.45 * (h - blur_wrap(h, 6) + 0.5) * 1.0, 0, 1)
    if metal is None:
        metal = np.zeros_like(h)
    orm = np.stack([ao, np.clip(rough, 0, 1), metal], -1)
    Image.fromarray((orm * 255).astype(np.uint8)).save(os.path.join(OUT, name + '_orm.png'), optimize=True)
    Image.fromarray((np.clip(h, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + '_height.png'), optimize=True)
    print('saved', name)


def pebbles(count, rmin, rmax, seed):
    """tileable pebble field: height map + per-pebble colour id"""
    r = np.random.default_rng(seed)
    h = np.zeros((N, N)); cid = np.zeros((N, N))
    yy, xx = np.mgrid[0:N, 0:N]
    for i in range(count):
        cx, cy = r.random() * N, r.random() * N
        rx = r.uniform(rmin, rmax); ry = rx * r.uniform(0.6, 1.0)
        ang = r.uniform(0, np.pi)
        x0, x1 = int(cx - rx - 2), int(cx + rx + 3)
        y0, y1 = int(cy - rx - 2), int(cy + rx + 3)
        ys = np.arange(y0, y1); xs = np.arange(x0, x1)
        YY, XX = np.meshgrid(ys, xs, indexing='ij')
        dx = XX - cx; dy = YY - cy
        u = (dx * np.cos(ang) + dy * np.sin(ang)) / rx
        v = (-dx * np.sin(ang) + dy * np.cos(ang)) / ry
        d = u * u + v * v
        m = d < 1
        val = np.sqrt(np.clip(1 - d, 0, 1)) * rx / rmax
        iy = YY % N; ix = XX % N
        cur = h[iy, ix]
        upd = m & (val > cur)
        h[iy[upd], ix[upd]] = val[upd]
        cid[iy[upd], ix[upd]] = r.random()
    return h, cid


def mix(a, b, t):
    t = t[..., None] if t.ndim == 2 else t
    return a * (1 - t) + b * t


def col(c):
    return np.array(c, float)[None, None, :]


# ---------------------------------------------------------------- dirt
def gen_dirt():
    base = fnoise(beta=2.2, seed=1)
    fine = fnoise(beta=1.2, seed=2)
    damp = np.clip((blur_wrap(fnoise(beta=2.6, seed=3), 3) - 0.55) * 4, 0, 1)
    ph, pid = pebbles(2600, 2.5, 9, 4)
    ph2, pid2 = pebbles(9000, 1.0, 2.6, 5)
    peb = np.maximum(ph, ph2 * 0.6)
    pmask = (peb > 0.02).astype(float)
    # cracks: thin dark lines from a ridged noise
    rn = np.abs(band(N, 6, 14, 6) - 0.5)
    cracks = np.clip(1 - rn * 28, 0, 1) * np.clip((fnoise(beta=2, seed=7) - 0.45) * 5, 0, 1)
    soil = mix(col((0.40, 0.31, 0.22)), col((0.55, 0.45, 0.33)), base)
    soil = soil * (0.86 + 0.28 * fine[..., None])
    soil = mix(soil, soil * 0.62, damp * 0.8)
    pc = mix(col((0.46, 0.43, 0.39)), col((0.72, 0.66, 0.58)), np.maximum(pid, pid2 * pmask))
    pc = pc * (0.75 + 0.35 * peb[..., None])
    alb = mix(soil, pc, pmask * 0.92)
    alb = alb * (1 - cracks[..., None] * 0.45)
    h = base * 0.35 + fine * 0.15 + peb * 0.55 - cracks * 0.25
    h = (h - h.min()) / (h.max() - h.min())
    rough = 0.95 - damp * 0.3 - pmask * 0.12
    save('dirt', alb, h, rough, 9.0)


def gen_gravel():
    ph, pid = pebbles(5200, 3, 10, 11)
    ph2, pid2 = pebbles(12000, 1.2, 3, 12)
    peb = np.maximum(ph, ph2 * 0.7)
    gap = (peb < 0.03).astype(float)
    tone = fnoise(beta=2.4, seed=13)
    c = mix(col((0.42, 0.41, 0.4)), col((0.75, 0.73, 0.7)), np.where(ph > ph2 * 0.7, pid, pid2))
    c = c * (0.7 + 0.45 * peb[..., None]) * (0.9 + 0.2 * tone[..., None])
    alb = mix(c, col((0.2, 0.18, 0.16)), gap * 0.85)
    save('gravel2', alb, peb, 0.9 - peb * 0.15, 10.0)


def gen_dryground():
    soil = fnoise(beta=2.2, seed=21)
    patch = blur_wrap(fnoise(beta=2.8, seed=22), 2)
    gmask = np.clip((patch - 0.35) * 3.2, 0, 1)
    # grass blades: many short strokes drawn on a tiled canvas
    im = Image.new('L', (N, N), 0); dr = ImageDraw.Draw(im)
    ci = Image.new('L', (N, N), 0); dc = ImageDraw.Draw(ci)
    r = np.random.default_rng(23)
    for i in range(26000):
        x, y = r.random() * N, r.random() * N
        if gmask[int(y) % N, int(x) % N] < r.random() * 0.9:
            continue
        a = r.uniform(-1.2, 1.2) + np.pi / 2
        L = r.uniform(6, 22)
        x2, y2 = x + np.cos(a) * L, y - np.sin(a) * L
        v = int(r.uniform(120, 255)); cv = int(r.random() * 255)
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                dr.line([(x + ox, y + oy), (x2 + ox, y2 + oy)], fill=v, width=int(r.integers(1, 3)))
                dc.line([(x + ox, y + oy), (x2 + ox, y2 + oy)], fill=cv, width=2)
    bl = np.array(im) / 255.0; bc = np.array(ci) / 255.0
    sc = mix(col((0.36, 0.29, 0.2)), col((0.5, 0.41, 0.3)), soil)
    gc = mix(col((0.55, 0.5, 0.3)), col((0.78, 0.7, 0.45)), bc)
    gc = mix(gc, col((0.4, 0.45, 0.22)), (bc > 0.8) * 0.6)
    alb = mix(sc * (1 - gmask[..., None] * 0.25), gc * (0.75 + 0.25 * bl[..., None]), np.clip(bl * 1.4, 0, 1))
    h = soil * 0.4 + bl * 0.6
    save('dryground', alb, h, 0.93 - bl * 0.05, 7.0)


def gen_rawconc():
    base = fnoise(beta=2.0, seed=31)
    fine = fnoise(beta=1.0, seed=32)
    stain = blur_wrap(fnoise(beta=2.6, seed=33), 4)
    # vertical water streaks (tile along Y)
    sx = np.random.default_rng(34).random(N)
    streak = np.tile(np.convolve(sx, np.ones(9) / 9, 'same')[None, :], (N, 1))
    streak = np.clip((streak - 0.55) * 6, 0, 1) * (0.4 + 0.6 * band(N, 1, 3, 35))
    # formwork panel seams: 2 x 1 panels per tile, tie holes
    yy, xx = np.mgrid[0:N, 0:N]
    seam = ((np.abs((xx % (N // 2)) - 0) < 3) | (np.abs((yy % (N // 2)) - 0) < 3)).astype(float)
    seam = blur_wrap(seam, 1.2)
    holes = np.zeros((N, N))
    for hx in (N // 8, 3 * N // 8, 5 * N // 8, 7 * N // 8):
        for hy in (N // 4, 3 * N // 4):
            d = (xx - hx) ** 2 + (yy - hy) ** 2
            holes = np.maximum(holes, np.clip(1 - d / 64.0, 0, 1))
    pores = (fnoise(beta=0.6, seed=36) > 0.93).astype(float)
    c = mix(col((0.42, 0.41, 0.39)), col((0.6, 0.59, 0.56)), base)
    c = c * (0.9 + 0.18 * fine[..., None])
    c = mix(c, c * col((0.85, 0.82, 0.76)), np.clip((stain - 0.5) * 3, 0, 1) * 0.7)
    c = c * (1 - streak[..., None] * 0.22)
    c = c * (1 - seam[..., None] * 0.35) * (1 - holes[..., None] * 0.6) * (1 - pores[..., None] * 0.35)
    h = 0.6 + base * 0.15 + fine * 0.08 - seam * 0.25 - holes * 0.5 - pores * 0.2
    save('rawconc', c, np.clip(h, 0, 1), 0.88 - stain * 0.1, 5.0)


def gen_ashlar():
    yy, xx = np.mgrid[0:N, 0:N]
    rows = 8
    rh = N // rows
    h = np.zeros((N, N)); cid = np.zeros((N, N))
    r = np.random.default_rng(41)
    for ri in range(rows):
        y0 = ri * rh
        x = r.integers(0, N)
        start = x
        widths = []
        tot = 0
        while tot < N:
            w = int(r.integers(int(rh * 1.2), int(rh * 2.6)))
            widths.append(w); tot += w
        widths[-1] -= tot - N
        x = start
        for w in widths:
            v = r.random()
            ys = slice(y0 + 4, y0 + rh - 4)
            for k in range(w - 8):
                cx = (x + 4 + k) % N
                h[ys, cx] = 1.0
                cid[ys, cx] = v
            x += w
    edge = blur_wrap(h, 3)
    chip = fnoise(beta=1.3, seed=42)
    hm = np.clip(edge * 0.8 + chip * 0.25 - (1 - h) * 0.3, 0, 1)
    face = fnoise(beta=2.0, seed=43)
    lich = np.clip((blur_wrap(fnoise(beta=2.5, seed=44), 2) - 0.62) * 4, 0, 1)
    c = mix(col((0.6, 0.55, 0.45)), col((0.82, 0.76, 0.64)), cid)
    c = c * (0.82 + 0.3 * face[..., None]) * (0.85 + 0.15 * chip[..., None])
    c = mix(c, col((0.38, 0.4, 0.3)), lich * 0.45)
    mortar = col((0.5, 0.47, 0.42)) * (0.8 + 0.3 * chip[..., None])
    alb = mix(mortar, c, np.clip(edge * 1.6, 0, 1))
    save('ashlar', alb, hm, 0.9 - edge * 0.05, 8.0)


def gen_tuft():
    S = 256
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    r = np.random.default_rng(51)
    for i in range(70):
        x0 = S / 2 + r.normal(0, S * 0.12)
        a = np.pi / 2 + r.normal(0, 0.35)
        L = r.uniform(S * 0.45, S * 0.95)
        bend = r.normal(0, 0.25)
        pts = []
        for t in np.linspace(0, 1, 8):
            aa = a + bend * t * t
            pts.append((x0 + np.cos(aa) * L * t, S - 2 - np.sin(aa) * L * t))
        g = r.uniform(0.0, 1.0)
        cc = (int(150 + 70 * g), int(135 + 55 * g), int(70 + 30 * g), 255) if r.random() < 0.8 else (int(95 + 40 * g), int(110 + 40 * g), int(50 + 20 * g), 255)
        for k in range(len(pts) - 1):
            w = max(1, int(4 * (1 - k / len(pts))))
            d.line([pts[k], pts[k + 1]], fill=cc, width=w)
    im = im.filter(ImageFilter.SMOOTH)
    im.save(os.path.join(OUT, 'grass_tuft.png'))
    print('saved tuft')


if __name__ == '__main__':
    gen_dirt(); gen_gravel(); gen_dryground(); gen_rawconc(); gen_ashlar(); gen_tuft()
