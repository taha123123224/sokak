"""SOKAK main theme v2 (original): cinematic orchestral-trap hybrid in D Hicaz.
Intro (strings drone, taiko hits, riser) -> drop (808 + glide sub, half-time snare, rolling hats,
16th string ostinato, brass stabs, saz hook) -> breakdown (choir pad) -> final drop -> outro.
Writes assets/sfx/music_menu.wav (and a lighter music_match.wav)."""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import gen_music as G
from gen_music import SR, place, reverb, master, lp, hp, bp, env, hz, saz, saz_fast

rng = np.random.default_rng(11)
BPM = 140
BEAT = 60 / BPM
BAR = BEAT * 4


def saw(f, n, det=0.0):
    t = np.arange(n) / SR
    ph = (t * f * (1 + det)) % 1.0
    return 2 * ph - 1


def supersaw(f, dur, voices=7, spread=0.012):
    n = int(dur * SR)
    out = np.zeros(n)
    for k in range(voices):
        d = (k - voices // 2) / (voices // 2) * spread
        out += saw(f, n, d) * (1.0 if k == voices // 2 else 0.6)
    return out / voices


def strings(freqs, dur, bright=1800, att=0.25):
    n = int(dur * SR)
    x = sum(supersaw(f, dur, 5, 0.006) for f in freqs) / len(freqs)
    t = np.arange(n) / SR
    vib = 1 + 0.003 * np.sin(2 * np.pi * 5.2 * t)
    x = lp(x * vib, bright, 2)
    return x * env(n, att, 9e9, 1.0, min(0.6, dur * 0.4))


def ost_note(f, dur):
    n = int(dur * SR)
    x = lp(supersaw(f, dur, 3, 0.004), 2600, 2)
    return x * env(n, 0.004, dur * 0.6, 0.25, 0.03)


def brass(freqs, dur):
    n = int(dur * SR)
    x = sum(supersaw(f, dur, 5, 0.008) for f in freqs) / len(freqs)
    e = env(n, 0.02, 0.35, 0.45, 0.12)
    cut = 600 + 3200 * env(n, 0.01, 0.25, 0.2)
    # time-varying lowpass approximation: blend two filtered copies
    a = lp(x, 900, 2); b = lp(x, 3800, 2)
    k = (cut - 600) / 3200
    return (a * (1 - k) + b * k) * e * 1.4


def k808(f=55.0, dur=0.9, glide_to=None):
    n = int(dur * SR)
    t = np.arange(n) / SR
    fr = f * (1 + 2.5 * np.exp(-t * 40))
    if glide_to:
        fr *= np.interp(t, [0, dur * 0.5, dur], [1, 1, glide_to / f])
    ph = 2 * np.pi * np.cumsum(fr) / SR
    x = np.sin(ph) + 0.25 * np.sin(2 * ph)
    x = np.tanh(x * 2.2) * env(n, 0.002, dur * 0.8, 0.0, 0.05)
    return x


def kick():
    n = int(0.35 * SR); t = np.arange(n) / SR
    ph = 2 * np.pi * np.cumsum(48 * (1 + 4 * np.exp(-t * 55))) / SR
    click = hp(rng.standard_normal(n), 3000) * np.exp(-t * 300) * 0.4
    return np.tanh((np.sin(ph) * np.exp(-t * 9) + click) * 1.6)


def snare():
    n = int(0.6 * SR); t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 22)
    noise = bp(rng.standard_normal(n), 1200, 9000) * np.exp(-t * 9)
    return np.tanh((body * 0.8 + noise * 0.9) * 1.4)


def hat(open_=False):
    n = int((0.25 if open_ else 0.05) * SR); t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7000, 4) * np.exp(-t * (14 if open_ else 90)) * 0.5


def taiko():
    n = int(1.2 * SR); t = np.arange(n) / SR
    ph = 2 * np.pi * np.cumsum(70 * (1 + 0.6 * np.exp(-t * 12))) / SR
    skin = lp(rng.standard_normal(n), 900) * np.exp(-t * 18)
    return np.tanh((np.sin(ph) * np.exp(-t * 4.5) * 1.2 + skin * 0.6) * 1.3)


def riser(dur):
    n = int(dur * SR); t = np.arange(n) / SR
    x = rng.standard_normal(n)
    out = np.zeros(n)
    seg = 2048
    for i in range(0, n, seg):
        f = 300 + 9000 * (i / n) ** 2
        out[i:i + seg] = bp(x[i:i + seg], f * 0.7, min(f * 1.3, 20000))
    return out * (t / dur) ** 2 * 0.6


def choir(freqs, dur):
    n = int(dur * SR)
    src = sum(supersaw(f, dur, 5, 0.01) for f in freqs) / len(freqs)
    vowel = bp(src, 500, 900) * 1.2 + bp(src, 1000, 1400) * 0.7 + bp(src, 2400, 2900) * 0.3
    return vowel * env(n, 0.8, 9e9, 1.0, 0.8)


