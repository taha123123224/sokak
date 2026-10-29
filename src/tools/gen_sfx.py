"""Procedural sound effects (WAV 44.1k mono/16bit) via numpy synthesis."""
import numpy as np, os, wave
from scipy.signal import butter, lfilter, fftconvolve

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(3)


def t(d):
    return np.arange(int(SR * d)) / SR


def noise(d):
    return rng.standard_normal(int(SR * d))


def bp(x, lo, hi, order=2):
    b, a = butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], 'band')
    return lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = butter(order, min(f / (SR / 2), 0.99), 'low')
    return lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = butter(order, f / (SR / 2), 'high')
    return lfilter(b, a, x)


def env(n, attack, decay, curve=1.0):
    tt = np.arange(n) / SR
    e = np.minimum(tt / max(attack, 1e-5), 1.0) * np.exp(-np.maximum(tt - attack, 0) / decay) ** curve
    return e


def pad(x, d):
    n = int(SR * d)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*xs):
    n = max(len(x) for x in xs)
    out = np.zeros(n)
    for x in xs:
        out[:len(x)] += x
    return out


def reverb(x, size=0.6, decay=0.35, wet=0.3, bright=4000):
    ir = noise(size) * np.exp(-t(size) / decay)
    ir = lp(ir, bright)
    ir[:int(SR * 0.008)] *= np.linspace(0, 1, int(SR * 0.008))
    y = fftconvolve(x, ir)[:len(x) + len(ir) - 1]
    y = y / (np.max(np.abs(y)) + 1e-9) * np.max(np.abs(x))
    return mix(x * (1 - wet * 0.5), y * wet)


def sat(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def save(name, x, gain=0.9):
    x = x / (np.max(np.abs(x)) + 1e-9) * gain
    # fade out last 5ms
    f = int(SR * 0.005)
    x[-f:] *= np.linspace(1, 0, f)
    d = (x * 32767).astype(np.int16)
    with wave.open(os.path.join(OUT, name + '.wav'), 'w') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())


def sweep(f0, f1, d, k=8):
    tt = t(d)
    f = f1 + (f0 - f1) * np.exp(-tt * k)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def gunshot(name, crack=1.0, body_lo=150, body_hi=3500, body_dec=0.09, thump_f=110, thump=1.0, tail=0.9, tail_dec=0.45, mech=0.2, drive=3.0, length=1.4):
    n = noise(length)
    c = hp(noise(0.012), 2500) * env(int(SR * 0.012), 0.0002, 0.003) * crack
    body = bp(n, body_lo, body_hi) * env(len(n), 0.0005, body_dec)
    th = sweep(thump_f * 2.2, thump_f * 0.45, 0.35, 14) * env(int(SR * 0.35), 0.001, 0.07) * thump
    tl = lp(bp(noise(length), 80, 2000), 1200) * env(int(SR * length), 0.02, tail_dec) * 0.25 * tail
    mc = bp(noise(0.04), 2000, 8000) * env(int(SR * 0.04), 0.0005, 0.006) * mech
    mc = np.concatenate([np.zeros(int(SR * 0.035)), mc])
    x = mix(c, body, th, tl, mc)
    x = sat(x, drive)
    x = reverb(x, 0.9, tail_dec * 0.6, 0.35, 3000)
    save(name, pad(x, length))


def distant(name, src_lo=80, dec=0.6):
    n = noise(1.6)
    x = lp(bp(n, src_lo, 900), 700) * env(len(n), 0.004, 0.08)
    x = mix(x, lp(noise(1.6), 400) * env(int(SR * 1.6), 0.03, dec) * 0.5)
    x = reverb(x, 1.2, 0.6, 0.6, 1500)
    save(name, pad(x, 1.6), 0.7)


