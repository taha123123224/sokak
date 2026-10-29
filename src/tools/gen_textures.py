"""Procedural, tileable PBR texture generator (albedo / normal / roughness).
All textures are periodic (seamless) because they are built from FFT-filtered
noise and wrap-around Voronoi.
"""
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree
import os, sys

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'tex')
os.makedirs(OUT, exist_ok=True)
R = np.random.default_rng(42)


def fnoise(n, beta=2.0, seed=0):
    """periodic 1/f^beta noise in [0,1]"""
    r = np.random.default_rng(seed)
    w = r.standard_normal((n, n))
    F = np.fft.fft2(w)
    fx = np.fft.fftfreq(n)[:, None]
    fy = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    F = F / f ** (beta / 2)
    F[0, 0] = 0
    out = np.real(np.fft.ifft2(F))
    out = (out - out.min()) / (out.max() - out.min())
    return out


def bandnoise(n, lo, hi, seed=0):
    r = np.random.default_rng(seed)
    w = r.standard_normal((n, n))
    F = np.fft.fft2(w)
    fx = np.fft.fftfreq(n)[:, None] * n
    fy = np.fft.fftfreq(n)[None, :] * n
    f = np.sqrt(fx ** 2 + fy ** 2)
    F[(f < lo) | (f > hi)] = 0
    out = np.real(np.fft.ifft2(F))
    return (out - out.min()) / (out.max() - out.min() + 1e-9)


def voronoi(n, count, seed=0, jitter=1.0, grid=None):
    """returns (F1, F2, cell_id) wrap-around voronoi distances in pixels"""
    r = np.random.default_rng(seed)
    if grid is not None:
        gx, gy = grid
        pts = []
        for j in range(gy):
            for i in range(gx):
                off = 0.5 if j % 2 else 0.0
                pts.append(((i + off + 0.5 + (r.random() - .5) * jitter) / gx * n,
                            (j + 0.5 + (r.random() - .5) * jitter * 0.6) / gy * n))
        pts = np.array(pts) % n
    else:
        pts = r.random((count, 2)) * n
    tiles = []
    for dx in (-n, 0, n):
        for dy in (-n, 0, n):
            tiles.append(pts + [dx, dy])
    allp = np.concatenate(tiles)
    ids = np.tile(np.arange(len(pts)), 9)
    tree = cKDTree(allp)
    yy, xx = np.mgrid[0:n, 0:n]
    q = np.stack([xx.ravel() + 0.5, yy.ravel() + 0.5], 1)
    d, i = tree.query(q, k=2)
    return d[:, 0].reshape(n, n), d[:, 1].reshape(n, n), ids[i[:, 0]].reshape(n, n), len(pts)


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # OpenGL convention (+Y up)
    nz = np.ones_like(h)
    l = np.sqrt(nx ** 2 + ny ** 2 + nz ** 2)
    n = np.stack([nx / l, ny / l, nz / l], -1)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, albedo, height=None, rough=None, nstrength=4.0, metal=None):
    a = np.clip(albedo, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8)).save(f'{OUT}/{name}_albedo.png', optimize=True)
    if height is not None:
        Image.fromarray(normal_from_height(height, nstrength)).save(f'{OUT}/{name}_normal.png', optimize=True)
        hh = (height - height.min()) / max(height.max() - height.min(), 1e-6)
        Image.fromarray((hh * 255).astype(np.uint8)).save(f'{OUT}/{name}_height.png', optimize=True)
    if rough is not None:
        rr = np.clip(rough, 0, 1)
        mm = np.zeros_like(rr) if metal is None else np.clip(metal, 0, 1)
        # glTF ORM-ish: R=occlusion(1) G=roughness B=metallic
        orm = np.stack([np.ones_like(rr), rr, mm], -1)
        Image.fromarray((orm * 255).astype(np.uint8)).save(f'{OUT}/{name}_orm.png', optimize=True)
    print('saved', name)


def col(hexs):
    hexs = hexs.lstrip('#')
    return np.array([int(hexs[i:i + 2], 16) / 255 for i in (0, 2, 4)])


