"""v4.16 real weapon recordings -> assets/sfx (replaces older synthetic / generic takes; originals backed up).
Sources (all free for commercial use):
  Freesound CC0  (freesound.org, ids in the file names)      Sonniss GDC 2020 Game Audio Bundle (Pole Position Production;
  royalty-free, no attribution required, sonniss.com/gdc-bundle-license)
Every take is cut at a detected transient, trimmed, faded and peak-normalised; several takes per sound become _v1, _v2 variants.
python3 tools/build_sfx4.py
"""
import os, subprocess, shutil, json
import numpy as np

SRC = '/home/claude/src_assets/audio/b1/'
OUT = '/home/claude/sokak/assets/sfx/'
BAK = '/home/claude/old_assets/sfx_v415/'
SR = 44100
os.makedirs(BAK, exist_ok=True)


def load(fn):
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', SRC + fn, '-ac', '1', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).copy()


def onsets(x, n, gap=0.35, thr=0.35):
    """indices of the n loudest transients at least `gap` s apart (onset = first sample over 20 % of that peak)"""
    env = np.abs(x)
    w = int(0.002 * SR)
    env = np.convolve(env, np.ones(w) / w, 'same')
    order = np.argsort(env)[::-1]
    picks = []
    pk = env.max()
    for i in order:
        if env[i] < pk * thr or len(picks) >= n:
            break
        if all(abs(i - p) > gap * SR for p in picks):
            picks.append(i)
    out = []
    for p in sorted(picks):
        j = p
        while j > 0 and env[j] > env[p] * 0.2 and p - j < 0.05 * SR:
            j -= 1
        out.append(max(0, j - int(0.003 * SR)))
    return out


def save(y, name, dur, fade=0.25, gain_db=-1.0):
    y = y[:int(dur * SR)].astype(np.float32)
    if len(y) < 16:
        return
    fl = min(int(min(fade, dur * 0.8) * SR), len(y) // 2)
    if fl > 0:
        y[-fl:] *= np.linspace(1, 0, fl) ** 2
    y[:32] *= np.linspace(0, 1, 32)
    y = y / max(np.abs(y).max(), 1e-6) * 10 ** (gain_db / 20)
    for ext in ('.wav', '.ogg'):
        p = OUT + name + ext
        if os.path.exists(p) and not os.path.exists(BAK + name + ext):
            shutil.copy(p, BAK + name + ext)
        if ext == '.ogg' and os.path.exists(p):
            os.remove(p)
            if os.path.exists(p + '.import'):
                os.remove(p + '.import')
    pcm = (np.clip(y, -1, 1) * 32767).astype('<i2').tobytes()
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 's16le', '-ar', str(SR), '-ac', '1', '-i', '-', OUT + name + '.wav'],
                   input=pcm, check=True)
    REPORT.append((name, round(len(y) / SR, 2)))


def takes(fn, base, n, dur, gap=0.35, fade=0.25, thr=0.35, start=0.0, gain_db=-1.0):
    x = load(fn)
    x = x[int(start * SR):]
    on = onsets(x, n, gap, thr)
    for k, o in enumerate(on):
        save(x[o:], base if k == 0 else f'{base}_v{k}', dur, fade, gain_db)
    return len(on)


REPORT = []
F = {
    'ak_close': '136399__felixblume__rifle-gun-shot-ak47-close-recording-in-a-shooting-range.wav',
    'ak_qubo': '184750__qubodup__ak-47.flac',
    'ak_dist': '201669__franki-01234__ak47-down-the-block.aiff',
    'rifle1': '710084__felixblume__rifle-gunshot-one-shot.wav',
    'pistol': '668348__deltacode__handgun-one-shot.wav',
    'pistol_in': '402789__acidsnowflake__small-pistol-gunshot-indoors.wav',
    'ar15p': '427598__michorvath__ar15-pistol-shot.wav',
    'sup': '539141__subwaysandwitch420__assault-rifle-suppressor-gunshot.wav',
    'm1903': 'M1903A3, Firing, t2, 1m, Right, Above, MKH8060.wav',
    'm1903bolt': 'M1903A3, Handling, Cycling Bolt, MKH416.wav',
    'tommy': '1928A1, Firing, t2, Burst, 1m, Right, Above, MKH8060.wav',
    'dry': '1928A1, Handling, Dry Fire, MKH416.wav',
    'shells': '318964__gryffdavid__bouncing-shell-casings-various-sizes.wav',
    'akshell': '507048__kaniaplania__gun_ak47_shell_bullet_floor_tiles.wav',
    'bodyfall': '181177__jmdh__body-falling-to-floor.wav',
    'steps': '813622__securesubset__footsteps-stone-rock-concrete-cement.wav',
}
if __name__ == '__main__':
    takes(F['ak_close'], 'shot_ak', 3, 0.85)
    takes(F['ak_qubo'], 'shot_akm', 3, 0.85)
    takes(F['ak_dist'], 'shotfar_ak', 1, 1.4, fade=0.6, gain_db=-3.0)
    takes(F['ak_dist'], 'shotfar_akm', 1, 1.4, fade=0.6, gain_db=-3.0)
    takes(F['m1903'], 'shot_sniper', 2, 1.6, gap=0.6, fade=0.7)
    takes(F['rifle1'], 'shot_kar', 1, 1.4, fade=0.6)
    takes(F['m1903'], 'shot_awm', 2, 1.6, gap=0.6, fade=0.7)
    takes(F['pistol'], 'shot_pistol', 1, 0.7)
    takes(F['pistol_in'], 'shot_pistol_v1', 1, 0.7)
    takes(F['ar15p'], 'shot_pistol_v2', 1, 0.7)
    takes(F['pistol'], 'shot_usp', 1, 0.7)
    takes(F['pistol_in'], 'shot_m1911', 1, 0.7)
    takes(F['tommy'], 'shot_smg', 3, 0.45, gap=0.07, fade=0.2, thr=0.5)
    takes(F['sup'], 'shot_sup', 1, 0.6, fade=0.3)
    # mechanics: bolt cycle = two transients (back / forward)
    x = load(F['m1903bolt'])
    on = onsets(x, 2, gap=0.15, thr=0.25)
    if len(on) == 2:
        save(x[on[0]:], 'bolt_back', min(0.45, (on[1] - on[0]) / SR), fade=0.1)
        save(x[on[1]:], 'bolt_fwd', 0.45, fade=0.15)
    takes(F['dry'], 'dryfire', 1, 0.25, fade=0.12)
    takes(F['shells'], 'shell', 3, 0.7, gap=0.5, fade=0.3, thr=0.2, gain_db=-6.0)
    takes(F['bodyfall'], 'bodyfall', 1, 0.9, fade=0.4)
    takes(F['steps'], 'step_concrete0', 1, 0.32, fade=0.12, gain_db=-4.0)
    x = load(F['steps'])
    on = onsets(x, 4, gap=0.3, thr=0.3)
    for k, o in enumerate(on):
        save(x[o:], f'step_concrete{k}', 0.32, fade=0.12, gain_db=-4.0)
    json.dump(REPORT, open('/tmp/sfx4_report.json', 'w'))
    for r in REPORT:
        print(*r)
