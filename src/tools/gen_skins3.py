"""v2.6 weapon skins (original designs) -> assets/tex/skin_<id>_albedo.png (+ orm)"""
import sys, os, math
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(__file__))
from gen_textures import fnoise, bandnoise, save, smoothstep, lerp, col, voronoi

n = 1024
yy, xx = np.mgrid[0:n, 0:n] / n


def ones(v):
    return v * np.ones((n, n))


def aurora():
    # Kuzey Işığı: deep navy with flowing green-violet light bands
    w = np.sin(xx * 6 + 3 * fnoise(n, 1.5, 301)) * 0.5 + 0.5
    band = smoothstep(0.55, 1.0, np.sin((yy + 0.25 * w) * 9 * math.pi) * 0.5 + 0.5)
    alb = lerp(col('071226'), col('0b2d4a'), yy[..., None])
    alb = lerp(alb, col('35f0a0'), (band * (1 - yy))[..., None] * 0.9)
    alb = lerp(alb, col('b45cff'), (band * yy)[..., None] * 0.7)
    stars = (np.random.default_rng(302).random((n, n)) > 0.9993).astype(float)
    alb = lerp(alb, col('ffffff'), stars[..., None])
    save('skin_aurora', alb, None, ones(0.2))


def zumrut():
    # Zümrüt: emerald hexagon gems with gold seams
    f1, f2, ids, cnt = voronoi(n, 140, 311)
    facet = np.random.default_rng(312).random(cnt)[ids]
    alb = lerp(col('06512f'), col('2fd38a'), facet[..., None])
    alb = lerp(alb, col('e8c25a'), smoothstep(3.0, 0.8, f2 - f1)[..., None])
    save('skin_zumrut', alb, None, 0.12 + 0.4 * smoothstep(3.0, 0.8, f2 - f1))


def ayyildiz():
    # Ay Yıldız: deep red lacquer with repeating white crescent-and-star emblems
    im = Image.new('RGB', (n, n), (150, 8, 14))
    d = ImageDraw.Draw(im)
    step = 256
    for gy in range(0, n, step):
        for gx in range(0, n, step):
            ox = gx + (step // 2 if (gy // step) % 2 else 0)
            cx, cy, r = ox + 92, gy + 128, 62
            d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(238, 238, 236))
            r2 = r * 0.8
            d.ellipse([cx - r2 + 16, cy - r2, cx + r2 + 16, cy + r2], fill=(150, 8, 14))
            sx, sy, sr = cx + 70, cy, 26
            pts = []
            for i in range(10):
                rr = sr if i % 2 == 0 else sr * 0.4
                a = math.radians(i * 36)
                pts.append((sx + rr * math.cos(a), sy + rr * math.sin(a)))
            d.polygon(pts, fill=(238, 238, 236))
    a = np.asarray(im, np.float32) / 255
    a *= (0.92 + 0.08 * fnoise(n, 3, 321))[..., None]
    save('skin_ayyildiz', a, None, ones(0.24))


def lale():
    # Lale Devri: ivory with stylised tulip ornaments in red and teal
    im = Image.new('RGB', (n, n), (238, 228, 205))
    d = ImageDraw.Draw(im)
    s = 128
    for gy in range(0, n + s, s):
        for gx in range(0, n + s, s):
            ox = gx + (s // 2 if (gy // s) % 2 else 0)
            # stem + leaves
            d.line([(ox, gy + 20), (ox, gy + 92)], fill=(25, 120, 110), width=6)
            d.ellipse([ox - 32, gy + 50, ox - 4, gy + 70], fill=(25, 120, 110))
            d.ellipse([ox + 4, gy + 58, ox + 32, gy + 78], fill=(25, 120, 110))
            # tulip head
            d.polygon([(ox - 22, gy + 20), (ox - 14, gy - 18), (ox, gy + 4), (ox + 14, gy - 18), (ox + 22, gy + 20), (ox, gy + 32)], fill=(200, 35, 40))
            d.polygon([(ox - 6, gy + 12), (ox, gy - 22), (ox + 6, gy + 12)], fill=(240, 90, 70))
    a = np.asarray(im.filter(ImageFilter.GaussianBlur(0.8)), np.float32) / 255
    save('skin_lale', a, None, ones(0.28))


def nazar():
    # Nazar: cobalt glass with evil-eye rings
    q = 7
    u = (xx * q) % 1 - 0.5; v = ((yy * q) % 1 - 0.5) * 1.15
    r = np.sqrt(u * u + v * v)
    alb = col('0b2e9c')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('f4f6fb'), smoothstep(0.24, 0.22, r)[..., None])
    alb = lerp(alb, col('5fb8ff'), smoothstep(0.17, 0.15, r)[..., None])
    alb = lerp(alb, col('05060a'), smoothstep(0.08, 0.06, r)[..., None])
    alb = lerp(alb, col('ffffff'), smoothstep(0.025, 0.0, np.hypot(u + 0.03, v + 0.03))[..., None])
    save('skin_nazar', alb, None, ones(0.08))


