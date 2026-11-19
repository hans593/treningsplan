"""Lager appens egne treningslåter (ingen opphavsrett): arbeid.mp3 og pause.mp3.

Kjør:  python3 tools/lag_musikk.py   (krever numpy, scipy og ffmpeg)
"""
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'musikk')


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def env(n, a=0.005, d=0.1, s=0.6, r=0.05, length=None):
    """ADSR-kurve over n samples."""
    length = length or n
    a_n, d_n, r_n = int(a * SR), int(d * SR), int(r * SR)
    e = np.full(n, s, dtype=np.float32)
    a_n = min(a_n, n)
    e[:a_n] = np.linspace(0, 1, a_n, endpoint=False)
    d_end = min(a_n + d_n, n)
    e[a_n:d_end] = np.linspace(1, s, d_end - a_n, endpoint=False)
    if r_n and n > r_n:
        e[-r_n:] *= np.linspace(1, 0, r_n)
    return e


def saw(f, n, detune=0.0):
    t = np.arange(n) / SR
    out = np.zeros(n, dtype=np.float32)
    for d in (-detune, 0, detune) if detune else (0,):
        ph = (t * f * (1 + d)) % 1.0
        out += (2 * ph - 1)
    return out / (3 if detune else 1)


def square(f, n):
    t = np.arange(n) / SR
    return np.sign(np.sin(2 * np.pi * f * t)).astype(np.float32)


def lp(x, cut, order=2):
    sos = butter(order, min(cut, SR * 0.45) / (SR / 2), 'low', output='sos')
    return sosfilt(sos, x).astype(np.float32)


def hp(x, cut, order=2):
    sos = butter(order, cut / (SR / 2), 'high', output='sos')
    return sosfilt(sos, x).astype(np.float32)


def bp(x, lo, hi):
    sos = butter(2, [lo / (SR / 2), hi / (SR / 2)], 'band', output='sos')
    return sosfilt(sos, x).astype(np.float32)


rng = np.random.default_rng(7)


def kick():
    n = int(0.32 * SR)
    t = np.arange(n) / SR
    f = 48 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) * np.exp(-t * 9) + 0.15 * np.sin(ph * 2) * np.exp(-t * 30)).astype(np.float32)


def clap():
    n = int(0.22 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n).astype(np.float32)
    e = np.exp(-t * 22) + 0.6 * np.exp(-((t - 0.012) ** 2) / 0.00002)
    return bp(noise, 900, 4000) * e.astype(np.float32) * 0.9


def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n).astype(np.float32)
    return hp(noise, 7000) * np.exp(-t * (14 if open_ else 70)).astype(np.float32) * 0.45


def shaker():
    n = int(0.07 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n).astype(np.float32)
    e = np.sin(np.pi * np.clip(t / 0.07, 0, 1)) ** 2
    return hp(noise, 5000) * e.astype(np.float32) * 0.25


def place(buf, sample, pos, gain=1.0):
    pos = int(pos)
    if pos >= len(buf):
        return
    end = min(len(buf), pos + len(sample))
    buf[pos:end] += sample[: end - pos] * gain


def sidechain(n_total, beat_n, depth=0.6):
    """Volumkurve som «pumper» med basstromma."""
    t = np.arange(beat_n) / SR
    one = 1 - depth * np.exp(-t * 12)
    reps = n_total // beat_n + 1
    return np.tile(one, reps)[:n_total].astype(np.float32)


def delay(x, time_s, fb=0.35, mix=0.3):
    d = int(time_s * SR)
    out = x.copy()
    y = np.zeros_like(x)
    y[d:] = x[:-d]
    acc = y.copy()
    for _ in range(3):
        y2 = np.zeros_like(y)
        y2[d:] = y[:-d] * fb
        acc += y2
        y = y2
    return out + acc * mix


# Am – F – C – G (grunntone i MIDI, akkordtoner)
PROG = [(57, [69, 72, 76]), (53, [65, 69, 72]), (60, [67, 72, 76]), (55, [67, 71, 74])]


