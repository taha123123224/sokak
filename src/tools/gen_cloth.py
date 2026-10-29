import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from gen_textures import *

def weave(n, period, twill=True):
    yy, xx = np.mgrid[0:n, 0:n]
    if twill:
        d = (xx + yy) % period
        return (np.sin(d / period * 2 * np.pi) * 0.5 + 0.5)
    a = np.sin(xx / period * 2 * np.pi) * 0.5 + 0.5
    b = np.sin(yy / period * 2 * np.pi) * 0.5 + 0.5
    return np.where(((xx // period) + (yy // period)) % 2 == 0, a, b)

def wool(n=1024):
    w = weave(n, 6)
    f = bandnoise(n, 150, 512, 201); big = fnoise(n, 2.2, 202)
    alb = np.ones((n, n, 3)) * (0.82 + 0.1 * w[..., None] + 0.06 * f[..., None] + 0.04 * big[..., None])
    save('cloth_wool', alb, w * 0.6 + f * 0.3 + big * 0.4, 0.82 + 0.1 * f, 3)

def cotton(n=1024):
    w = weave(n, 4, False)
    f = bandnoise(n, 200, 512, 211); big = fnoise(n, 2.4, 212)
    alb = np.ones((n, n, 3)) * (0.9 + 0.05 * w[..., None] + 0.04 * f[..., None])
    save('cloth_cotton', alb, w * 0.4 + f * 0.2 + big * 0.6, 0.85 * np.ones((n, n)), 3)

def denim(n=1024):
    w = weave(n, 5)
    f = bandnoise(n, 150, 512, 221); fade = fnoise(n, 2.0, 222)
    stre = bandnoise(n, 30, 200, 223)
    alb = lerp(col('1d2a44'), col('5b6f92'), np.clip(w * 0.5 + f * 0.3 + fade * 0.4 - 0.2, 0, 1))
    save('cloth_denim', alb, w * 0.7 + f * 0.3 + fade * 0.3, 0.85 * np.ones((n, n)), 4)

def leather(n=1024):
    F1, F2, cid, cnt = voronoi(n, 2500, seed=231)
    cr = smoothstep(0, 6, F2 - F1)
    big = fnoise(n, 2.2, 232); wrink = bandnoise(n, 4, 25, 233)
    alb = np.ones((n, n, 3)) * (0.85 + 0.1 * cr[..., None] + 0.1 * big[..., None])
    rough = 0.38 + 0.25 * (1 - cr) + 0.15 * big - 0.1 * smoothstep(0.6, 0.9, wrink)
    save('cloth_leather', alb, cr * 0.4 + wrink * 0.8 + big * 0.2, rough, 4)

def nylon(n=1024):
    yy, xx = np.mgrid[0:n, 0:n]
    w = ((xx // 3 + yy // 3) % 2).astype(float)
    f = bandnoise(n, 120, 512, 241); big = fnoise(n, 2.0, 242)
    alb = np.ones((n, n, 3)) * (0.85 + 0.08 * w[..., None] + 0.06 * f[..., None] + 0.05 * big[..., None])
    # molle webbing rows
    rows = ((yy % 64) < 14).astype(float)
    alb = alb * (1 - 0.12 * rows[..., None])
    save('cloth_nylon', alb, w * 0.3 + rows * 0.8 + f * 0.2, 0.7 + 0.1 * f, 4)

def camo(n=1024):
    k = [fnoise(n, 3.2, 250 + i) for i in range(3)]
    alb = col('6b6a4c')[None, None] * np.ones((n, n, 3))
    alb = lerp(alb, col('4b5236'), smoothstep(0.55, 0.57, k[0]))
    alb = lerp(alb, col('8a7d5c'), smoothstep(0.6, 0.62, k[1]))
    alb = lerp(alb, col('3a3324'), smoothstep(0.66, 0.68, k[2]))
    w = weave(n, 4, False)
    alb = alb * (0.92 + 0.08 * w[..., None])
    save('cloth_camo', alb, w * 0.4 + fnoise(n, 2.4, 255) * 0.5, 0.85 * np.ones((n, n)), 3)

def hair(n=1024):
    yy, xx = np.mgrid[0:n, 0:n] / n
    warp = fnoise(n, 2.4, 261)
    strands = bandnoise(n, 200, 512, 262)
    strands = np.repeat(strands[:1, :], n, 0) * 0.6 + strands * 0.4  # stretched along y
    s2 = np.sin((xx * 300 + warp * 30) * np.pi) * 0.5 + 0.5
    alb = np.ones((n, n, 3)) * (0.5 + 0.3 * strands[..., None] + 0.2 * s2[..., None])
    save('hair_strands', alb, strands * 0.7 + s2 * 0.5, 0.55 + 0.2 * strands, 4)

def skin(n=1024):
    pores = bandnoise(n, 250, 512, 271)
    pores = smoothstep(0.75, 0.95, pores)
    fine = bandnoise(n, 100, 400, 272); blot = fnoise(n, 2.4, 273)
    alb = np.ones((n, n, 3)) * (0.94 + 0.06 * blot[..., None] - 0.05 * pores[..., None])
    # subtle red/blue variation
    alb[..., 0] *= 1 + 0.03 * (fnoise(n, 2.2, 274) - 0.5)
    alb[..., 2] *= 1 + 0.03 * (fnoise(n, 2.2, 275) - 0.5)
    save('skin_detail', alb, -pores * 0.6 + fine * 0.3, 0.5 + 0.15 * fine + 0.1 * pores, 3)

def boots(n=512):
    big = fnoise(n, 2.2, 281); f = bandnoise(n, 100, 256, 282)
    alb = np.ones((n, n, 3)) * (0.85 + 0.1 * big[..., None] + 0.05 * f[..., None])
    save('cloth_bootleather', alb, f * 0.4 + big * 0.3, 0.45 + 0.2 * big, 3)

for fn in [wool, cotton, denim, leather, nylon, camo, hair, skin, boots]:
    fn()