def kehribar():
    # Kehribar: warm amber resin with inner swirls
    f = fnoise(n, 3.2, 331); g = fnoise(n, 9.0, 332)
    sw = np.sin((f * 6 + g) * math.pi) * 0.5 + 0.5
    alb = lerp(col('6a2c02'), col('f0a020'), sw[..., None])
    alb = lerp(alb, col('ffe08a'), smoothstep(0.85, 1.0, sw)[..., None])
    save('skin_kehribar', alb, None, ones(0.1))


def siber():
    # Siber Neon: black with cyan / magenta circuit grid
    t = 32
    gx = np.abs(((xx * t) % 1) - 0.5); gy = np.abs(((yy * t) % 1) - 0.5)
    rng = np.random.default_rng(341)
    cell = np.kron(rng.random((t, t)), np.ones((n // t, n // t)))
    line = np.maximum(smoothstep(0.40, 0.48, gx) * (cell > 0.5), smoothstep(0.40, 0.48, gy) * (cell < 0.45))
    alb = col('07070c')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('19f0ff'), (line * (xx < 0.5))[..., None])
    alb = lerp(alb, col('ff2bd6'), (line * (xx >= 0.5))[..., None])
    save('skin_siber', alb, None, ones(0.3))


def ejder():
    # Ejderha Pulu: overlapping dragon scales, crimson with gold rims
    q = 16
    gx = xx * q; gy = yy * q * 1.3
    row = np.floor(gy)
    u = (gx + (row % 2) * 0.5) % 1 - 0.5
    v = gy % 1
    d = np.sqrt(u * u + (v - 0.05) ** 2)        # distance to the scale's top centre (scales hang downward)
    body = 1 - smoothstep(0.42, 0.62, d)
    rim = smoothstep(0.5, 0.6, d) * (1 - smoothstep(0.6, 0.7, d))
    shade = np.clip(1.15 - d * 1.3, 0, 1)
    alb = lerp(col('1c0202'), col('c0181c'), (shade * body)[..., None])
    alb = lerp(alb, col('f2b440'), np.clip(rim * 1.4, 0, 1)[..., None])
    save('skin_ejder', alb, None, 0.28 - 0.16 * rim)


def mermer():
    # Mermer: white Marmara marble with grey and gold veins
    f = fnoise(n, 2.5, 351); g = fnoise(n, 7.0, 352)
    ridge = (1 - np.abs((f * 0.7 + g * 0.3) * 2 - 1)) ** 10
    ridge2 = (1 - np.abs(fnoise(n, 5.0, 354) * 2 - 1)) ** 16
    alb = lerp(col('f4f2ee'), col('dcdad4'), fnoise(n, 4, 353)[..., None])
    alb = lerp(alb, col('5a5a62'), np.clip(ridge * 1.2, 0, 1)[..., None])
    alb = lerp(alb, col('c9a24e'), np.clip(ridge2 * 1.3, 0, 1)[..., None])
    save('skin_mermer', alb, None, ones(0.08))


def col_fırtına():
    # Çöl Fırtınası: desert digital camo
    px = 20
    rg = np.random.default_rng(361)
    b1 = np.kron(rg.random((n // px + 1, n // px + 1)), np.ones((px, px)))[:n, :n]
    b2 = np.kron(rg.random((n // (px * 3) + 1, n // (px * 3) + 1)), np.ones((px * 3, px * 3)))[:n, :n]
    alb = col('c8ad80')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('8a6e4a'), (b2 > 0.6).astype(float)[..., None])
    alb = lerp(alb, col('e6d6b2'), (b1 > 0.8).astype(float)[..., None])
    alb = lerp(alb, col('4e3e2c'), ((b1 < 0.08) & (b2 > 0.4)).astype(float)[..., None])
    save('skin_col', alb, None, ones(0.7))


def okyanus():
    # Derin Okyanus: dark teal water caustics
    f1, f2, _, _ = voronoi(n, 120, 371)
    c = smoothstep(4.0, 0.5, f2 - f1)
    alb = lerp(col('021b2a'), col('075a6e'), yy[..., None])
    alb = lerp(alb, col('5ff0f0'), c[..., None] * 0.7)
    save('skin_okyanus', alb, None, ones(0.1))


def kan():
    # Kan Kırmızı: red carbon fibre
    t = 64
    wx = (np.floor(xx * t) + np.floor(yy * t)) % 2
    sx = 0.5 + 0.5 * np.sin(xx * t * np.pi * 2); sy = 0.5 + 0.5 * np.sin(yy * t * np.pi * 2)
    shade = np.where(wx > 0, sx, sy)
    alb = lerp(col('1a0204'), col('a8101a'), shade[..., None] * 0.8)
    save('skin_kan', alb, None, ones(0.22))


for f in [siber, ejder, mermer] if '--fix' in sys.argv else [aurora, zumrut, ayyildiz, lale, nazar, kehribar, siber, ejder, mermer, col_fırtına, okyanus, kan]:
    f(); print('skin', f.__name__)