def lerp(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ surfaces
def cobble(n=2048):
    F1, F2, cid, cnt = voronoi(n, 0, seed=3, grid=(14, 16), jitter=0.7)
    edge = F2 - F1
    stone = smoothstep(2, 22, edge)
    dome = np.clip(1 - (F1 / (F1 + edge * 0.5 + 1e-3)) ** 2, 0, 1)
    rn = np.random.default_rng(5).random(cnt)
    tone = rn[cid]
    det = fnoise(n, 1.6, 7)
    fine = bandnoise(n, 80, 400, 8)
    h = stone * (0.55 + 0.45 * dome) + fine * 0.06 * stone + det * 0.1
    base = lerp(col('8a8378'), col('b3aa9b'), tone)
    base = lerp(base, col('6f6a63'), (rn[cid] > 0.82).astype(float) * 0.6)
    base = base * (0.85 + 0.25 * det[..., None]) * (0.92 + 0.12 * fine[..., None])
    mortar = col('3d3a35') * (0.8 + 0.3 * fine[..., None])
    alb = lerp(mortar, base, stone)
    dirt = smoothstep(0.55, 0.85, fnoise(n, 2.2, 9))
    alb = lerp(alb, alb * col('7a6a55') * 1.3, dirt * 0.5)
    rough = 0.55 + 0.3 * (1 - stone) + 0.1 * fine - 0.15 * dome * stone
    save('cobble', alb, h, rough, 9)


def pavers(n=1024):
    yy, xx = np.mgrid[0:n, 0:n]
    s = n // 4
    gx, gy = xx % s, yy % s
    d = np.minimum(np.minimum(gx, s - gx), np.minimum(gy, s - gy))
    tile = smoothstep(2, 9, d)
    tid = (xx // s) + (yy // s) * 7
    rn = np.random.default_rng(2).random(64)
    tone = rn[tid % 64]
    det = fnoise(n, 1.8, 3)
    fine = bandnoise(n, 60, 300, 4)
    base = lerp(col('9c9890'), col('bdb8ae'), tone) * (0.88 + 0.2 * det[..., None]) * (0.95 + 0.08 * fine[..., None])
    alb = lerp(col('4a4740'), base, tile)
    stains = smoothstep(0.6, 0.9, fnoise(n, 2.4, 6))
    alb = lerp(alb, alb * 0.75, stains * 0.6)
    h = tile * 0.8 + fine * 0.05
    save('paver', alb, h, 0.7 + 0.15 * fine - 0.1 * stains, 5)


def asphalt(n=1024):
    fine = bandnoise(n, 150, 512, 1)
    mid = fnoise(n, 1.7, 2)
    agg = (np.random.default_rng(3).random((n, n)) > 0.985).astype(float)
    alb = col('3a3b3d')[None, None] * (0.75 + 0.45 * fine[..., None]) * (0.85 + 0.3 * mid[..., None])
    alb = lerp(alb, col('8d8a86'), agg * 0.6)
    patch = smoothstep(0.62, 0.66, fnoise(n, 2.5, 4))
    alb = lerp(alb, alb * 0.75, patch * 0.7)
    save('asphalt', alb, fine * 0.6 + agg * 0.3, 0.82 - 0.12 * patch + 0.1 * fine, 3)


def plaster(n=1024):
    big = fnoise(n, 2.4, 11)
    mid = bandnoise(n, 20, 90, 12)
    fine = bandnoise(n, 120, 500, 13)
    alb = np.ones((n, n, 3)) * (0.86 + 0.1 * big[..., None] + 0.05 * mid[..., None] + 0.04 * fine[..., None])
    # damp/dirt streaks from top
    yy = np.mgrid[0:n, 0:n][0] / n
    streak = bandnoise(n, 3, 30, 14)
    s = smoothstep(0.55, 0.8, streak) * (0.4 + 0.6 * np.abs(np.sin(yy * np.pi)))
    alb = alb * (1 - 0.18 * s[..., None])
    # cracked/peeled spots revealing brick-ish layer
    peel = smoothstep(0.80, 0.82, fnoise(n, 2.0, 15))
    alb = lerp(alb, col('9b7d64'), peel * 0.85)
    h = 0.5 * mid + 0.3 * fine - 0.4 * peel + 0.2 * big
    save('plaster', alb, h, 0.85 + 0.1 * fine, 4)


def wood_beam(n=1024):
    yy, xx = np.mgrid[0:n, 0:n] / n
    warp = fnoise(n, 2.0, 21) * 6
    rings = np.sin((xx * 40 + warp * 3) * np.pi) * 0.5 + 0.5
    grain = bandnoise(n, 100, 500, 22)
    cracks = smoothstep(0.93, 0.97, bandnoise(n, 30, 120, 23))
    base = lerp(col('2b1d14'), col('5a3e2b'), rings * 0.6 + grain * 0.4)
    base = base * (1 - 0.6 * cracks[..., None])
    h = rings * 0.3 + grain * 0.4 - cracks
    save('woodbeam', base, h, 0.75 + 0.15 * grain, 5)


def planks(n=1024, name='planks', c1='6b4a30', c2='a77a50', gap='1b130d', rows=8):
    yy, xx = np.mgrid[0:n, 0:n]
    ph = n // rows
    row = yy // ph
    rn = np.random.default_rng(31).random(256)
    offs = (rn[row % 256] * n).astype(int)
    seg = ((xx + offs) % n) // (n // 2)
    pid = (row * 3 + seg) % 256
    tone = rn[(pid * 7) % 256]
    warp = fnoise(n, 2.0, 32)
    grain = np.sin(((yy % ph) / ph * 6 + warp * 8 + tone * 10) * np.pi) * 0.5 + 0.5
    fine = bandnoise(n, 120, 500, 33)
    gy = yy % ph
    gx = (xx + offs) % (n // 2)
    joint = np.minimum(smoothstep(0, 4, gy) * smoothstep(0, 4, ph - gy), smoothstep(0, 3, gx) * smoothstep(0, 3, n // 2 - gx))
    base = lerp(col(c1), col(c2), tone * 0.6 + grain * 0.3 + fine * 0.1)
    alb = lerp(col(gap), base, joint)
    wear = smoothstep(0.55, 0.9, fnoise(n, 2.2, 34))
    alb = lerp(alb, alb * 1.15, wear * 0.3)
    nails = np.zeros((n, n))
    h = joint * 0.7 + grain * 0.1 + fine * 0.1
    save(name, alb, h, 0.7 + 0.15 * fine - 0.1 * wear, 6)


def roof_tiles(n=1024):
    yy, xx = np.mgrid[0:n, 0:n]
    cw, rh = n // 8, n // 8
    row = yy // rh
    off = (row % 2) * (cw // 2)
    u = ((xx + off) % cw) / cw
    v = (yy % rh) / rh
    curve = np.sin(u * np.pi)  # barrel shape
    overlap = smoothstep(0.0, 0.18, v)
    h = curve * 0.8 * overlap + (1 - overlap) * 0.1
    tid = ((xx + off) // cw + row * 13) % 256
    rn = np.random.default_rng(41).random(256)
    tone = rn[tid]
    det = fnoise(n, 1.8, 42)
    base = lerp(col('8f3b22'), col('c46a3f'), tone * 0.7 + det * 0.3)
    base = base * (0.55 + 0.45 * curve[..., None]) * (0.6 + 0.4 * overlap[..., None])
    moss = smoothstep(0.65, 0.9, fnoise(n, 2.2, 43)) * (1 - curve)
    base = lerp(base, col('4d5232'), moss * 0.7)
    save('rooftiles', base, h, 0.7 + 0.2 * det, 8)


def stone_wall(n=1024):
    F1, F2, cid, cnt = voronoi(n, 0, seed=51, grid=(7, 9), jitter=0.9)
    edge = F2 - F1
    stone = smoothstep(3, 18, edge)
    rn = np.random.default_rng(52).random(cnt)
    tone = rn[cid]
    det = fnoise(n, 1.7, 53)
    fine = bandnoise(n, 70, 400, 54)
    base = lerp(col('8b8375'), col('c2b7a1'), tone) * (0.8 + 0.3 * det[..., None]) * (0.9 + 0.15 * fine[..., None])
    alb = lerp(col('5c564c'), base, stone)
    h = stone * (0.6 + 0.4 * np.clip(edge / 60, 0, 1)) + fine * 0.15
    save('stonewall', alb, h, 0.85 - 0.1 * stone, 8)


def painted_metal(n=1024):
    fine = bandnoise(n, 100, 500, 61)
    big = fnoise(n, 2.2, 62)
    rust = smoothstep(0.7, 0.85, fnoise(n, 2.0, 63) * 0.7 + bandnoise(n, 30, 200, 64) * 0.3)
    yy = np.mgrid[0:n, 0:n][0] / n
    streak = smoothstep(0.6, 0.9, bandnoise(n, 2, 25, 65)) * smoothstep(0.2, 1, (yy * 4) % 1)
    alb = np.ones((n, n, 3)) * (0.9 + 0.08 * big[..., None] + 0.04 * fine[..., None])
    alb = alb * (1 - 0.2 * streak[..., None])
    alb = lerp(alb, col('6b3a1f') * 1.4, rust)
    # panel seams
    xx = np.mgrid[0:n, 0:n][1]
    seam = 1 - (np.minimum(xx % (n // 2), n // 2 - xx % (n // 2)) < 3).astype(float) * 0.5
    alb = alb * seam[..., None]
    h = fine * 0.2 - rust * 0.3 + seam * 0.3
    save('paintmetal', alb, h, 0.45 + 0.4 * rust + 0.1 * fine, 3, metal=0.2 * (1 - rust))


def corrugated(n=1024):
    xx = np.mgrid[0:n, 0:n][1] / n
    wave = np.sin(xx * 2 * np.pi * 16)
    h = wave * 0.5 + 0.5
    fine = bandnoise(n, 100, 500, 71)
    rust = smoothstep(0.72, 0.85, fnoise(n, 2.0, 72))
    dent = fnoise(n, 2.6, 73)
    alb = np.ones((n, n, 3)) * (0.85 + 0.15 * (wave[..., None] * 0.5 + 0.5)) * (0.92 + 0.08 * fine[..., None])
    alb = lerp(alb, col('5a3018') * 1.5, rust)
    save('corrugated', alb, h * 0.9 + dent * 0.3, 0.5 + 0.35 * rust, 10, metal=0.3 * (1 - rust))


def concrete(n=1024):
    big = fnoise(n, 2.2, 81)
    fine = bandnoise(n, 120, 500, 82)
    pores = (bandnoise(n, 200, 512, 83) > 0.82).astype(float)
    alb = col('9a968f')[None, None] * (0.85 + 0.2 * big[..., None] + 0.06 * fine[..., None]) * (1 - 0.25 * pores[..., None])
    stains = smoothstep(0.6, 0.85, fnoise(n, 2.4, 84))
    alb = lerp(alb, alb * 0.7, stains * 0.5)
    save('concrete', alb, fine * 0.4 - pores * 0.3 + big * 0.2, 0.85 + 0.1 * fine, 4)


def grass_dirt(n=1024):
    big = fnoise(n, 2.0, 91)
    fine = bandnoise(n, 150, 512, 92)
    blades = bandnoise(n, 250, 512, 93)
    g = lerp(col('3d5226'), col('6b7d39'), blades * 0.7 + big * 0.3)
    d = lerp(col('5b4632'), col('8a7155'), fine)
    m = smoothstep(0.45, 0.6, big)
    alb = lerp(d, g, m)
    save('grass', alb, fine * 0.5 + m * 0.3, 0.9 * np.ones((n, n)), 4)


def water_normal(n=1024):
    h = bandnoise(n, 4, 30, 101) * 0.6 + bandnoise(n, 30, 120, 102) * 0.4
    Image.fromarray(normal_from_height(h, 6)).save(f'{OUT}/water_normal.png', optimize=True)
    print('saved water')


def sandbag(n=512):
    fine = bandnoise(n, 120, 256, 111)
    weave = (np.sin(np.mgrid[0:n, 0:n][1] * 1.2) * np.sin(np.mgrid[0:n, 0:n][0] * 1.2)) * 0.5 + 0.5
    alb = lerp(col('8e7d5c'), col('b3a27c'), fine * 0.6 + weave * 0.4)
    save('sandbag', alb, weave * 0.5 + fine * 0.5, 0.95 * np.ones((n, n)), 3)


# ------------------------------------------------------------------ weapon materials
def gunmetal(n=1024):
    fine = bandnoise(n, 150, 512, 121)
    brushed = bandnoise(n, 200, 512, 122)
    brushed = np.repeat(brushed[:, :1], n, 1) * 0.5 + brushed * 0.5
    scratches = np.zeros((n, n))
    r = np.random.default_rng(123)
    for _ in range(260):
        x0, y0 = r.random(2) * n
        ang = r.random() * np.pi
        L = r.random() * 80 + 10
        t = np.linspace(0, 1, int(L))
        xs = ((x0 + np.cos(ang) * L * t) % n).astype(int)
        ys = ((y0 + np.sin(ang) * L * t) % n).astype(int)
        scratches[ys, xs] = r.random() * 0.8 + 0.2
    wear = smoothstep(0.7, 0.9, fnoise(n, 2.0, 124))
    alb = np.ones((n, n, 3)) * (0.18 + 0.04 * fine[..., None]) + scratches[..., None] * 0.25 + wear[..., None] * 0.1
    rough = 0.38 + 0.12 * brushed - 0.2 * scratches - 0.08 * wear
    save('gunmetal', alb, fine * 0.2 + scratches * 0.1, rough, 1.5, metal=np.ones((n, n)) * 0.9)


def polymer(n=512):
    stip = bandnoise(n, 120, 256, 131)
    alb = np.ones((n, n, 3)) * (0.07 + 0.025 * stip[..., None])
    save('polymer', alb, stip, 0.72 + 0.12 * stip, 3)


def gunwood(n=1024):
    yy, xx = np.mgrid[0:n, 0:n] / n
    warp = fnoise(n, 2.0, 141)
    grain = np.sin((yy * 30 + warp * 6) * np.pi * 2) * 0.5 + 0.5
    fine = bandnoise(n, 150, 512, 142)
    alb = lerp(col('4a210c'), col('8d4a1f'), grain * 0.6 + fine * 0.2 + warp * 0.2)
    save('gunwood', alb, grain * 0.2 + fine * 0.2, 0.4 + 0.2 * fine, 2)


def skins(n=1024):
    r = np.random.default_rng(151)
    yy, xx = np.mgrid[0:n, 0:n] / n
    # Kızıl Ejder: deep red with black flame/tribal shapes + gold edge lines
    a = fnoise(n, 2.6, 152)
    b = bandnoise(n, 3, 12, 153)
    flame = smoothstep(0.55, 0.58, a * 0.6 + b * 0.4 + np.sin(xx * 12 * np.pi) * 0.05)
    edge = smoothstep(0.53, 0.55, a * 0.6 + b * 0.4) - flame
    alb = lerp(col('a0101a'), col('0c0b0d'), flame)
    alb = lerp(alb, col('ffb02e'), np.clip(edge, 0, 1) * 0.9)
    save('skin_kizil', alb, None, 0.35 + 0.2 * flame)
    # Gece Avcısı: carbon fibre + blue hex glow lines
    cf = (np.sin(xx * n * 0.4) * np.sin(yy * n * 0.4) > 0).astype(float)
    alb = lerp(col('101520'), col('1c2333'), cf)
    q = 18.0
    hx = np.abs(((xx * q + (np.floor(yy * q * 1.1547) % 2) * 0.5) % 1) - 0.5)
    hy = np.abs(((yy * q * 1.1547) % 1) - 0.5)
    hexline = smoothstep(0.46, 0.5, np.maximum(hx, hy * 0.866 + hx * 0.5))
    mask = smoothstep(0.5, 0.7, fnoise(n, 2.0, 154))
    alb = lerp(alb, col('3aa0ff'), hexline * mask * 0.9)
    save('skin_gece', alb, None, 0.4 * np.ones((n, n)))
    # Zehir Yeşili: toxic green with black splatter
    sp = bandnoise(n, 10, 80, 155)
    alb = lerp(col('22e04a'), col('0b120b'), smoothstep(0.62, 0.66, sp))
    drops = smoothstep(0.8, 0.82, bandnoise(n, 60, 200, 156))
    alb = lerp(alb, col('0b120b'), drops)
    save('skin_neon', alb, None, 0.3 + 0.2 * drops)
    # Galaksi: nebula gradient with stars
    n1, n2, n3 = fnoise(n, 2.4, 157), fnoise(n, 2.2, 158), fnoise(n, 2.8, 159)
    alb = col('12062e')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('8a1fc0'), smoothstep(0.4, 0.8, n1))
    alb = lerp(alb, col('1f63e0'), smoothstep(0.5, 0.85, n2) * 0.8)
    alb = lerp(alb, col('ff2a9a'), smoothstep(0.6, 0.9, n3) * 0.8)
    stars = (r.random((n, n)) > 0.996).astype(float)
    alb = lerp(alb, np.ones(3), stars)
    save('skin_galaksi', alb, None, 0.25 * np.ones((n, n)))
    # Orman kamuflaj
    k = [fnoise(n, 3.0, 160 + i) for i in range(3)]
    alb = col('5a6440')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('2d3820'), smoothstep(0.55, 0.57, k[0]))
    alb = lerp(alb, col('7d7449'), smoothstep(0.6, 0.62, k[1]))
    alb = lerp(alb, col('3a2a1a'), smoothstep(0.65, 0.67, k[2]))
    save('skin_kamuflaj', alb, None, 0.7 * np.ones((n, n)))
    # Kış: digital snow camo
    px = 32
    blk = np.random.default_rng(170).random((n // px, n // px))
    blk = np.kron(blk, np.ones((px, px)))
    alb = col('e6ebf0')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('9aa6b2'), (blk > 0.6).astype(float))
    alb = lerp(alb, col('4e5a66'), (blk > 0.85).astype(float))
    save('skin_kar', alb, None, 0.6 * np.ones((n, n)))


if __name__ == '__main__':
    which = sys.argv[1:] or None
    fns = [cobble, pavers, asphalt, plaster, wood_beam, planks, roof_tiles, stone_wall, painted_metal,
           corrugated, concrete, grass_dirt, water_normal, sandbag, gunmetal, polymer, gunwood, skins,
           lambda: planks(1024, 'deck', '8a6a48', 'b8946a', '1a1410', 10)]
    for f in fns:
        f()
