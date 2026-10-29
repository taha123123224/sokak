"""AI announcer lines (Kokoro-82M TTS, Apache-2.0) processed into a punchy game announcer voice."""
import os, sys, numpy as np
from scipy.io import wavfile
from scipy.signal import resample, butter, sosfilt, fftconvolve
from kokoro_onnx import Kokoro

K = '/home/claude/ext/kokoro'
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sfx')
kok = Kokoro(os.path.join(K, 'kokoro-v1.0.int8.onnx'), os.path.join(K, 'voices-v1.0.bin'))
VOICE = os.environ.get('VOICE', 'am_michael')
LINES = {
    'ann_head': 'Headshot!', 'ann_double': 'Double kill!', 'ann_triple': 'Triple kill!', 'ann_quad': 'Multi kill!',
    'ann_penta': 'Unstoppable!', 'ann_knife': 'Humiliation!', 'ann_grenade': 'Boom! Grenade kill!', 'ann_streak': 'Killing spree!',
    'ann_start': 'Fight!', 'ann_win': 'Victory!', 'ann_lose': 'Defeat.', 'ann_first': 'First blood!', 'ann_lead': 'You have taken the lead!',
}


def bq(x, kind, fc, sr, o=2):
    return sosfilt(butter(o, fc, kind, fs=sr, output='sos'), x)


for key, text in LINES.items():
    a, sr = kok.create(text, voice=VOICE, speed=0.92, lang='en-us')
    x = np.asarray(a, dtype=np.float64)
    # trim silence
    th = 0.02 * np.abs(x).max()
    idx = np.where(np.abs(x) > th)[0]
    x = x[max(idx[0] - int(0.01 * sr), 0): idx[-1] + int(0.08 * sr)]
    # deeper, larger-than-life: pitch down ~6% (resample), add a sub-octave layer
    x = resample(x, int(len(x) * 1.06))
    sub = bq(x, 'lowpass', 300, sr) * 0.35
    x = x + sub
    # presence + slight radio edge
    x = x + bq(x, 'bandpass', [2000, 4500], sr) * 0.35
    x = bq(x, 'highpass', 80, sr)
    # compression / saturation
    x = np.tanh(x / (np.abs(x).max() + 1e-9) * 2.2) / np.tanh(2.2)
    # arena reverb
    n = int(0.9 * sr); t = np.arange(n) / sr
    ir = np.random.default_rng(3).standard_normal(n) * np.exp(-t / 0.25)
    ir = bq(ir, 'lowpass', 3500, sr); ir[:int(0.012 * sr)] = 0; ir /= np.abs(ir).max()
    wet = fftconvolve(x, ir)[:len(x) + n] * 0.035
    y = np.zeros(len(wet)); y[:len(x)] += x; y += wet
    y = y / np.abs(y).max() * 0.92
    if sr != 44100:
        y = resample(y, int(len(y) * 44100 / sr)); sr = 44100
    wavfile.write(os.path.join(OUT, key + '.wav'), sr, (y * 32767).astype(np.int16))
    print(key, round(len(y) / sr, 2), 's')