def click(name, f_lo=1500, f_hi=7000, d=0.06, dec=0.008, n=1, gap=0.03, ring=0.0, ring_f=2500):
    parts = []
    for i in range(n):
        c = bp(noise(d), f_lo, f_hi) * env(int(SR * d), 0.0003, dec)
        if ring:
            c = mix(c, np.sin(2 * np.pi * ring_f * t(d)) * env(int(SR * d), 0.0005, dec * 3) * ring)
        parts.append(c)
        parts.append(np.zeros(int(SR * gap)))
    save(name, np.concatenate(parts), 0.8)


def build():
    # ---- weapons
    gunshot('shot_ak', crack=1.0, body_lo=120, body_hi=3200, body_dec=0.10, thump_f=95, thump=1.2, drive=3.5)
    gunshot('shot_m4', crack=1.2, body_lo=200, body_hi=5000, body_dec=0.08, thump_f=120, thump=0.9, drive=3.0)
    gunshot('shot_smg', crack=0.9, body_lo=300, body_hi=6000, body_dec=0.05, thump_f=150, thump=0.6, tail=0.6, tail_dec=0.3, drive=2.5, length=0.9)
    gunshot('shot_p90', crack=1.1, body_lo=400, body_hi=7000, body_dec=0.045, thump_f=170, thump=0.5, tail=0.5, tail_dec=0.28, drive=2.5, length=0.9)
    gunshot('shot_shotgun', crack=1.0, body_lo=80, body_hi=2500, body_dec=0.18, thump_f=70, thump=1.6, tail=1.2, tail_dec=0.7, drive=4.0, length=1.8)
    gunshot('shot_sniper', crack=1.5, body_lo=90, body_hi=4000, body_dec=0.2, thump_f=60, thump=1.8, tail=1.5, tail_dec=1.0, drive=4.5, length=2.4)
    gunshot('shot_pistol', crack=1.0, body_lo=300, body_hi=5000, body_dec=0.05, thump_f=160, thump=0.6, tail=0.6, tail_dec=0.35, drive=2.5, length=1.0)
    gunshot('shot_deagle', crack=1.3, body_lo=120, body_hi=3500, body_dec=0.12, thump_f=85, thump=1.4, tail=1.1, tail_dec=0.6, drive=4.0, length=1.5)
    distant('shot_far')
    distant('shot_far_heavy', 50, 0.9)
    # mechanical
    click('dryfire', 2000, 6000, 0.04, 0.004, ring=0.2, ring_f=3200)
    click('mag_out', 600, 4000, 0.12, 0.02, 2, 0.05, ring=0.3, ring_f=900)
    click('mag_in', 500, 5000, 0.1, 0.015, 2, 0.02, ring=0.4, ring_f=1200)
    click('bolt_back', 800, 6000, 0.08, 0.012, 1, 0.0, ring=0.5, ring_f=1800)
    click('bolt_fwd', 600, 5000, 0.12, 0.02, 2, 0.01, ring=0.6, ring_f=1500)
    click('pump', 300, 3000, 0.12, 0.03, 2, 0.12, ring=0.3, ring_f=700)
    click('shell_in', 600, 4000, 0.07, 0.012, ring=0.3, ring_f=1100)
    click('equip', 500, 5000, 0.1, 0.02, 2, 0.06, ring=0.25, ring_f=900)
    click('scope_in', 1500, 8000, 0.05, 0.008)
    # shells hitting ground
    for i in range(3):
        x = mix(*[np.concatenate([np.zeros(int(SR * (k * 0.07 + rng.random() * 0.03))), np.sin(2 * np.pi * (3800 + rng.random() * 900) * t(0.08)) * env(int(SR * 0.08), 0.0005, 0.015) * (0.7 ** k)]) for k in range(3)])
        save(f'shell{i}', pad(x, 0.35), 0.4)
    # knife
    x = bp(noise(0.35), 600, 7000) * env(int(SR * 0.35), 0.08, 0.06)
    save('knife_swing', x * np.linspace(0.3, 1, len(x)), 0.6)
    x = mix(lp(noise(0.25), 1200) * env(int(SR * 0.25), 0.001, 0.04), bp(noise(0.25), 2000, 6000) * env(int(SR * 0.25), 0.001, 0.02) * 0.4)
    save('knife_hit', x, 0.8)
    x = mix(bp(noise(0.3), 2500, 9000) * env(int(SR * 0.3), 0.001, 0.03), np.sin(2 * np.pi * 3100 * t(0.3)) * env(int(SR * 0.3), 0.001, 0.08) * 0.4)
    save('knife_wall', x, 0.7)
    # grenade
    click('pin', 2500, 9000, 0.15, 0.04, ring=0.8, ring_f=4200)
    x = bp(noise(0.3), 300, 3000) * env(int(SR * 0.3), 0.05, 0.05)
    save('throw', x, 0.5)
    x = mix(np.sin(2 * np.pi * 900 * t(0.15)) * env(int(SR * 0.15), 0.0005, 0.03), bp(noise(0.15), 500, 3000) * env(int(SR * 0.15), 0.0005, 0.01))
    save('bounce', x, 0.6)
    n = noise(3.0)
    x = mix(sat(lp(n, 900) * env(len(n), 0.002, 0.35), 4) * 1.2, sweep(150, 30, 1.2, 4) * env(int(SR * 1.2), 0.003, 0.3) * 1.5,
            hp(noise(0.05), 3000) * env(int(SR * 0.05), 0.0002, 0.006), lp(noise(3.0), 300) * env(int(SR * 3), 0.1, 1.0) * 0.4)
    x = reverb(x, 1.5, 1.0, 0.4, 2000)
    save('explosion', pad(x, 3.0), 1.0)
    # impacts
    for i in range(3):
        x = mix(bp(noise(0.2), 1500, 9000) * env(int(SR * 0.2), 0.0003, 0.012), lp(noise(0.2), 800) * env(int(SR * 0.2), 0.001, 0.03) * 0.5)
        save(f'imp_concrete{i}', x, 0.6)
        x = mix(np.sin(2 * np.pi * (2200 + i * 500) * t(0.4)) * env(int(SR * 0.4), 0.0003, 0.09), bp(noise(0.4), 2000, 8000) * env(int(SR * 0.4), 0.0003, 0.01))
        save(f'imp_metal{i}', x, 0.6)
        x = mix(lp(noise(0.25), 700) * env(int(SR * 0.25), 0.001, 0.025), bp(noise(0.25), 300, 1500) * env(int(SR * 0.25), 0.001, 0.04) * 0.7)
        save(f'imp_flesh{i}', x, 0.8)
        x = mix(bp(noise(0.3), 400, 2500) * env(int(SR * 0.3), 0.0005, 0.03), np.sin(2 * np.pi * (300 + i * 60) * t(0.3)) * env(int(SR * 0.3), 0.001, 0.05) * 0.5)
        save(f'imp_wood{i}', x, 0.6)
    # bullet whiz (near miss)
    tt = t(0.35)
    f = 1800 - 1200 * tt / 0.35
    x = bp(noise(0.35), 1000, 6000) * np.exp(-((tt - 0.12) ** 2) / 0.003) * (1 + 0.5 * np.sin(2 * np.pi * np.cumsum(f) / SR))
    save('whiz', x, 0.5)
    # footsteps (concrete, metal, wood, gravel)
    for i in range(4):
        x = mix(lp(noise(0.18), 900 + i * 100) * env(int(SR * 0.18), 0.002, 0.025), bp(noise(0.18), 2000, 6000) * env(int(SR * 0.18), 0.001, 0.008) * 0.3)
        save(f'step_concrete{i}', x, 0.35)
        x = mix(np.sin(2 * np.pi * (180 + i * 25) * t(0.3)) * env(int(SR * 0.3), 0.002, 0.06), bp(noise(0.3), 800, 4000) * env(int(SR * 0.3), 0.001, 0.02) * 0.6,
                np.sin(2 * np.pi * (1300 + i * 120) * t(0.3)) * env(int(SR * 0.3), 0.001, 0.05) * 0.2)
        save(f'step_metal{i}', x, 0.4)
        x = mix(lp(noise(0.25), 500) * env(int(SR * 0.25), 0.002, 0.04), np.sin(2 * np.pi * (140 + i * 15) * t(0.25)) * env(int(SR * 0.25), 0.002, 0.04) * 0.6)
        save(f'step_wood{i}', x, 0.4)
    x = lp(noise(0.3), 400) * env(int(SR * 0.3), 0.002, 0.06)
    save('land', mix(x, sweep(120, 50, 0.3) * env(int(SR * 0.3), 0.002, 0.05) * 0.6), 0.6)
    # player feedback
    save('hitmarker', mix(np.sin(2 * np.pi * 2400 * t(0.06)) * env(int(SR * 0.06), 0.0005, 0.012), bp(noise(0.06), 3000, 9000) * env(int(SR * 0.06), 0.0003, 0.004) * 0.6), 0.5)
    save('headshot', mix(np.sin(2 * np.pi * 3200 * t(0.35)) * env(int(SR * 0.35), 0.0005, 0.08), np.sin(2 * np.pi * 4800 * t(0.35)) * env(int(SR * 0.35), 0.0005, 0.05) * 0.5), 0.55)
    x = mix(np.sin(2 * np.pi * 880 * t(0.12)) * env(int(SR * 0.12), 0.001, 0.04), np.concatenate([np.zeros(int(SR * 0.08)), np.sin(2 * np.pi * 1320 * t(0.25)) * env(int(SR * 0.25), 0.001, 0.08)]))
    save('kill', x, 0.5)
    # headshot: metallic helmet 'tink' + wet crunch + low thump
    hs = mix(np.sin(2 * np.pi * 3300 * t(0.5)) * env(int(SR * 0.5), 0.0003, 0.12) * 0.7,
             np.sin(2 * np.pi * 5150 * t(0.5)) * env(int(SR * 0.5), 0.0003, 0.07) * 0.45,
             bp(noise(0.25), 600, 3000) * env(int(SR * 0.25), 0.0005, 0.03) * 0.9,
             sweep(160, 45, 0.3, 8) * env(int(SR * 0.3), 0.001, 0.07) * 0.9)
    save('headshot', reverb(hs, 0.4, 0.3, 0.18), 0.62)
    # gore splat (flesh burst)
    for i in range(2):
        g = mix(lp(noise(0.35), 1400 + i * 300) * env(int(SR * 0.35), 0.001, 0.05 + i * 0.02),
                bp(noise(0.35), 200, 900) * env(int(SR * 0.35), 0.003, 0.09) * 0.8,
                sweep(120, 40, 0.35, 6) * env(int(SR * 0.35), 0.002, 0.08) * 0.7)
        save(f'gore{i}', g, 0.6)
    # body fall
    bf = mix(lp(noise(0.6), 350) * env(int(SR * 0.6), 0.004, 0.09), sweep(90, 35, 0.6, 5) * env(int(SR * 0.6), 0.003, 0.12) * 0.8,
             np.concatenate([np.zeros(int(SR * 0.16)), lp(noise(0.4), 600) * env(int(SR * 0.4), 0.002, 0.05) * 0.6]))
    save('bodyfall', bf, 0.55)
    # multikill stinger: impact + rising power chord + shimmer
    d = 1.1
    n_ = int(SR * d)
    chord = mix(*[sat(np.sin(2 * np.pi * f * t(d)) + 0.5 * np.sin(2 * np.pi * f * 2 * t(d)), 2.5) * env(n_, 0.01, 0.35) * a
                  for f, a in ((110, 1.0), (164.8, 0.8), (220, 0.6))])
    shimmer = mix(*[np.sin(2 * np.pi * f * t(d)) * env(n_, 0.002, 0.25) * 0.25 for f in (1760, 2217, 2637)])
    hit = mix(lp(noise(0.5), 300) * env(int(SR * 0.5), 0.001, 0.12), sweep(70, 35, 0.5, 6) * env(int(SR * 0.5), 0.001, 0.15))
    rise = bp(noise(0.35), 1500, 7000) * np.linspace(0, 1, int(SR * 0.35)) ** 2 * 0.5
    save('multikill', reverb(mix(np.concatenate([rise, np.zeros(n_ - len(rise))]) * 0.0 + 0, hit, chord * 0.55, shimmer), 0.7, 0.4, 0.25), 0.75)
    save('medal', reverb(mix(bp(noise(0.25), 2000, 8000) * np.linspace(0, 1, int(SR * 0.25)) ** 3 * 0.6,
                             np.concatenate([np.zeros(int(SR * 0.2)), np.sin(2 * np.pi * 1568 * t(0.6)) * env(int(SR * 0.6), 0.001, 0.12) * 0.5 + np.sin(2 * np.pi * 2349 * t(0.6)) * env(int(SR * 0.6), 0.001, 0.1) * 0.3])), 0.5, 0.3, 0.2), 0.5)
    save('hurt', mix(lp(noise(0.3), 600) * env(int(SR * 0.3), 0.002, 0.05), sweep(300, 120, 0.3, 6) * env(int(SR * 0.3), 0.003, 0.06) * 0.6), 0.6)
    save('heartbeat', mix(sweep(90, 40, 0.15, 10) * env(int(SR * 0.15), 0.003, 0.04), np.concatenate([np.zeros(int(SR * 0.22)), sweep(80, 40, 0.15, 10) * env(int(SR * 0.15), 0.003, 0.04) * 0.7]), np.zeros(int(SR * 0.9))), 0.7)
    # UI
    save('ui_hover', np.sin(2 * np.pi * 1800 * t(0.04)) * env(int(SR * 0.04), 0.001, 0.008), 0.25)
    save('ui_click', mix(np.sin(2 * np.pi * 1200 * t(0.08)) * env(int(SR * 0.08), 0.001, 0.015), bp(noise(0.08), 2000, 7000) * env(int(SR * 0.08), 0.0005, 0.004) * 0.5), 0.45)
    save('ui_back', np.sin(2 * np.pi * 700 * t(0.1)) * env(int(SR * 0.1), 0.001, 0.02), 0.4)
    coins = mix(*[np.concatenate([np.zeros(int(SR * k * 0.05)), np.sin(2 * np.pi * (2600 + 400 * (k % 3)) * t(0.25)) * env(int(SR * 0.25), 0.0005, 0.05)]) for k in range(6)])
    save('buy', coins, 0.5)
    save('tick', mix(np.sin(2 * np.pi * 2000 * t(0.03)) * env(int(SR * 0.03), 0.0003, 0.006), bp(noise(0.03), 3000, 8000) * env(int(SR * 0.03), 0.0002, 0.003) * 0.4), 0.35)
    arp = mix(*[np.concatenate([np.zeros(int(SR * k * 0.09)), np.sin(2 * np.pi * f * t(0.6)) * env(int(SR * 0.6), 0.002, 0.25)]) for k, f in enumerate([523, 659, 784, 1046])])
    save('success', reverb(arp, 0.8, 0.4, 0.3), 0.5)
    arp = mix(*[np.concatenate([np.zeros(int(SR * k * 0.12)), np.sin(2 * np.pi * f * t(0.5)) * env(int(SR * 0.5), 0.002, 0.2)]) for k, f in enumerate([440, 349, 262])])
    save('fail', arp, 0.5)
    save('beep', np.sin(2 * np.pi * 1000 * t(0.15)) * env(int(SR * 0.15), 0.002, 0.05), 0.4)
    save('beep_go', np.sin(2 * np.pi * 1500 * t(0.5)) * env(int(SR * 0.5), 0.002, 0.2), 0.5)
    # upgrade charge (rising)
    d = 2.2; tt = t(d)
    f = 200 + 1400 * (tt / d) ** 2
    x = (np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5 + bp(noise(d), 500, 5000) * 0.2 * (tt / d)) * np.minimum(tt / 0.2, 1)
    save('upgrade_charge', x, 0.5)
    # ambience loops (10s, seamless via crossfade)
    def loop(x, cf=1.0):
        n = int(SR * cf)
        a = x[:n] * np.linspace(0, 1, n); b = x[-n:] * np.linspace(1, 0, n)
        return np.concatenate([x[n:-n], a + b])
    L = 14
    city = lp(noise(L), 500) * 0.3 + lp(bp(noise(L), 200, 1200), 800) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.07 * t(L)))[: int(SR * L)] * 0.2
    for k in range(8):  # birds chirps
        s = int(rng.random() * (L - 1) * SR)
        ch = np.sin(2 * np.pi * np.cumsum(3000 + 1500 * np.sin(2 * np.pi * 18 * t(0.25))) / SR) * env(int(SR * 0.25), 0.01, 0.06) * 0.15
        city[s:s + len(ch)] += ch
    save('amb_city', loop(city), 0.35)
    sea = lp(noise(L), 700) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.12 * t(L))) + lp(noise(L), 150) * 0.5
    save('amb_sea', loop(sea), 0.4)
    wind = bp(noise(L), 200, 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.05 * t(L) + 1)) + lp(noise(L), 120) * 0.4
    save('amb_wind', loop(wind), 0.35)
    # menu music: dark synth pad + soft beat (16s loop, 100 bpm)
    L = 19.2; tt = t(L)
    chords = [(110, 130.8, 164.8), (87.3, 110, 130.8), (98, 123.5, 146.8), (82.4, 98, 123.5)]
    music = np.zeros(int(SR * L))
    seg = int(SR * L / 4)
    for i, ch in enumerate(chords):
        tt2 = t(L / 4)
        s = sum(np.sin(2 * np.pi * f * tt2) + 0.5 * np.sin(2 * np.pi * f * 2.003 * tt2) + 0.3 * np.sign(np.sin(2 * np.pi * f * 0.5 * tt2)) * 0.2 for f in ch)
        e = np.minimum(tt2 / 0.6, 1) * np.minimum((L / 4 - tt2) / 0.6, 1)
        music[i * seg:i * seg + len(s)] += lp(s, 1200) * e * 0.25
    beat = 60 / 100
    for k in range(int(L / beat)):
        s = int(k * beat * SR)
        kick = sweep(160, 45, 0.3, 18) * env(int(SR * 0.3), 0.001, 0.08)
        music[s:s + len(kick)] += kick * 0.8
        if k % 2 == 1:
            hh = hp(noise(0.05), 7000) * env(int(SR * 0.05), 0.0005, 0.01) * 0.25
            music[s:s + len(hh)] += hh
            sn = bp(noise(0.2), 800, 5000) * env(int(SR * 0.2), 0.001, 0.05) * 0.3
            if k % 4 == 3:
                music[s:s + len(sn)] += sn
        o = int((k + 0.5) * beat * SR)
        hh = hp(noise(0.04), 8000) * env(int(SR * 0.04), 0.0005, 0.006) * 0.15
        music[o:o + len(hh)] += hh
    arp_notes = [440, 523, 659, 523, 392, 523, 587, 494]
    for k in range(int(L / (beat / 2))):
        s = int(k * beat / 2 * SR)
        f = arp_notes[k % 8] * (0.5 if (k // 16) % 2 else 1)
        n_ = np.sin(2 * np.pi * f * t(0.25)) * env(int(SR * 0.25), 0.002, 0.07) * 0.08
        music[s:s + len(n_)] += n_[: max(0, min(len(n_), len(music) - s))]
    music = reverb(music, 1.2, 0.8, 0.25, 4000)[: int(SR * L)]
    pass  # menu music now comes from tools/gen_music.py
    print('sfx done', len(os.listdir(OUT)))


build()
