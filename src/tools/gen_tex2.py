"""Second texture pass: realistic stucco, window interiors, grime/streak overlays, posters."""
import sys, os, math, random
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont
sys.path.insert(0, os.path.dirname(__file__))
from gen_textures import fnoise, bandnoise, save, smoothstep, lerp, col, OUT, normal_from_height

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def stucco(n=1024):
    grain = bandnoise(n, 200, 500, 21)              # sand grain
    mid = bandnoise(n, 25, 80, 22)                  # trowel unevenness
    big = fnoise(n, 2.6, 23)                        # large tone variation
    # vertical rain streaks: noise stretched vertically
    st = bandnoise(n, 4, 40, 24)
    st = np.asarray(Image.fromarray((st * 255).astype(np.uint8)).resize((n // 8, n)).resize((n, n), Image.BICUBIC), np.float32) / 255
    streak = smoothstep(0.62, 0.9, st) * 0.6
    tone = 0.9 + 0.07 * (big - 0.5) + 0.05 * (mid - 0.5) + 0.06 * (grain - 0.5)
    alb = np.ones((n, n, 3)) * tone[..., None]
    alb *= (1 - 0.1 * streak)[..., None]
    # hairline cracks
    img = Image.new('L', (n, n), 0)
    d = ImageDraw.Draw(img)
    rr = random.Random(3)
    for _ in range(9):
        x, y = rr.uniform(0, n), rr.uniform(0, n)
        a = rr.uniform(0, math.tau)
        for k in range(rr.randint(10, 40)):
            a += rr.uniform(-0.5, 0.5)
            nx, ny = x + math.cos(a) * 6, y + math.sin(a) * 6
            if 0 <= nx < n and 0 <= ny < n:
                d.line([(x, y), (nx, ny)], fill=255, width=1)
            else:
                break
            x, y = nx, ny
    crack = np.asarray(img, np.float32) / 255
    alb *= (1 - 0.22 * crack)[..., None]
    h = 0.55 * grain + 0.35 * mid + 0.1 * big - 0.5 * crack
    save('plaster', alb, h, 0.88 + 0.08 * grain, 2.5)


def interiors():
    """window interior images (seen through glass): curtains, blinds, rooms, lit rooms"""
    W, H = 256, 320
    rr = random.Random(9)
    curtain_cols = [(200, 60, 55), (235, 225, 200), (90, 120, 170), (210, 180, 120), (120, 150, 110), (240, 240, 240)]
    for i in range(8):
        im = Image.new('RGB', (W, H), (0, 0, 0))
        d = ImageDraw.Draw(im)
        lit = i in (2, 6)
        # room back wall + ceiling light falloff
        wall = (60, 55, 52) if not lit else (210, 170, 110)
        for y in range(H):
            k = y / H
            c = tuple(int(v * (0.55 + 0.45 * k) if not lit else v * (1.0 - 0.35 * k)) for v in wall)
            d.line([(0, y), (W, y)], fill=c)
        # furniture silhouettes
        if rr.random() < 0.7:
            d.rectangle([rr.randint(10, 80), int(H * 0.62), rr.randint(140, 240), H], fill=(30, 26, 24) if not lit else (120, 80, 50))
        if rr.random() < 0.5:
            x = rr.randint(40, 200)
            d.rectangle([x, int(H * 0.25), x + 40, int(H * 0.5)], fill=(90, 80, 70) if not lit else (230, 200, 150))   # picture frame
        if lit:
            d.ellipse([W // 2 - 30, 10, W // 2 + 30, 40], fill=(255, 240, 200))
        style = i % 4
        cc = curtain_cols[i % len(curtain_cols)]
        if style in (0, 2):        # side curtains with folds
            for side in (0, 1):
                cw = rr.randint(60, 100)
                x0 = 0 if side == 0 else W - cw
                for x in range(cw):
                    fold = 0.75 + 0.25 * math.sin((x / cw) * math.pi * rr.choice([5, 6, 7]))
                    c = tuple(int(v * fold) for v in cc)
                    d.line([(x0 + x, 0), (x0 + x, H)], fill=c)
            # sheer tulle in the middle
            tul = Image.new('RGB', (W, H), (235, 235, 230))
            im = Image.blend(im, tul, 0.35 if style == 0 else 0.0)
            d = ImageDraw.Draw(im)
        elif style == 1:           # venetian blinds half down
            down = rr.randint(int(H * 0.3), int(H * 0.8))
            for y in range(0, down, 9):
                d.rectangle([0, y, W, y + 6], fill=(205, 200, 190))
                d.line([(0, y + 6), (W, y + 6)], fill=(150, 145, 135))
        else:                      # tulle full
            tul = Image.new('RGB', (W, H), (238, 236, 228))
            im = Image.blend(im, tul, 0.75)
            d = ImageDraw.Draw(im)
            for x in range(0, W, 14):
                d.line([(x, 0), (x, H)], fill=(215, 212, 205))
        # sky reflection gradient (top brighter) + slight blue
        arr = np.asarray(im, np.float32) / 255
        yy = np.linspace(1, 0, H)[:, None, None]
        refl = np.array([0.55, 0.68, 0.85])[None, None, :]
        arr = arr * (1 - 0.32 * yy) + refl * 0.32 * yy
        Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, f'win_int{i}.png'))
    print('interiors ok')


def grime():
    """RGBA overlays: bottom-of-wall dirt gradient and rain streaks under sills"""
    n = 512
    r = np.random.default_rng(5)
    x = bandnoise(n, 3, 40, 31)
    yy = np.linspace(0, 1, n)[:, None]           # 0 top .. 1 bottom
    a = smoothstep(0.25, 1.0, yy) ** 1.4 * (0.6 + 0.4 * x)
    rgba = np.zeros((n, n, 4))
    rgba[..., 0] = 0.22; rgba[..., 1] = 0.2; rgba[..., 2] = 0.17
    rgba[..., 3] = np.clip(a * 0.75, 0, 1)
    Image.fromarray((rgba * 255).astype(np.uint8)).save(os.path.join(OUT, 'grime_bottom.png'))
    # streaks: vertical drips fading downward
    st = bandnoise(n, 6, 60, 32)
    st = np.asarray(Image.fromarray((st * 255).astype(np.uint8)).resize((n // 10, n)).resize((n, n), Image.BICUBIC), np.float32) / 255
    a = smoothstep(0.5, 0.85, st) * (1 - yy) ** 0.8
    rgba[..., 3] = np.clip(a * 0.55, 0, 1)
    rgba[..., 0] = 0.18; rgba[..., 1] = 0.17; rgba[..., 2] = 0.15
    Image.fromarray((rgba * 255).astype(np.uint8)).save(os.path.join(OUT, 'grime_streak.png'))
    print('grime ok')


def posters():
    fdir = os.path.join(ROOT, 'assets', 'fonts')
    f1 = ImageFont.truetype(os.path.join(fdir, 'RussoOne-Regular.ttf'), 44)
    f2 = ImageFont.truetype(os.path.join(fdir, 'Rajdhani-Bold.ttf'), 30)
    texts = [('KONSER', 'CUMARTESİ 21:00', (200, 40, 40)), ('KİRALIK', '0532 ••• •• ••', (240, 200, 40)), ('SATILIK DAİRE', '3+1  •  ACİL', (40, 120, 200)),
             ('BÜYÜK İNDİRİM', '%50', (230, 90, 20)), ('SİNEMA', 'BU HAFTA', (40, 40, 40)), ('DÜĞÜN SALONU', 'REZERVASYON', (150, 60, 160))]
    for i, (t1, t2, c) in enumerate(texts):
        im = Image.new('RGB', (300, 420), (235, 230, 215))
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, 300, 150], fill=c)
        d.text((150, 75), t1, font=f1, fill=(255, 255, 255), anchor='mm')
        d.text((150, 200), t2, font=f2, fill=(30, 30, 30), anchor='mm')
        for k in range(5):
            d.rectangle([30, 250 + k * 28, 270 - (k * 23) % 90, 262 + k * 28], fill=(150, 145, 135))
        arr = np.asarray(im, np.float32) / 255
        wear = fnoise(420, 2.2, 40 + i)[:420, :300]
        arr *= (0.85 + 0.15 * wear)[..., None]
        Image.fromarray((np.clip(arr, 0, 1) * 255).astype(np.uint8)).save(os.path.join(ROOT, 'assets', 'tex', 'signs', f'poster{i}.png'))
    print('posters ok')


def skins2(n=1024):
    from gen_textures import voronoi
    yy, xx = np.mgrid[0:n, 0:n] / n
    # Osmanlı Çini: Iznik tile pattern (cobalt + turquoise + coral on white)
    q = 8
    u = (xx * q) % 1 - 0.5; v = (yy * q) % 1 - 0.5
    r = np.sqrt(u * u + v * v); a = np.arctan2(v, u)
    petal = smoothstep(0.02, 0.0, np.abs(r - 0.28 - 0.08 * np.cos(a * 6))) 
    flower = smoothstep(0.13, 0.11, r * (1 + 0.25 * np.cos(a * 8)))
    diag = smoothstep(0.03, 0.0, np.abs(np.abs(u) + np.abs(v) - 0.5))
    alb = col('f2eee4')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('1f4fa8'), np.clip(petal + diag, 0, 1))
    alb = lerp(alb, col('d8432f'), flower)
    alb = lerp(alb, col('25a0a0'), smoothstep(0.05, 0.0, np.abs(r - 0.18)) * 0.9)
    save('skin_cini', alb, None, 0.22 * np.ones((n, n)))
    # Lav: black basalt with glowing orange cracks
    f1, f2, _, _ = voronoi(n, 90, 201)
    crack = smoothstep(6, 1.5, f2 - f1)
    base = 0.08 + 0.06 * fnoise(n, 2.4, 202)
    alb = np.ones((n, n, 3)) * base[..., None]
    alb = lerp(alb, col('ff6a10'), crack)
    alb = lerp(alb, col('ffd040'), crack ** 3)
    save('skin_lav', alb, None, 0.6 - 0.3 * crack)
    # Karbon: woven carbon fibre with clear coat
    t = 64
    wx = (np.floor(xx * t) + np.floor(yy * t)) % 2
    sx = 0.5 + 0.5 * np.sin(xx * t * np.pi * 2)
    sy = 0.5 + 0.5 * np.sin(yy * t * np.pi * 2)
    shade = np.where(wx > 0, sx, sy)
    alb = np.ones((n, n, 3)) * (0.04 + 0.09 * shade)[..., None]
    save('skin_karbon', alb, None, 0.25 * np.ones((n, n)))
    # Buz Kristali: icy blue facets
    f1, f2, ids, cnt = voronoi(n, 160, 203)
    rr = np.random.default_rng(204).random(cnt)
    facet = rr[ids]
    alb = lerp(col('9fd8ff'), col('e8f8ff'), facet[..., None])
    alb = lerp(alb, col('3a8fd0'), smoothstep(3, 0.5, f2 - f1))
    save('skin_buz', alb, None, 0.12 * np.ones((n, n)))
    # Şehir dijital: urban digital camo
    px = 24
    rg = np.random.default_rng(205)
    blk = np.kron(rg.random((n // px + 1, n // px + 1)), np.ones((px, px)))[:n, :n]
    blk2 = np.kron(rg.random((n // (px * 2) + 1, n // (px * 2) + 1)), np.ones((px * 2, px * 2)))[:n, :n]
    alb = col('6b7178')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('2c3034'), (blk2 > 0.62).astype(float))
    alb = lerp(alb, col('a8adb2'), (blk > 0.78).astype(float))
    save('skin_dijital', alb, None, 0.65 * np.ones((n, n)))
    # Turkuaz Altın: turquoise enamel with gold filigree
    fil = smoothstep(0.035, 0.0, np.abs(np.sin(xx * 20 * np.pi + np.sin(yy * 8 * np.pi) * 2) * np.sin(yy * 20 * np.pi + np.sin(xx * 8 * np.pi) * 2)))
    alb = lerp(col('0fa3a3'), col('f0c048'), fil)
    save('skin_turkuaz', alb, None, 0.25 - 0.1 * fil)


if __name__ == '__main__':
    if len(sys.argv) > 1 and sys.argv[1] == "skins":
        skins2()
    else:
        stucco(); interiors(); grime(); posters(); skins2()

