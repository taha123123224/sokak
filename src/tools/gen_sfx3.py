"""Weapon sounds from real CC0 recordings (The Free Firearm Sound Library + CC0 reload packs, via OpenGameArt;
see assets/sfx_src/CREDITS.md), layered with a punchy sub thump, a mechanical click and an outdoor slap-back tail.
Writes assets/sfx/shot_*.wav (+ _v1/_v2 variants), shot_far*.wav and foley (mag, bolt, pump, equip...)."""
import os, numpy as np
from scipy.io import wavfile
from scipy.signal import resample, butter, sosfilt, fftconvolve

SR = 44100
SRC = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx_src')
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
rng = np.random.default_rng(7)


def load(n):
    sr, d = wavfile.read(os.path.join(SRC, n + '.wav'))
    d = d.astype(np.float32) / 32768.0
    if d.ndim > 1:
        d = d.mean(axis=1)
    return d


def pitch(x, f):
    if abs(f - 1.0) < 1e-3:
        return x
    return resample(x, int(len(x) / f)).astype(np.float32)


def filt(x, kind, fc, order=2):
    sos = butter(order, fc, kind, fs=SR, output='sos')
    return sosfilt(sos, x).astype(np.float32)


def thump(freq, dur, amp):
    t = np.arange(int(dur * SR)) / SR
    f = freq * (1 + 1.5 * np.exp(-t * 40))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) * np.exp(-t * 18) * amp).astype(np.float32)


def click(amp=0.4):
    n = int(0.006 * SR)
    return (filt(rng.standard_normal(n).astype(np.float32), 'highpass', 3000) * np.exp(-np.arange(n) / (n / 5)) * amp).astype(np.float32)


def tail_ir(dur=1.1, decay=0.32, slap=0.16):
    n = int(dur * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal(n).astype(np.float32) * np.exp(-t / decay)
    ir = filt(ir, 'lowpass', 2600)
    k = int(slap * SR)
    ir[k:k + 400] += np.hanning(400).astype(np.float32) * 3.0       # building slap-back
    ir[:200] = 0
    return ir / np.abs(ir).max()


IR = tail_ir()
IR_BIG = tail_ir(1.8, 0.55, 0.24)


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n, np.float32)
    for p in parts:
        out[:len(p)] += p
    return out


def master(x, peak=0.95, drive=1.4):
    x = x - np.mean(x)
    x = np.tanh(x * drive) / np.tanh(drive)
    x = x / (np.abs(x).max() + 1e-9) * peak
    fade = int(0.02 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def save(name, x):
    wavfile.write(os.path.join(OUT, name + '.wav'), SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))


def gun(name, srcs, pf=1.0, sub=(55, 0.12, 0.5), crack=0.0, wet=0.22, big=False, trim=0.7, hp=60):
    for vi, sname in enumerate(srcs):
        d = pitch(load(sname), pf * (1 + (vi - 1) * 0.015))
        d = d[:int(trim * SR)]
        d = filt(d, 'highpass', hp)
        body = d.copy()
        if crack > 0:
            body = body + filt(d, 'highpass', 2500) * crack
        dry = mix(body, thump(*sub), click(0.25))
        wetsig = fftconvolve(dry, IR_BIG if big else IR)[:len(dry) + len(IR)] * wet * 0.06
        x = master(mix(dry, wetsig.astype(np.float32)))
        save(name if vi == 0 else f'{name}_v{vi}', x)
        if vi == 0:
            # distant version: low-passed, mostly tail
            far = filt(dry, 'lowpass', 900) * 0.6
            fw = fftconvolve(far, IR_BIG)[:len(far) + len(IR_BIG)] * 0.09
            save(name.replace('shot_', 'shotfar_'), master(mix(far, fw.astype(np.float32)), 0.7, 1.1))