# progression: i - bII - VII - i  /  i - bVI - VII - V(Hicaz major)   (scale degrees in D Hicaz)
CH_A = [[0, 2, 4], [1, 3, 5], [-1, 1, 3], [0, 2, 4]]
CH_B = [[0, 2, 4], [5, 7, 9], [6, 8, 10], [4, 6, 8]]
HOOK = [(4, 0.75), (3, 0.25), (2, 0.5), (1, 0.5), (2, 1.0), (4, 0.5), (5, 0.5), (4, 0.75), (3, 0.25), (2, 0.5), (1, 0.5), (0, 2.0),
        (7, 0.75), (6, 0.25), (5, 0.5), (4, 0.5), (5, 1.0), (4, 0.5), (3, 0.5), (2, 0.5), (1, 0.5), (2, 0.5), (1, 0.5), (0, 2.0)]


def section_drop(tr, start_bar, bars, lead=True, energy=1.0, chords=CH_A):
    for b in range(bars):
        t0 = (start_bar + b) * BAR
        ch = chords[b % 4]
        root = hz(ch[0], -2)
        # drums: half-time (kick 1 + and-of-2, snare on 3)
        place(tr, kick(), t0, 0.95 * energy)
        place(tr, kick(), t0 + BEAT * 1.5, 0.7 * energy)
        if b % 2 == 1:
            place(tr, kick(), t0 + BEAT * 3.5, 0.55 * energy)
        place(tr, snare(), t0 + BEAT * 2, 0.75 * energy, 0.05)
        for i in range(16):
            roll = (b % 4 == 3 and i >= 12)
            if roll:
                for j in range(3):
                    place(tr, hat(), t0 + (i + j / 3) * BEAT / 4, 0.25, 0.3)
            else:
                place(tr, hat(i % 8 == 6), t0 + i * BEAT / 4, 0.32 if i % 2 == 0 else 0.18, 0.3)
        # 808 with glide into the next chord
        nxt = hz(chords[(b + 1) % 4][0], -2)
        place(tr, k808(root, BAR * 0.95, nxt if b % 4 == 3 else None), t0, 0.8 * energy)
        # string ostinato (16ths)
        pat = [0, 2, 4, 2, 7, 4, 2, 4, 0, 2, 4, 2, 7, 4, 5, 4]
        for i, d in enumerate(pat):
            place(tr, ost_note(hz(ch[0] + d, 0) / 2, BEAT / 4 * 0.95), t0 + i * BEAT / 4, 0.16, -0.35 + 0.7 * (i % 2))
        # long strings bed
        place(tr, strings([hz(c, -1) for c in ch], BAR, 1600, 0.05), t0, 0.32, 0.0)
        # brass stabs on 1 and the and-of-2
        if energy > 0.8:
            place(tr, brass([hz(c, -1) for c in ch], BEAT * 0.9), t0, 0.35)
            place(tr, brass([hz(c, -1) for c in ch], BEAT * 0.6), t0 + BEAT * 1.5, 0.25)
    if lead:
        t = start_bar * BAR
        for rep in range(bars // 8):
            tt = t + rep * 8 * BAR
            for (d, l) in HOOK:
                place(tr, saz(hz(d, 1), l * BEAT + 0.4, 0.75), tt, 0.42, 0.15)
                place(tr, saz_fast(hz(d, 0), l * BEAT + 0.3, 0.5), tt + 0.012, 0.2, -0.2)
                tt += l * BEAT


def build(name, total_gain=0.86, light=False):
    bars_intro, bars_d1, bars_br, bars_d2, bars_out = 4, 16, 8, 16, 2
    total = bars_intro + bars_d1 + bars_br + bars_d2 + bars_out
    tr = np.zeros((2, int((total * BAR + 3) * SR)))
    # intro: drone + taikos + riser
    place(tr, strings([hz(0, -2), hz(4, -2), hz(0, -1)], bars_intro * BAR, 900, 1.5), 0, 0.5)
    for b in range(bars_intro):
        place(tr, taiko(), b * BAR, 0.7)
        place(tr, taiko(), b * BAR + BEAT * 2.5, 0.45, -0.3)
    place(tr, riser(BAR * 2), (bars_intro - 2) * BAR, 0.6)
    s = bars_intro
    section_drop(tr, s, bars_d1, lead=not light, energy=0.75 if light else 1.0)
    s += bars_d1
    # breakdown: choir + saz solo + filtered pulse
    for b in range(bars_br):
        t0 = (s + b) * BAR
        ch = CH_B[b % 4]
        place(tr, choir([hz(c, -1) for c in ch], BAR + 0.5), t0, 0.5)
        place(tr, taiko(), t0, 0.4)
        for i in range(8):
            place(tr, saz_fast(hz(ch[0] + [0, 2, 4, 7][i % 4], 0), BEAT / 2 + 0.2, 0.4), t0 + i * BEAT / 2, 0.28, 0.25 * (-1) ** i)
    place(tr, riser(BAR * 2), (s + bars_br - 2) * BAR, 0.7)
    s += bars_br
    section_drop(tr, s, bars_d2, lead=not light, energy=0.8 if light else 1.0, chords=CH_B)
    s += bars_d2
    place(tr, taiko(), s * BAR, 0.8)
    place(tr, strings([hz(0, -2), hz(4, -2), hz(0, -1)], bars_out * BAR + 2, 1200, 0.02), s * BAR, 0.45)
    tr = reverb(tr, 0.28, 1.4)
    fade = int(2.5 * SR)
    tr[:, -fade:] *= np.linspace(1, 0, fade)
    master(tr, name, total_gain)


if __name__ == '__main__':
    build('music_menu', 0.86)
    if '--match' in sys.argv:
        build('music_match', 0.6, light=True)
