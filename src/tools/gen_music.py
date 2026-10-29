"""Original game music for SOKAK, synthesized from scratch (numpy):
Turkish 'Hicaz' makam melodies on a Karplus-Strong saz, darbuka + trap drums, sub bass, wide pads.
Outputs (44.1 kHz stereo WAV): music_menu, music_match, music_win, music_lose
"""
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'sfx')
rng = np.random.default_rng(7)

# D Hicaz: D Eb F# G A Bb C  (semitones from D)
HICAZ = [0, 1, 4, 5, 7, 8, 10]
D3 = 146.83


def hz(deg, octv=0, base=D3):
    o, d = divmod(deg, 7)
    return base * 2 ** ((HICAZ[d] + 12 * (o + octv)) / 12)


def lp(x, f, o=2):
    return sosfilt(butter(o, min(f, SR / 2 - 100) / (SR / 2), 'low', output='sos'), x)


def hp(x, f, o=2):
    return sosfilt(butter(o, f / (SR / 2), 'high', output='sos'), x)


def bp(x, lo, hi, o=2):
    return sosfilt(butter(o, [lo / (SR / 2), hi / (SR / 2)], 'band', output='sos'), x)


def env(n, a, d, s=0.0, r=None):
    t = np.arange(n) / SR
    e = np.minimum(t / max(a, 1e-4), 1.0)
    e *= s + (1 - s) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4))
    if r:
        rl = int(r * SR)
        if rl < n:
            e[-rl:] *= np.linspace(1, 0, rl)
    return e


def saz(f, dur, bright=0.5):
    """Karplus-Strong plucked string with a metallic buzz like a bağlama."""
    n = int(dur * SR)
    p = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, p)
    buf = lp(buf, 2000 + bright * 6000) if p > 16 else buf
    out = np.zeros(n)
    idx = 0
    damp = 0.996
    for i in range(n):
        v = buf[idx]
        nxt = buf[(idx + 1) % p]
        buf[idx] = damp * 0.5 * (v + nxt)
        out[i] = v
        idx = (idx + 1) % p
    # second course slightly detuned (doubled strings)
    return out * env(n, 0.002, dur * 0.6, 0.0, 0.05)


def saz_fast(f, dur, bright=0.5):
    # vectorised approximation for long passages: decaying harmonic series + pluck noise
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for k in range(1, 12):
        a = (1.0 / k) * np.exp(-t * (1.5 + k * (1.2 - bright * 0.6)))
        y += a * np.sin(2 * np.pi * f * k * t * (1 + 0.0008 * k) + rng.uniform(0, 6.28))
        y += a * 0.6 * np.sin(2 * np.pi * f * 1.003 * k * t)
    y += bp(rng.standard_normal(n), 1500, 6000) * np.exp(-t * 60) * 0.3
    return y * env(n, 0.002, dur, 0.0, 0.04)


def pad(freqs, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for f in freqs:
        for det in (-0.12, 0.0, 0.11):
            ph = rng.uniform(0, 1)
            y += 2 * (((f * 2 ** (det / 12)) * t + ph) % 1.0) - 1
    y = lp(y, 1800) * env(n, dur * 0.3, 10, 1.0, dur * 0.35)
    return y / (len(freqs) * 3)


def sub(f, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * f * t) + 0.35 * np.tanh(3 * np.sin(2 * np.pi * f * t))
    return y * env(n, 0.005, dur * 0.8, 0.6, 0.05)


def kick(n=int(0.5 * SR)):
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t * 32)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.tanh(2.2 * np.sin(ph) * np.exp(-t * 7)) + lp(rng.standard_normal(n), 3000) * np.exp(-t * 120) * 0.3


def snare(n=int(0.35 * SR)):
    t = np.arange(n) / SR
    return bp(rng.standard_normal(n), 1200, 8000) * np.exp(-t * 18) * 0.8 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 30) * 0.5


def clap(n=int(0.3 * SR)):
    t = np.arange(n) / SR
    e = np.zeros(n)
    for o in (0, 0.011, 0.022):
        e += np.exp(-np.maximum(t - o, 0) * 60) * (t >= o)
    e += np.exp(-t * 14) * 0.4
    return bp(rng.standard_normal(n), 900, 5000) * e * 0.7