def arbeid(bpm=128, bars=64):
    beat = 60 / bpm
    beat_n = int(beat * SR)
    bar_n = beat_n * 4
    n = bar_n * bars
    drums = np.zeros(n, np.float32)
    bass = np.zeros(n, np.float32)
    arp = np.zeros(n, np.float32)
    pad = np.zeros(n, np.float32)
    k, c, h, ho = kick(), clap(), hat(), hat(True)

    for b in range(bars):
        root, chord = PROG[b % 4]
        start = b * bar_n
        section = 'intro' if b < 8 else 'break' if 32 <= b < 40 else 'outro' if b >= 60 else 'main'
        for i in range(4):
            pos = start + i * beat_n
            if section != 'break':
                place(drums, k, pos, 0.95)
            if i in (1, 3) and section in ('main', 'outro'):
                place(drums, c, pos, 0.55)
            place(drums, h, pos + beat_n // 2, 0.5 if section != 'break' else 0.3)
            if section == 'main' and i == 3 and b % 4 == 3:
                place(drums, ho, pos + beat_n // 2, 0.5)
        # Bass: åttendedeler på offbeat
        if section != 'break':
            note_n = beat_n // 2
            for e8 in range(8):
                if e8 % 2 == 1:
                    s = lp(saw(midi(root - 12), note_n), 600) * env(note_n, 0.003, 0.08, 0.5, 0.03)
                    place(bass, s, start + e8 * note_n, 0.55)
        # Arpeggio: sekstendedeler
        if section in ('main', 'break', 'outro'):
            n16 = beat_n // 4
            notes = chord + [chord[0] + 12]
            pattern = [0, 1, 2, 3, 2, 1, 0, 2] * 2
            for j, p in enumerate(pattern):
                f = midi(notes[p])
                cut = 1800 + 1400 * np.sin(2 * np.pi * (b * 16 + j) / 128) ** 2
                s = lp(square(f, n16) * 0.5 + saw(f, n16) * 0.5, cut) * env(n16, 0.002, 0.06, 0.2, 0.02)
                place(arp, s, start + j * n16, 0.22)
        # Pad: akkord over hele takten
        tones = [saw(midi(nn - 12), bar_n, detune=0.004) for nn in chord]
        p = lp(sum(tones) / 3, 1200 if section != 'break' else 2200) * env(bar_n, 0.25, 0.3, 0.8, 0.3)
        place(pad, p, start, 0.28 if section != 'intro' else 0.15)

    sc = sidechain(n, beat_n, 0.65)
    mix = drums * 0.9 + bass * sc + delay(arp, beat * 0.75) * sc + pad * sc
    return mix


def pause(bpm=88, bars=24):
    beat = 60 / bpm
    beat_n = int(beat * SR)
    bar_n = beat_n * 4
    n = bar_n * bars
    pad = np.zeros(n, np.float32)
    pluck = np.zeros(n, np.float32)
    perc = np.zeros(n, np.float32)
    sh = shaker()
    for b in range(bars):
        root, chord = PROG[b % 4]
        start = b * bar_n
        tones = [saw(midi(nn - 12), bar_n, detune=0.006) for nn in chord + [root]]
        p = lp(sum(tones) / 4, 700) * env(bar_n, 0.8, 0.4, 0.85, 0.8)
        place(pad, p, start, 0.5)
        for i in range(4):
            nn = (chord + [chord[1] + 12])[i]
            q = beat_n
            t = np.arange(q) / SR
            s = (np.sin(2 * np.pi * midi(nn) * t) + 0.3 * np.sin(4 * np.pi * midi(nn) * t)) * np.exp(-t * 4)
            place(pluck, s.astype(np.float32), start + i * beat_n, 0.18)
            place(perc, sh, start + i * beat_n + beat_n // 2, 0.3)
    return pad + delay(pluck, beat * 0.5, 0.4, 0.35) + perc


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    # Myk inn- og uttoning så sløyfen ikke klikker
    f = int(0.02 * SR)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, name + '.wav')
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        mp3 = os.path.join(OUT, name + '.mp3')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav,
                        '-af', 'loudnorm=I=-14:TP=-1.5:LRA=11', '-ar', '44100', '-ac', '1',
                        '-b:a', '128k', mp3], check=True)
    print('Laget', mp3)


if __name__ == '__main__':
    write('arbeid', arbeid())
    write('pause', pause())
