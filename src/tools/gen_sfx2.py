"""Sound pass 2: layered realistic gunshots, mechanical foley, living ambiences (44.1k 16-bit)."""
import os, sys, wave
import numpy as np
from scipy.signal import butter, lfilter, fftconvolve
SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'sfx')
rng = np.random.default_rng(11)


def T(d): return np.arange(int(SR * d)) / SR
def N(d): return rng.standard_normal(int(SR * d))
def bp(x, lo, hi, o=2):
    b, a = butter(o, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], 'band'); return lfilter(b, a, x)
def lp(x, f, o=2):
    b, a = butter(o, min(f / (SR / 2), 0.99), 'low'); return lfilter(b, a, x)
def hp(x, f, o=2):
    b, a = butter(o, f / (SR / 2), 'high'); return lfilter(b, a, x)
def env(n, a, d, sustain=0.0):
    t = np.arange(n) / SR
    return np.minimum(t / max(a, 1e-5), 1.0) * (sustain + (1 - sustain) * np.exp(-np.maximum(t - a, 0) / d))
def mix(*xs):
    n = max(len(x) for x in xs); o = np.zeros(n)
    for x in xs: o[:len(x)] += x
    return o
def at(x, sec, total):
    o = np.zeros(int(SR * total)); i = int(SR * sec); k = min(len(x), len(o) - i)
    if k > 0: o[i:i + k] += x[:k]
    return o
def sat(x, d=2.0): return np.tanh(x * d) / np.tanh(d)
def sweep(f0, f1, d, k):
    t = T(d); f = f1 + (f0 - f1) * np.exp(-t * k); return np.sin(2 * np.pi * np.cumsum(f) / SR)
def save(name, x, gain=0.92, stereo=False):
    x = x - np.mean(x)
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    f = int(SR * 0.01); x[-f:] *= np.linspace(1, 0, f)
    with wave.open(os.path.join(OUT, name + '.wav'), 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype(np.int16).tobytes())
    print('sfx', name, round(len(x) / SR, 2))


def outdoor_tail(x, length, size=1.0, bright=3500, wet=0.45):
    """slap-back echoes off buildings + diffuse urban decay"""
    total = len(x) / SR + length
    y = at(x, 0, total)
    for dly, g, f in ((0.055, 0.35, 5000), (0.11, 0.28, 3500), (0.19, 0.22, 2500), (0.31, 0.16, 1800), (0.47, 0.1, 1200)):
        y += at(lp(x, f) * g * size, dly * size, total)
    ir = N(length) * np.exp(-T(length) / (0.35 * size)) 
    ir = lp(ir, bright)
    ir[:int(SR * 0.02)] *= np.linspace(0, 1, int(SR * 0.02))
    dif = fftconvolve(x, ir)[:len(y)]
    dif = dif / (np.max(np.abs(dif)) + 1e-9) * np.max(np.abs(x)) * wet
    return mix(y, dif)