def hat(n=int(0.07 * SR), open_=False):
    t = np.arange(n if not open_ else int(0.3 * SR)) / SR
    return hp(rng.standard_normal(len(t)), 7000) * np.exp(-t * (60 if not open_ else 12)) * 0.35


def doum(n=int(0.45 * SR)):
    t = np.arange(n) / SR
    f = 80 + 40 * np.exp(-t * 20)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 0.9


def tek(n=int(0.15 * SR)):
    t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 820 * t) * 0.5 + bp(rng.standard_normal(n), 2000, 7000) * 0.6) * np.exp(-t * 45)


def place(track, x, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    if i >= track.shape[1]:
        return
    x = x[: track.shape[1] - i]
    l = np.cos((pan + 1) * np.pi / 4) * 1.41
    r = np.sin((pan + 1) * np.pi / 4) * 1.41
    track[0, i:i + len(x)] += x * gain * l
    track[1, i:i + len(x)] += x * gain * r


def reverb(st, wet=0.25, size=1.0):
    out = st.copy()
    for ch in range(2):
        acc = np.zeros(st.shape[1])
        for k, (dly, g) in enumerate([(0.029, 0.5), (0.037, 0.45), (0.041, 0.42), (0.053, 0.38), (0.067, 0.33), (0.079, 0.3)]):
            d = int(dly * size * SR * (1.0 + 0.07 * ch))
            y = np.zeros(st.shape[1])
            y[d:] = st[ch, :-d]
            # simple feedback comb via repeated echoes
            fb = y.copy()
            for m in range(1, 6):
                s = d * m
                if s >= len(fb):
                    break
                fb[s:] += y[:-s] * (g ** m)
            acc += fb
        out[ch] += lp(acc, 5000) * wet / 6
    return out


def master(st, name, gain=0.9):
    st = st - st.mean(axis=1, keepdims=True)
    st = np.tanh(st * 1.3) / np.tanh(1.3)
    pk = np.abs(st).max() + 1e-9
    st = st / pk * gain
    wavfile.write(os.path.join(OUT, name + '.wav'), SR, (st.T * 32767).astype(np.int16))
    print('music', name, round(st.shape[1] / SR, 1), 's')


# chord progression (scale degree roots) – i  bII  VII  i  (D  Eb  C  D) with F# major colour
PROG = [(0, [0, 4, 7]), (1, [1, 5, 8]), (6, [-2, 2, 5]), (0, [0, 4, 7])]
MELODY_A = [(0, 4, 0.5), (0, 3, 0.25), (0, 2, 0.25), (0, 1, 1.0), (0, 2, 0.5), (0, 3, 0.5), (0, 4, 1.0), (0, 5, 0.5), (0, 4, 0.5),
            (0, 3, 0.5), (0, 2, 0.5), (0, 1, 0.5), (0, 0, 1.5)]
MELODY_B = [(1, 0, 0.5), (0, 6, 0.25), (0, 5, 0.25), (0, 4, 0.5), (0, 5, 0.5), (0, 6, 0.75), (1, 0, 0.25), (0, 6, 0.5), (0, 5, 0.5),
            (0, 4, 1.0), (0, 3, 0.5), (0, 2, 0.5), (0, 1, 0.5), (0, 2, 0.5), (0, 0, 1.0)]


def song(name, bpm, bars, intensity=1.0, lead=True, gain=0.85):
    beat = 60.0 / bpm
    bar = beat * 4
    dur = bars * bar + 2.0
    tr = np.zeros((2, int(dur * SR)))
    for b in range(bars):
        t0 = b * bar
        root, chord = PROG[b % 4]
        sec = (b // 4) % 4      # song section: 0 intro, 1 groove, 2 lead, 3 lead+full
        if b >= bars - 1:
            sec = 0
        place(tr, pad([hz(c, -1) for c in chord], bar + 0.4), t0, 0.32 * intensity, 0.0)
        if sec >= 1:
            for k in range(8):   # syncopated sub bass
                if k in (0, 3, 6) or (k == 7 and b % 2):
                    place(tr, sub(hz(root, -2), beat * 0.45), t0 + k * beat * 0.5, 0.55 * intensity)
            # drums
            for k in range(4):
                if k in (0,) or (k == 2 and b % 2 == 0):
                    place(tr, kick(), t0 + k * beat, 0.8 * intensity)
                if k in (1, 3):
                    place(tr, clap(), t0 + k * beat, 0.45 * intensity, 0.1)
                    place(tr, snare(), t0 + k * beat, 0.25 * intensity, -0.1)
            place(tr, kick(), t0 + 2.75 * beat, 0.55 * intensity)
            for k in range(16):  # trap hats with rolls
                sw = 0.02 if k % 2 else 0.0
                g = 0.35 if k % 4 == 0 else 0.22
                place(tr, hat(), t0 + k * beat * 0.25 + sw, g * intensity, 0.35)
                if b % 4 == 3 and k >= 12:
                    place(tr, hat(), t0 + k * beat * 0.25 + beat * 0.125, 0.18 * intensity, 0.35)
        # darbuka (maqsum-ish): D T - T D - T -
        for k, typ in enumerate(['D', 'T', '', 'T', 'D', '', 'T', '']):
            if typ == 'D':
                place(tr, doum(), t0 + k * beat * 0.5, 0.55 * intensity, -0.3)
            elif typ == 'T':
                place(tr, tek(), t0 + k * beat * 0.5, 0.4 * intensity, -0.35)
        # saz ostinato (arpeggio on chord tones)
        for k in range(8):
            deg = chord[[0, 1, 2, 1, 0, 2, 1, 2][k]]
            place(tr, saz_fast(hz(deg, 0), beat * 0.6, 0.4), t0 + k * beat * 0.5, 0.18 * intensity, 0.45)
    # lead melody (saz, octave up) in sections 2-3
    if lead:
        for b in range(0, bars - 1, 4):
            if (b // 4) % 4 < 2:
                continue
            mel = MELODY_A if (b // 4) % 2 == 0 else MELODY_B
            t = b * bar
            for (o, d, ln) in mel:
                place(tr, saz_fast(hz(d, 1 + o), ln * beat + 0.3, 0.7), t, 0.42 * intensity, -0.15)
                t += ln * beat
    tr = reverb(tr, 0.35, 1.2)
    # seamless loop: fold the ringing tail (notes/reverb past the last bar) back onto the start
    # and cut at exactly bars*bar, so the loop point has no gap, click or fade
    L = int(round(bars * bar * SR))
    tail = tr[:, L:]
    out = tr[:, :L].copy()
    out[:, :tail.shape[1]] += tail
    master(out, name, gain)


def stinger(name, win=True):
    dur = 4.0
    tr = np.zeros((2, int(dur * SR)))
    if win:
        notes = [0, 2, 4, 7]
        for i, d in enumerate(notes):
            place(tr, saz_fast(hz(d, 1), 2.5, 0.8), i * 0.14, 0.5, -0.2 + i * 0.13)
        place(tr, pad([hz(0, -1), hz(4, -1), hz(7, -1), hz(0, 0)], 3.6), 0.4, 0.6)
        place(tr, kick(), 0.56, 0.9)
        place(tr, clap(), 0.56, 0.6)
    else:
        for i, d in enumerate([4, 3, 1, 0]):
            place(tr, saz_fast(hz(d, 0), 2.2, 0.3), i * 0.3, 0.45, 0.1)
        place(tr, pad([hz(0, -1), hz(1, -1), hz(5, -1)], 3.6), 0.2, 0.5)
        place(tr, doum(), 1.2, 0.8)
    tr = reverb(tr, 0.45, 1.5)
    tr[:, -int(1.0 * SR):] *= np.linspace(1, 0, int(1.0 * SR))
    master(tr, name, 0.8)


if __name__ == '__main__':
    song('music_menu', 96, 32, 1.0, True, 0.82)
    song('music_match', 104, 16, 0.75, False, 0.6)
    stinger('music_win', True)
    stinger('music_lose', False)
