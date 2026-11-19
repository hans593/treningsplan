"""Lager appens egne treningslåter (egne komposisjoner, ingen opphavsrett).

For hver musikktype lages to filer i assets/musikk/:
  <type>_arbeid.mp3  – under arbeid (sett, intervaller)
  <type>_pause.mp3   – i pauser og oppvarming

Typer: rolig, piano, rock, pop, klassisk

Kjør:  python3 tools/lag_musikk.py [type ...]   (krever numpy, scipy og ffmpeg)
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'musikk')
rng = np.random.default_rng(7)


# ---------------------------------------------------------------- grunnlag

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def env(n, a=0.005, d=0.1, s=0.6, r=0.05):
    a_n, d_n, r_n = min(int(a * SR), n), int(d * SR), int(r * SR)
    e = np.full(n, s, dtype=np.float32)
    e[:a_n] = np.linspace(0, 1, a_n, endpoint=False)
    d_end = min(a_n + d_n, n)
    e[a_n:d_end] = np.linspace(1, s, d_end - a_n, endpoint=False)
    if r_n and n > r_n:
        e[-r_n:] *= np.linspace(1, 0, r_n)
    return e


def saw(f, n, detune=0.0, voices=3):
    t = tt(n)
    if not detune:
        return (2 * ((t * f) % 1.0) - 1).astype(np.float32)
    out = np.zeros(n, np.float32)
    for k in range(voices):
        d = detune * (k - (voices - 1) / 2)
        out += 2 * ((t * f * (1 + d) + rng.random()) % 1.0) - 1
    return out / voices


def square(f, n):
    return np.sign(np.sin(2 * np.pi * f * tt(n))).astype(np.float32)


def _sos(kind, cut, order=2):
    if kind == 'band':
        return butter(order, [cut[0] / (SR / 2), cut[1] / (SR / 2)], 'band', output='sos')
    return butter(order, min(cut, SR * 0.45) / (SR / 2), kind, output='sos')


def lp(x, cut, order=2):
    return sosfilt(_sos('low', cut, order), x).astype(np.float32)


def hp(x, cut, order=2):
    return sosfilt(_sos('high', cut, order), x).astype(np.float32)


def bp(x, lo, hi):
    return sosfilt(_sos('band', (lo, hi)), x).astype(np.float32)


def place(buf, sample, pos, gain=1.0):
    pos = int(pos)
    if pos >= len(buf) or pos < 0:
        return
    end = min(len(buf), pos + len(sample))
    buf[pos:end] += sample[: end - pos] * gain


def reverb(x, seconds=1.6, mix=0.25, tone=4000):
    n = int(seconds * SR)
    ir = rng.standard_normal(n).astype(np.float32) * np.exp(-tt(n) * 6.9 / seconds).astype(np.float32)
    ir = lp(ir, tone)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = fftconvolve(x, ir)[: len(x)].astype(np.float32)
    return x * (1 - mix) + wet * mix * 1.5


def delay(x, time_s, fb=0.35, mix=0.3):
    d = int(time_s * SR)
    acc = np.zeros_like(x)
    y = x
    for _ in range(4):
        y2 = np.zeros_like(y)
        y2[d:] = y[:-d]
        acc += y2
        y = y2 * fb
    return x + acc * mix


def sidechain(n_total, beat_n, depth=0.6):
    one = 1 - depth * np.exp(-tt(beat_n) * 12)
    return np.tile(one, n_total // beat_n + 1)[:n_total].astype(np.float32)


# ---------------------------------------------------------------- instrumenter

def kick(punch=1.0):
    n = int(0.32 * SR)
    t = tt(n)
    f = 48 + 110 * punch * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return (np.sin(ph) * np.exp(-t * 9) + 0.15 * np.sin(ph * 2) * np.exp(-t * 30)).astype(np.float32)


def clap():
    n = int(0.22 * SR)
    t = tt(n)
    e = np.exp(-t * 22) + 0.6 * np.exp(-((t - 0.012) ** 2) / 0.00002)
    return bp(rng.standard_normal(n).astype(np.float32), 900, 4000) * e.astype(np.float32) * 0.9


def snare():
    n = int(0.25 * SR)
    t = tt(n)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25)
    noise = bp(rng.standard_normal(n).astype(np.float32), 1500, 8000) * np.exp(-t * 14)
    return (tone * 0.6 + noise).astype(np.float32)


def hat(open_=False, level=0.45):
    n = int((0.18 if open_ else 0.05) * SR)
    return hp(rng.standard_normal(n).astype(np.float32), 7000) * np.exp(-tt(n) * (14 if open_ else 70)).astype(np.float32) * level


def crash():
    n = int(1.6 * SR)
    return hp(rng.standard_normal(n).astype(np.float32), 4000) * np.exp(-tt(n) * 2.5).astype(np.float32) * 0.35


def shaker(level=0.25):
    n = int(0.07 * SR)
    e = np.sin(np.pi * np.clip(tt(n) / 0.07, 0, 1)) ** 2
    return hp(rng.standard_normal(n).astype(np.float32), 5000) * e.astype(np.float32) * level


def timpani(f):
    n = int(1.2 * SR)
    t = tt(n)
    x = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 1.5 * t) + 0.2 * np.sin(2 * np.pi * f * 2.0 * t)
    return (x * np.exp(-t * 4)).astype(np.float32) * 0.8


def piano(note, dur, vel=1.0):
    """Pianoaktig tone: overtoner med litt uharmonisitet, ulik dempning og anslag."""
    f = midi(note)
    n = int((dur + 0.6) * SR)
    t = tt(n)
    x = np.zeros(n, np.float32)
    for k in range(1, 9):
        fk = f * k * np.sqrt(1 + 0.0004 * k * k)
        if fk > SR / 2.2:
            break
        decay = 1.2 + 0.9 * k + f / 400
        x += (np.sin(2 * np.pi * fk * t) * np.exp(-t * decay) / k ** 1.1).astype(np.float32)
    hammer = lp(rng.standard_normal(int(0.01 * SR)).astype(np.float32), 3000) * 0.3
    x[: len(hammer)] += hammer
    rel = np.ones(n, np.float32)
    off = int(dur * SR)
    if off < n:
        rel[off:] = np.exp(-tt(n - off) * 12)
    return x * rel * vel * 0.5


def strings(notes, dur, attack=0.25, bright=2500):
    """Strykere: flere svakt forstemte sagtenner med vibrato og myk innsving."""
    n = int(dur * SR)
    t = tt(n)
    out = np.zeros(n, np.float32)
    for nn in notes:
        f = midi(nn)
        for k in range(4):
            vib = 1 + 0.004 * np.sin(2 * np.pi * (5.2 + 0.3 * k) * t + rng.random() * 6)
            ph = np.cumsum(f * (1 + 0.003 * (k - 1.5)) * vib) / SR
            out += (2 * (ph % 1.0) - 1).astype(np.float32)
    out = lp(out / (4 * len(notes)), bright, 2)
    return out * env(n, attack, 0.1, 0.9, min(0.3, dur / 3))


def pluck(note, dur, bright=0.5, decay=0.996):
    """Gitar-/harpeaktig klimpring (Karplus–Strong), regnet blokkvis."""
    f = midi(note)
    N = max(2, int(SR / f))
    n = int((dur + 0.4) * SR)
    y = np.zeros(n + N + 1, np.float32)
    y[: N + 1] = lp(rng.uniform(-1, 1, N + 1).astype(np.float32), 1500 + 6000 * bright)
    pos = N + 1
    while pos < len(y):
        end = min(len(y), pos + N)
        seg = np.arange(pos, end)
        y[seg] = decay * 0.5 * (y[seg - N] + y[seg - N - 1])
        pos = end
    out = y[N + 1 : N + 1 + n]
    off = int(dur * SR)
    if off < n:
        out[off:] *= np.exp(-tt(n - off) * 15)
    return out * 0.8


def power_chord(root, dur, mute=False):
    """Forvrengt elgitar (grunntone, kvint, oktav)."""
    n = int(dur * SR)
    x = sum(saw(midi(r), n, detune=0.003) for r in (root, root + 7, root + 12)) / 3
    x = lp(x, 3500)
    x = np.tanh(x * 9).astype(np.float32)
    x = lp(x, 5000 if not mute else 2200)
    return x * env(n, 0.003, 0.05, 0.9 if not mute else 0.5, 0.02)


def sine_bass(note, dur, drive=1.0):
    n = int(dur * SR)
    x = np.sin(2 * np.pi * midi(note) * tt(n)).astype(np.float32)
    x = np.tanh(x * drive) if drive > 1 else x
    return x * env(n, 0.005, 0.1, 0.8, 0.03)


def saw_bass(note, dur, cut=600):
    n = int(dur * SR)
    return lp(saw(midi(note), n), cut) * env(n, 0.003, 0.08, 0.5, 0.03)


# ---------------------------------------------------------------- komposisjoner

class Song:
    def __init__(self, bpm, bars):
        self.beat = 60 / bpm
        self.beat_n = int(self.beat * SR)
        self.bar_n = self.beat_n * 4
        self.n = self.bar_n * bars
        self.bars = bars

    def buf(self):
        return np.zeros(self.n, np.float32)

    def at(self, bar, beat=0.0):
        return bar * self.bar_n + int(beat * self.beat_n)


def section(b, intro=4, brk=(0, 0)):
    if b < intro:
        return 'intro'
    if brk[0] <= b < brk[1]:
        return 'break'
    return 'main'


# ---- POP (elektronisk pop, 128 BPM) ----
POP = [(57, [69, 72, 76]), (53, [65, 69, 72]), (60, [67, 72, 76]), (55, [67, 71, 74])]


def pop_arbeid():
    s = Song(128, 64)
    drums, bass, arp, pad = s.buf(), s.buf(), s.buf(), s.buf()
    k, c, h, ho = kick(), clap(), hat(), hat(True)
    for b in range(s.bars):
        root, chord = POP[b % 4]
        sec = section(b, 8, (32, 40))
        for i in range(4):
            if sec != 'break':
                place(drums, k, s.at(b, i), 0.95)
            if i in (1, 3) and sec == 'main':
                place(drums, c, s.at(b, i), 0.55)
            place(drums, h, s.at(b, i + 0.5), 0.5 if sec != 'break' else 0.3)
            if sec == 'main' and i == 3 and b % 4 == 3:
                place(drums, ho, s.at(b, i + 0.5), 0.5)
        if sec != 'break':
            for e8 in range(1, 8, 2):
                place(bass, saw_bass(root - 12, s.beat / 2), s.at(b, e8 / 2), 0.55)
        if sec != 'intro':
            notes = chord + [chord[0] + 12]
            for j, p in enumerate([0, 1, 2, 3, 2, 1, 0, 2] * 2):
                n16 = s.beat_n // 4
                f = midi(notes[p])
                cut = 1800 + 1400 * np.sin(2 * np.pi * (b * 16 + j) / 128) ** 2
                x = lp(square(f, n16) * 0.5 + saw(f, n16) * 0.5, cut) * env(n16, 0.002, 0.06, 0.2, 0.02)
                place(arp, x, s.at(b, j / 4), 0.22)
        tones = [saw(midi(nn - 12), s.bar_n, detune=0.004) for nn in chord]
        place(pad, lp(sum(tones) / 3, 1200 if sec != 'break' else 2200) * env(s.bar_n, 0.25, 0.3, 0.8, 0.3),
              s.at(b), 0.28 if sec != 'intro' else 0.15)
    sc = sidechain(s.n, s.beat_n, 0.65)
    return drums * 0.9 + bass * sc + delay(arp, s.beat * 0.75) * sc + pad * sc


def pop_pause():
    s = Song(88, 24)
    pad, pl, perc = s.buf(), s.buf(), s.buf()
    for b in range(s.bars):
        root, chord = POP[b % 4]
        tones = [saw(midi(nn - 12), s.bar_n, detune=0.006) for nn in chord + [root]]
        place(pad, lp(sum(tones) / 4, 700) * env(s.bar_n, 0.8, 0.4, 0.85, 0.8), s.at(b), 0.5)
        for i in range(4):
            nn = (chord + [chord[1] + 12])[i]
            t = tt(s.beat_n)
            x = (np.sin(2 * np.pi * midi(nn) * t) + 0.3 * np.sin(4 * np.pi * midi(nn) * t)) * np.exp(-t * 4)
            place(pl, x.astype(np.float32), s.at(b, i), 0.18)
            place(perc, shaker(), s.at(b, i + 0.5), 0.3)
    return pad + delay(pl, s.beat * 0.5, 0.4, 0.35) + perc


# ---- ROLIG (myk akustisk groove, 100 BPM) ----
ROLIG = [(62, [66, 69, 74]), (59, [62, 66, 71]), (55, [62, 67, 71]), (57, [61, 64, 69])]  # D Bm G A


def rolig_arbeid():
    s = Song(100, 48)
    drums, bass, gtr, pad, mel = s.buf(), s.buf(), s.buf(), s.buf(), s.buf()
    k = kick(0.6)
    melody = [74, 73, 71, 69, 71, 73, 74, 76, 78, 76, 74, 73, 71, 73, 74, 71]
    for b in range(s.bars):
        root, chord = ROLIG[b % 4]
        sec = section(b, 4, (24, 28))
        if sec != 'break':
            for i in (0, 2.5):
                place(drums, k, s.at(b, i), 0.6)
            for i in (1, 3):
                place(drums, snare(), s.at(b, i), 0.18)
        for i in range(8):
            place(drums, shaker(0.18), s.at(b, i / 2), 0.7 if i % 2 else 0.35)
        place(bass, sine_bass(root - 24, s.beat * 1.5), s.at(b), 0.6)
        place(bass, sine_bass(root - 24, s.beat), s.at(b, 2.5), 0.45)
        for j, p in enumerate([0, 1, 2, 1, 2, 1, 0, 2]):
            place(gtr, pluck(chord[p], s.beat / 2, 0.4), s.at(b, j / 2), 0.35)
        tones = [saw(midi(nn - 12), s.bar_n, detune=0.005) for nn in chord]
        place(pad, lp(sum(tones) / 3, 900) * env(s.bar_n, 0.6, 0.3, 0.8, 0.6), s.at(b), 0.2)
        if sec == 'main' and (b // 8) % 2 == 1:
            for j in range(4):
                place(mel, piano(melody[(b % 4) * 4 + j], s.beat * 0.9, 0.7), s.at(b, j), 0.35)
    mix = reverb(drums * 0.8 + bass + gtr + pad + delay(mel, s.beat * 0.75, 0.3, 0.3), 1.8, 0.22)
    return lp(mix, 8000)  # mykere topp for rolig musikk


def rolig_pause():
    s = Song(70, 18)
    pad, pn = s.buf(), s.buf()
    for b in range(s.bars):
        root, chord = ROLIG[b % 4]
        place(pad, strings([n - 12 for n in chord] + [root - 12], s.bar_n / SR, 1.2, 1400), s.at(b), 0.6)
        for i, nn in enumerate([chord[0] + 12, chord[2], chord[1] + 12, chord[2] + 12]):
            if (b + i) % 3 != 2:
                place(pn, piano(nn, s.beat * 1.5, 0.45), s.at(b, i), 0.5)
    return reverb(pad + pn, 3.0, 0.4, 3000)


# ---- PIANO (pianohouse, 118 BPM / rolig piano) ----
PIANO = [(48, [60, 64, 67, 72]), (45, [57, 60, 64, 69]), (41, [57, 60, 65, 69]), (43, [55, 59, 62, 67])]  # C Am F G


def piano_arbeid():
    s = Song(118, 56)
    drums, bass, pn = s.buf(), s.buf(), s.buf()
    k, c, h = kick(0.9), clap(), hat(level=0.35)
    rhythm = [0.5, 1.5, 2.0, 2.5, 3.5]  # synkopert pianoakkompagnement
    for b in range(s.bars):
        root, chord = PIANO[b % 4]
        sec = section(b, 4, (28, 32))
        for i in range(4):
            if sec != 'break':
                place(drums, k, s.at(b, i), 0.85)
                place(drums, h, s.at(b, i + 0.5), 1.0)
            if i in (1, 3) and sec == 'main':
                place(drums, c, s.at(b, i), 0.45)
        if sec != 'break':
            for i in range(4):
                place(bass, sine_bass(root - 12, s.beat * 0.45, 2.0), s.at(b, i + 0.5), 0.5)
        for r in rhythm:
            for nn in chord:
                place(pn, piano(nn, s.beat * 0.4, 0.9), s.at(b, r), 0.3)
        if sec == 'main' and b % 8 >= 4:
            top = chord[-1] + 12
            for j, nn in enumerate([top, top - 3, top - 5, top - 3]):
                place(pn, piano(nn, s.beat * 0.5, 0.6), s.at(b, j), 0.25)
    sc = sidechain(s.n, s.beat_n, 0.4)
    return drums * 0.85 + bass * sc + reverb(pn, 1.4, 0.2) * sc


def piano_pause():
    s = Song(72, 20)
    pn = s.buf()
    for b in range(s.bars):
        root, chord = PIANO[(b + 1) % 4]
        place(pn, piano(root - 12, s.beat * 3.5, 0.7), s.at(b), 0.5)
        arp = [chord[0], chord[1], chord[2], chord[3], chord[2], chord[1]]
        for j, nn in enumerate(arp):
            place(pn, piano(nn, s.beat * 1.2, 0.5), s.at(b, j * 4 / 6), 0.4)
        if b % 2 == 1:
            place(pn, piano(chord[3] + 12, s.beat * 2, 0.4), s.at(b, 2), 0.35)
    return reverb(pn, 2.6, 0.35, 3500)


# ---- ROCK (140 BPM / rolig gitar) ----
ROCK = [(40, [52, 55, 59]), (36, [48, 52, 55]), (43, [55, 59, 62]), (38, [50, 54, 57])]  # Em C G D


def rock_arbeid():
    s = Song(140, 64)
    drums, bass, gtr = s.buf(), s.buf(), s.buf()
    k, sn, h, cr = kick(1.2), snare(), hat(level=0.35), crash()
    for b in range(s.bars):
        root, _ = ROCK[b % 4]
        sec = section(b, 4, (32, 36))
        if b % 8 == 0 and sec != 'intro':
            place(drums, cr, s.at(b), 1.0)
        for i in range(8):
            beat = i / 2
            if sec == 'break':
                if i % 2 == 0:
                    place(drums, h, s.at(b, beat), 1.0)
                continue
            if i in (0, 3, 4):
                place(drums, k, s.at(b, beat), 1.0)
            if i in (2, 6) and sec != 'intro':
                place(drums, sn, s.at(b, beat), 0.7)
            place(drums, h, s.at(b, beat), 1.0)
        # Gitar: åttendedeler med power chords, aksent på 1, «og» på 2, og 3
        for i in range(8):
            accent = i in (0, 3, 4)
            g = power_chord(root + 12, s.beat / 2 * (0.95 if accent else 0.6), mute=not accent and sec != 'break')
            place(gtr, g, s.at(b, i / 2), 0.4 if sec != 'intro' else 0.25)
            if sec != 'break':
                place(bass, saw_bass(root, s.beat / 2 * 0.9, 900), s.at(b, i / 2), 0.55)
        if sec == 'main' and b % 4 == 3:  # lite trommebreak
            for j, beat in enumerate([3.0, 3.25, 3.5, 3.75]):
                place(drums, sn, s.at(b, beat), 0.4 + 0.1 * j)
    return drums * 0.9 + bass + reverb(gtr, 0.8, 0.12)


def rock_pause():
    s = Song(80, 20)
    gtr, bass = s.buf(), s.buf()
    for b in range(s.bars):
        root, chord = ROCK[b % 4]
        notes = [root + 12, chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[1] + 12, chord[0] + 12]
        for j, nn in enumerate(notes):
            place(gtr, pluck(nn, s.beat, 0.6, 0.997), s.at(b, j * 4 / 6), 0.45)
        place(bass, sine_bass(root, s.beat * 3.5), s.at(b), 0.35)
    return reverb(delay(gtr, s.beat * 0.75, 0.3, 0.25) + bass, 2.2, 0.3)


# ---- KLASSISK (barokk-energi for strykere, 120 BPM / adagio) ----
KLASSISK = [(43, [55, 58, 62]), (48, [55, 60, 63]), (41, [53, 57, 60]), (46, [53, 58, 62]),
            (39, [55, 58, 63]), (48, [55, 60, 63]), (38, [54, 57, 62]), (38, [54, 57, 62])]  # Gm Cm F Bb Eb Cm D D


def klassisk_arbeid():
    s = Song(120, 48)
    vln, low, hold, timp = s.buf(), s.buf(), s.buf(), s.buf()
    for b in range(s.bars):
        root, chord = KLASSISK[b % 8]
        sec = section(b, 2, (24, 28))
        top = [n + 12 for n in chord]
        fig = [top[0], top[1], top[2], top[1], top[2], top[1], top[0], top[1]] * 2
        if sec != 'intro':
            for j, nn in enumerate(fig):
                place(vln, strings([nn], s.beat / 4 * 0.95, 0.01, 4500), s.at(b, j / 4), 0.5 if j % 4 == 0 else 0.35)
        for i in range(8):
            if sec != 'break':
                place(low, strings([root - 12, root], s.beat / 2 * 0.85, 0.01, 1800), s.at(b, i / 2), 0.55)
        place(hold, strings(chord, s.bar_n / SR, 0.3, 2200), s.at(b), 0.35)
        if b % 2 == 0 and sec == 'main':
            place(timp, timpani(midi(root - 12)), s.at(b), 0.6)
            place(timp, timpani(midi(root - 5)), s.at(b, 2), 0.4)
    return reverb(vln + low + hold + timp, 2.2, 0.3, 5000)


def klassisk_pause():
    s = Song(60, 12)
    st = s.buf()
    for b in range(s.bars):
        root, chord = KLASSISK[b % 8]
        place(st, strings([root - 12] + chord + [chord[2] + 12], s.bar_n / SR + 0.3, 1.0, 1800), s.at(b), 0.7)
    return reverb(st, 3.5, 0.45, 3000)


GENRES = {
    'pop': (pop_arbeid, pop_pause),
    'rolig': (rolig_arbeid, rolig_pause),
    'piano': (piano_arbeid, piano_pause),
    'rock': (rock_arbeid, rock_pause),
    'klassisk': (klassisk_arbeid, klassisk_pause),
}


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    f = int(0.03 * SR)
    x = x.astype(np.float32)
    x[:f] *= np.linspace(0, 1, f)
    x[-f:] *= np.linspace(1, 0, f)
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.9
    with tempfile.TemporaryDirectory() as d:
        wav = os.path.join(d, name + '.wav')
        wavfile.write(wav, SR, (x * 32767).astype(np.int16))
        mp3 = os.path.join(OUT, name + '.mp3')
        subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav,
                        '-af', 'loudnorm=I=-14:TP=-1.5:LRA=11', '-ar', '44100', '-ac', '1',
                        '-b:a', '96k', mp3], check=True)
    print('Laget', os.path.relpath(mp3))


if __name__ == '__main__':
    for g in sys.argv[1:] or GENRES:
        arbeid, pause = GENRES[g]
        write(f'{g}_arbeid', arbeid())
        write(f'{g}_pause', pause())