def gunshot(name, cal=1.0, rifle=True, length=1.3, mech_f=(2300, 3700, 5200), boom=1.0, snap=1.0, bright=1.0, tail=1.0):
    d = 0.4
    # 1) muzzle transient (pressure spike) + supersonic snap (N-wave) for rifles
    spike = hp(N(0.004), 2000) * env(int(SR * 0.004), 0.00005, 0.0007) * 1.6
    nw = np.zeros(int(SR * 0.003)); m = len(nw); nw[:m // 2] = np.linspace(1, -1, m // 2); nw[m // 2:] = np.linspace(-1, 0, m - m // 2)
    nwave = hp(nw, 1500) * (1.2 * snap if rifle else 0.3 * snap)
    # 2) blast body: broadband with two-stage decay
    body = bp(N(d), 90, 6500 * bright) * (env(int(SR * d), 0.0002, 0.012 * cal) * 0.9 + env(int(SR * d), 0.001, 0.06 * cal) * 0.35)
    # 3) low boom / chest thump
    th = sat(sweep(180 / cal ** 0.3, 42, d, 18) * env(int(SR * d), 0.0008, 0.08 * cal), 2.5) * 0.9 * boom
    # 4) mechanical action: bolt carrier / slide with metal resonances
    mt = bp(N(0.05), 1500, 9000) * env(int(SR * 0.05), 0.0002, 0.004)
    for f in mech_f:
        mt += np.sin(2 * np.pi * f * T(0.05)) * env(int(SR * 0.05), 0.0002, 0.012) * 0.25
    x = mix(at(spike, 0, d), at(nwave, 0.0004, d), body, th, at(mt * 0.35, 0.022, d))
    x = sat(x, 2.2)
    x = outdoor_tail(x, length, size=0.9 + 0.3 * cal, bright=3000 * bright, wet=0.5 * tail)
    save(name, x[:int(SR * length)])


def distant(name, heavy=False):
    x = mix(lp(bp(N(0.3), 60, 1200), 900) * env(int(SR * 0.3), 0.003, 0.05),
            sweep(90, 40, 0.3, 10) * env(int(SR * 0.3), 0.002, 0.07) * (0.8 if heavy else 0.4))
    x = outdoor_tail(x, 1.8, 1.6, 1200, 0.9)
    save(name, x[:int(SR * 1.8)], 0.75)


def foley(name, hits, total):
    """hits: list of (time, lo, hi, decay, ring_freqs, gain)"""
    x = np.zeros(int(SR * total))
    for (tm, lo, hi, dec, rings, g) in hits:
        h = bp(N(0.08), lo, hi) * env(int(SR * 0.08), 0.0002, dec)
        for f in rings:
            h += np.sin(2 * np.pi * f * T(0.08)) * env(int(SR * 0.08), 0.0003, dec * 2.5) * 0.3
        x += at(h * g, tm, total)
    x = outdoor_tail(x, 0.25, 0.4, 5000, 0.2)[:int(SR * total)]
    save(name, x, 0.8)


def build_guns():
    gunshot('shot_ak', cal=1.15, rifle=True, length=1.4, mech_f=(1900, 3100, 4600), boom=1.2, bright=0.85)
    gunshot('shot_m4', cal=0.95, rifle=True, length=1.3, mech_f=(2400, 3900, 5600), boom=0.9, bright=1.1)
    gunshot('shot_smg', cal=0.75, rifle=False, length=0.95, mech_f=(2800, 4300), boom=0.6, bright=1.05, tail=0.8)
    gunshot('shot_p90', cal=0.7, rifle=True, length=0.95, mech_f=(3000, 4800), boom=0.5, snap=0.6, bright=1.2, tail=0.8)
    gunshot('shot_shotgun', cal=1.6, rifle=False, length=1.9, mech_f=(1400, 2600), boom=1.7, bright=0.7, tail=1.2)
    gunshot('shot_sniper', cal=1.9, rifle=True, length=2.6, mech_f=(1600, 2900), boom=1.9, snap=1.6, bright=0.9, tail=1.4)
    gunshot('shot_pistol', cal=0.8, rifle=False, length=1.0, mech_f=(2600, 4100, 6000), boom=0.6, bright=1.1, tail=0.8)
    gunshot('shot_deagle', cal=1.4, rifle=False, length=1.5, mech_f=(1800, 3300), boom=1.5, bright=0.9, tail=1.1)
    distant('shot_far'); distant('shot_far_heavy', True)
    foley('mag_out', [(0.0, 800, 5000, 0.006, (1400, 2600), 1.0), (0.05, 300, 2500, 0.02, (700,), 0.8)], 0.3)
    foley('mag_in', [(0.0, 500, 4000, 0.01, (1100,), 0.7), (0.07, 900, 7000, 0.005, (1900, 3300), 1.0)], 0.3)
    foley('bolt_back', [(0.0, 900, 7000, 0.006, (2100, 3400), 1.0), (0.06, 500, 4000, 0.012, (1500,), 0.6)], 0.25)
    foley('bolt_fwd', [(0.0, 700, 6000, 0.008, (1800,), 0.7), (0.045, 1000, 8000, 0.005, (2400, 4100), 1.0)], 0.25)
    foley('pump', [(0.0, 300, 3000, 0.02, (650,), 0.9), (0.13, 400, 4000, 0.015, (900, 1500), 1.0)], 0.35)
    foley('shell_in', [(0.0, 600, 4000, 0.012, (1100,), 0.8), (0.04, 300, 2000, 0.02, (500,), 0.5)], 0.2)
    foley('equip', [(0.0, 300, 3000, 0.03, (500,), 0.4), (0.08, 900, 6000, 0.006, (1700, 2900), 0.8)], 0.25)
    foley('dryfire', [(0.0, 2000, 8000, 0.003, (3300,), 1.0)], 0.12)
    for i in range(3):
        f0 = 3200 + i * 400
        x = mix(*[at(np.sin(2 * np.pi * (f0 + k * 150) * T(0.25)) * env(int(SR * 0.25), 0.0003, 0.05 / (k + 1)) * (0.7 ** k), k * 0.07, 0.5) for k in range(3)])
        save(f'shell{i}', x, 0.35)


def build_amb():
    L = 40.0
    t = T(L)
    def loopify(x, cf=2.0):
        n = int(SR * cf); a = x[:n] * np.linspace(0, 1, n); b = x[-n:] * np.linspace(1, 0, n)
        return np.concatenate([a + b, x[n:-n]])
    def birds(count, base=3000):
        o = np.zeros(int(SR * L))
        for k in range(count):
            s0 = rng.uniform(0, L - 1.5)
            for j in range(rng.integers(2, 6)):
                d = rng.uniform(0.06, 0.16)
                f = base * rng.uniform(0.8, 1.4)
                ch = np.sin(2 * np.pi * np.cumsum(f + f * 0.25 * np.sin(2 * np.pi * rng.uniform(15, 40) * T(d))) / SR) * env(int(SR * d), 0.008, d * 0.4)
                o += at(ch * rng.uniform(0.05, 0.15), s0 + j * rng.uniform(0.12, 0.25), L)
        return o
    def doves(count):
        o = np.zeros(int(SR * L))
        for k in range(count):
            s0 = rng.uniform(0, L - 3)
            for j, (f, d) in enumerate([(420, 0.35), (380, 0.25), (430, 0.5)]):
                c = np.sin(2 * np.pi * f * T(d) + 3 * np.sin(2 * np.pi * 6 * T(d))) * env(int(SR * d), 0.05, d * 0.5)
                o += at(lp(c, 900) * 0.08, s0 + j * 0.45, L)
        return o
    def gulls(count):
        o = np.zeros(int(SR * L))
        for k in range(count):
            s0 = rng.uniform(0, L - 2)
            for j in range(rng.integers(2, 4)):
                d = rng.uniform(0.25, 0.45)
                f = 1500 + 700 * np.exp(-T(d) * 6)
                g = sum(np.sin(2 * np.pi * np.cumsum(f * h) / SR) / h for h in (1, 2, 3)) * env(int(SR * d), 0.02, d * 0.5)
                o += at(bp(g, 600, 6000) * 0.07, s0 + j * (d + 0.1), L)
        return o
    def cars(count):
        o = np.zeros(int(SR * L))
        for k in range(count):
            s0 = rng.uniform(0, L - 6); d = rng.uniform(4, 6)
            sw = np.sin(np.pi * T(d) / d) ** 2
            o += at(lp(bp(N(d), 60, 900), 700) * sw * 0.35, s0, L)
        return o
    wind = bp(N(L), 150, 900) * (0.45 + 0.35 * np.sin(2 * np.pi * 0.05 * t) + 0.2 * np.sin(2 * np.pi * 0.13 * t + 1)) * 0.5
    rumble = lp(N(L), 160) * 0.6
    murmur = bp(N(L), 300, 1400) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.2 * t)) * 0.06
    city = rumble * 0.7 + cars(7) + birds(10) + murmur + wind * 0.3
    for k in range(3):   # distant car horns / dog
        s0 = rng.uniform(1, L - 2)
        h = (np.sign(np.sin(2 * np.pi * 420 * T(0.4))) + np.sign(np.sin(2 * np.pi * 530 * T(0.4)))) * env(int(SR * 0.4), 0.01, 0.3)
        city += at(lp(h, 1500) * 0.03, s0, L)
    save('amb_city', loopify(city), 0.4)
    town = wind * 0.8 + birds(18, 3400) + doves(6) + lp(N(L), 120) * 0.25
    save('amb_town', loopify(town), 0.38)
    waves = lp(N(L), 600) * (0.55 + 0.45 * np.sin(2 * np.pi * 0.11 * t) ** 2) + lp(N(L), 140) * 0.5
    ship = waves + gulls(9) + wind * 0.6
    for k in range(4):   # hull creaks / metal clanks
        s0 = rng.uniform(1, L - 2)
        cr = bp(N(0.8), 120, 600) * env(int(SR * 0.8), 0.2, 0.25) * 0.15
        ship += at(cr, s0, L)
    horn = lp(sum(np.sin(2 * np.pi * f * T(3.0)) for f in (110, 165, 220)) * env(int(SR * 3.0), 0.3, 1.2, 0.6), 600) * 0.05
    ship += at(horn, 14.0, L)
    save('amb_ship', loopify(ship), 0.42)
    port = waves * 0.7 + gulls(6) + rumble * 0.5 + wind * 0.4
    for k in range(6):
        s0 = rng.uniform(1, L - 1)
        cl = bp(N(0.15), 400, 4000) * env(int(SR * 0.15), 0.001, 0.03) + np.sin(2 * np.pi * 620 * T(0.15)) * env(int(SR * 0.15), 0.001, 0.06) * 0.4
        port += at(cl * 0.06, s0, L)
    beep = np.sign(np.sin(2 * np.pi * 1000 * T(0.25))) * 0.02
    for k in range(5):   # distant forklift reversing beeps
        port += at(lp(beep, 3000), 22 + k * 0.6, L)
    save('amb_port', loopify(port), 0.42)


if __name__ == '__main__':
    build_guns(); build_amb()
