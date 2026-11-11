"""v3.0: weapon shots straight from the CC0 Free Firearm Sound Library (mirror: github.com/buddingmonkey/
FreeFirearmsSFXLibrary). Every take is a real outdoor recording; we only slice single shots, high-pass the
rumble, tame peaks with a soft limiter and loudness-match. No synthetic layers.
python3 -I tools/build_guns.py"""
import numpy as np, os, shutil
from scipy.io import wavfile
from scipy.signal import butter, sosfilt, resample_poly
SRC = "/home/claude/ext_audio/ffl/Prepared SFX/"
OUT = "/home/claude/sokak/assets/sfx/"
BAK = "/home/claude/old_assets/sfx_synth/guns_v299/"
os.makedirs(BAK, exist_ok=True)
SR = 44100

def load(p):
    sr, x = wavfile.read(SRC + p)
    x = x.astype(np.float32)
    if x.dtype != np.float32 or np.abs(x).max() > 2: x /= 2 ** 31 if np.abs(x).max() > 70000 else 32768.0
    if x.ndim > 1: x = x.mean(axis=1)
    x = resample_poly(x, 147, 320) if sr == 96000 else x
    return x / (np.abs(x).max() + 1e-9)

def shots(x, gap=0.35, thr=0.35):
    env = np.abs(x)
    i, out = 0, []
    while i < len(env):
        if env[i] > thr:
            s = max(i - int(0.004 * SR), 0)
            out.append(s)
            i += int(gap * SR)
        else:
            i += 1
    return out

def hp(x, f, o=2):
    return sosfilt(butter(o, f, 'highpass', fs=SR, output='sos'), x)

def lp(x, f, o=2):
    return sosfilt(butter(o, f, 'lowpass', fs=SR, output='sos'), x)

def finish(x, dur, peak=0.93, pitch=1.0, hpf=45, bright=0.0):
    if pitch != 1.0:
        up = int(round(100 / pitch)); x = resample_poly(x, up, 100)
    x = x[:int(dur * SR)].copy()
    x = hp(x, hpf)
    if bright > 0: x = x + hp(x, 3000) * bright
    x = x / (np.abs(x).max() + 1e-9) * 1.8
    # soft limiter: knee at 0.5, keeps the transient punch without hard clipping
    a = np.abs(x); k = 0.5
    g = np.where(a > k, (k + (a - k) / (1 + (a - k) / (1 - k))) / (a + 1e-9), 1.0)
    x = x * g
    n = len(x); f = np.ones(n, np.float32)
    ft = int(min(0.35, dur * 0.45) * SR); f[-ft:] = np.linspace(1, 0, ft) ** 2
    x = x * f
    return (x / (np.abs(x).max() + 1e-9) * peak).astype(np.float32)

def save(name, x):
    p = OUT + name + ".wav"
    if os.path.exists(p) and not os.path.exists(BAK + name + ".wav"): shutil.copy(p, BAK + name + ".wav")
    wavfile.write(p, SR, (np.clip(x, -1, 1) * 32767).astype(np.int16))

def gun(name, src, dur, pitch=1.0, far=None, far_dur=None, bright=0.0, peak=0.93):
    x = load(src)
    st = shots(x)
    takes = [x[s:s + int(dur * 1.2 * SR)] for s in st if s + int(0.2 * SR) < len(x)]
    # prefer the cleanest takes (peak ratio = least clipped / most consistent)
    takes = sorted(takes, key=lambda t: -np.sqrt(np.mean(t[:int(0.05 * SR)] ** 2)))[:3]
    while len(takes) < 3: takes.append(takes[0])
    for vi, t in enumerate(takes):
        save(name if vi == 0 else f"{name}_v{vi}", finish(t, dur, peak, pitch * (1 + (vi - 1) * 0.012), bright=bright))
    fn = name.replace("shot_", "shotfar_")
    if far:
        y = load(far); s = shots(y)[0]
        save(fn, finish(lp(y[s:s + int((far_dur or dur * 1.6) * SR)], 2600), far_dur or dur * 1.6, 0.7, pitch))
    else:
        save(fn, finish(lp(takes[0], 1400), dur * 1.4, 0.6, pitch))
    print(name, len(st), "shots found")

gun("shot_ak", "AK-47/C_28P.wav", 0.75, far="AK-47/C_31P.wav", far_dur=1.2)
gun("shot_m4", "AR-15/D_32P.wav", 0.7, far="AR-15/D_24P.wav", far_dur=1.2, bright=0.1)
gun("shot_scar", "Savage 10 .300 Blackout/T_27P.wav", 0.85, pitch=0.97)
gun("shot_smg", "Carl Gustav M45/G_31P.wav", 0.5)
gun("shot_ump", "Carl Gustav M45/G_31P.wav", 0.5, pitch=0.94)
gun("shot_p90", "PPSh/P_30P.wav", 0.42, pitch=1.08)
gun("shot_pistol", "Walther PPQ/X_39P.wav", 0.55)
gun("shot_deagle", "1911/A_42P.wav", 0.75, pitch=0.9)
gun("shot_revolver", "Smith & Wesson 642/V_27P.wav", 0.75, pitch=0.92)
gun("shot_shotgun", "Nova/O_21P.wav", 1.0)
gun("shot_sniper", "Tikka/W_29P.wav", 1.4, far="Tikka/W_24P.wav", far_dur=1.8)
gun("shot_kar", "Tikka/W_29P.wav", 1.3, pitch=1.05)
y = load("AK-47/C_31P.wav"); s = shots(y)[0]; save("shot_far", finish(lp(y[s:s + int(1.3 * SR)], 1800), 1.3, 0.6))
y = load("Tikka/W_24P.wav"); s = shots(y)[0]; save("shot_far_heavy", finish(lp(y[s:s + int(1.8 * SR)], 1500), 1.8, 0.65))
print("done")