AK = ['shot-1', 'shot-2', 'shot-3']
gun('shot_ak', AK, 1.0, (52, 0.13, 0.55), 0.15)
gun('shot_m4', AK, 1.08, (60, 0.1, 0.4), 0.35)
gun('shot_scar', ['marksman-1', 'marksman-2', 'marksman-3'], 0.94, (46, 0.16, 0.65), 0.1, big=True)
gun('shot_smg', ['smg-1', 'smg-2', 'smg-3'], 1.0, (70, 0.08, 0.35), 0.2, trim=0.42)
gun('shot_ump', ['smg-1', 'smg-2', 'smg-3'], 0.93, (62, 0.09, 0.42), 0.1, trim=0.42)
gun('shot_p90', ['smg-2', 'smg-3', 'smg-1'], 1.1, (75, 0.07, 0.3), 0.4, trim=0.38)
gun('shot_pistol', ['pistol-1', 'pistol-2', 'pistol-3'], 1.0, (80, 0.07, 0.35), 0.25, trim=0.42)
gun('shot_deagle', ['marksman-1', 'marksman-2', 'marksman-3'], 1.12, (58, 0.12, 0.6), 0.3, trim=0.6)
gun('shot_revolver', ['marksman-2', 'marksman-3', 'marksman-1'], 1.04, (52, 0.13, 0.65), 0.2, trim=0.65)
gun('shot_shotgun', ['shotgun-1', 'shotgun-2', 'shotgun-1'], 1.0, (42, 0.18, 0.7), 0.0, big=True, trim=0.85)
gun('shot_sniper', ['marksman-1', 'marksman-2', 'marksman-3'], 0.86, (40, 0.22, 0.8), 0.25, wet=0.35, big=True, trim=0.75)
gun('shot_kar', ['chimney-1', 'chimney-2', 'chimney-1'], 0.95, (42, 0.2, 0.7), 0.15, wet=0.35, big=True, trim=0.8)
# generic distant shots used by far-away bots
save('shot_far', master(filt(load('shot-1'), 'lowpass', 800) * 0.6, 0.6, 1.0))
save('shot_far_heavy', master(filt(load('marksman-1'), 'lowpass', 700) * 0.6, 0.65, 1.0))

# ---- foley
rel = load('reload')
save('mag_out', master(filt(rel[:int(0.55 * SR)], 'highpass', 150), 0.8, 1.2))
save('mag_in', master(filt(rel[int(0.8 * SR):], 'highpass', 150), 0.85, 1.3))
pr = load('reloadPistol')
save('mag_out_p', master(filt(pr[:int(0.9 * SR)], 'highpass', 150), 0.75, 1.2))
save('mag_in_p', master(filt(pr[int(1.15 * SR):], 'highpass', 150), 0.8, 1.2))
pm = load('pump')
save('pump', master(pm, 0.85, 1.3))
save('bolt_back', master(pitch(pm[:int(0.16 * SR)], 1.15), 0.75, 1.2))
save('bolt_fwd', master(pitch(pm[int(0.14 * SR):], 1.12), 0.8, 1.2))
save('shell_in', master(load('shell-1'), 0.75, 1.1))
sw = load('swap')
save('equip', master(sw, 0.7, 1.2))
save('equip_pistol', master(pitch(sw, 1.18), 0.65, 1.2))
save('equip_heavy', master(mix(pitch(sw, 0.88), thump(90, 0.06, 0.15)), 0.75, 1.2))
save('dryfire', master(pitch(sw[:int(0.06 * SR)], 1.6), 0.5, 1.0))
print('ok')

# suppressed shot: real AK take, heavily low-passed with a sharp mechanical action click on top
d = filt(load('shot-2')[:int(0.4 * SR)], 'lowpass', 1100) * 0.55
act = pitch(load('pump')[:int(0.09 * SR)], 1.5) * 0.35
save('shot_sup', master(mix(d, thump(95, 0.05, 0.25), act, click(0.35)), 0.8, 1.6))
print('sup ok')
