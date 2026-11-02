"""Synthesises Vesper's original theme: a driving spy-thriller cue at 124 BPM in D minor.

Entirely original and generated from scratch, so it is free to use in your films.
Run: python3 scripts/make_theme.py  (needs numpy and ffmpeg)
"""
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44_100
BPM = 124
BEAT = 60 / BPM
BAR = 4 * BEAT
rng = np.random.default_rng(7)


def hz(note):
    """MIDI note number to frequency."""
    return 440.0 * 2 ** ((note - 69) / 12)


def env(n, attack=0.005, release=0.08, sustain=1.0):
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    e = np.full(n, sustain)
    e[:a] = np.linspace(0, sustain, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def saw(f, n, detune=0.0):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for d in (-detune, 0, detune) if detune else (0,):
        ph = (t * f * (1 + d)) % 1.0
        out += 2 * ph - 1
    return out / (3 if detune else 1)


def lowpass(x, cutoff):
    # One-pole low-pass, good enough for warmth.
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1 - a) * v + a * acc
        y[i] = acc
    return y


def place(track, start_s, sig):
    i = int(start_s * SR)
    j = min(len(track), i + len(sig))
    if j > i:
        track[i:j] += sig[: j - i]


# Chords per bar (root MIDI notes) — i  VI  iv  V, then i  III  VI  V.
PROG = [(50, "m"), (46, "M"), (43, "m"), (45, "M"), (50, "m"), (41, "M"), (46, "M"), (45, "M")]
BARS = 48
total = int(BARS * BAR * SR) + SR
bass = np.zeros(total)
drums = np.zeros(total)
stabs = np.zeros(total)
lead = np.zeros(total)
pad = np.zeros(total)


def kick():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 50 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)


def snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n)
    return (0.7 * noise * np.exp(-t * 18) + 0.4 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25))


def hat(open_=False):
    n = int((0.18 if open_ else 0.05) * SR)
    t = np.arange(n) / SR
    noise = rng.uniform(-1, 1, n)
    noise = noise - lowpass(noise, 6000)
    return noise * np.exp(-t * (14 if open_ else 70))


K, S, H, HO = kick(), snare(), hat(), hat(True)

# Bass ostinato in eighths, shaped around each chord root.
BASS_SHAPE = [0, 0, 12, 0, 7, 0, 10, 12]

# Original lead melody (scale degrees as semitones over D), two 8-bar phrases.
MELODY = [
    [(0, 9, 1.5), (1.5, 10, 0.5), (2, 12, 1), (3, 10, 1)],
    [(0, 9, 3), (3, 5, 1)],
    [(0, 7, 1.5), (1.5, 9, 0.5), (2, 10, 1), (3, 7, 1)],
    [(0, 4, 2), (2, 7, 1), (3, 9, 1)],
    [(0, 14, 1.5), (1.5, 12, 0.5), (2, 10, 1), (3, 9, 1)],
    [(0, 5, 2), (2, 9, 2)],
    [(0, 10, 1), (1, 9, 1), (2, 7, 1), (3, 5, 1)],
    [(0, 4, 2.5), (2.5, 1, 0.5), (3, 4, 1)],
]

for bar in range(BARS):
    t0 = bar * BAR
    root, quality = PROG[bar % len(PROG)]
    third = 3 if quality == "m" else 4
    section = bar // 8  # 0 intro, 1 groove, 2 lead, 3 lift, 4 lead, 5 outro

    # Bass from bar 0 (filtered in the intro), driving eighths.
    for k, iv in enumerate(BASS_SHAPE):
        n = int(BEAT / 2 * SR)
        f = hz(root - 12 + iv)
        tone = saw(f, n, 0.003) * env(n, 0.003, 0.05)
        tone = lowpass(tone, 500 if section == 0 else 1100)
        place(bass, t0 + k * BEAT / 2, 0.55 * tone)

    # Drums: kick on every beat, snare on 2 and 4, sixteenth hats; fills every 8th bar.
    if section >= 1 and section < 5 or (section == 5 and bar % 8 < 6):
        for b in range(4):
            place(drums, t0 + b * BEAT, 0.9 * K)
            if b in (1, 3):
                place(drums, t0 + b * BEAT, 0.55 * S)
        for s in range(16):
            place(drums, t0 + s * BEAT / 4, (0.22 if s % 2 else 0.12) * (HO if s == 14 else H))
        if bar % 8 == 7:
            for s in range(8, 16):
                place(drums, t0 + s * BEAT / 4, 0.3 * S * (0.5 + s / 32))
    elif section == 0 and bar >= 4:
        for s in range(16):
            place(drums, t0 + s * BEAT / 4, 0.12 * H)

    # Brass-like stabs: off-beat chord hits from the groove onward.
    if section >= 1:
        for hit in (1.5, 3.5) if section != 3 else (0.0, 1.5, 2.5, 3.5):
            n = int(0.22 * SR)
            chord = sum(saw(hz(root + 12 + iv), n, 0.004) for iv in (0, third, 7))
            chord = lowpass(chord, 2600) * env(n, 0.01, 0.12)
            place(stabs, t0 + hit * BEAT, 0.16 * chord)

    # Pad underneath everything for width.
    n = int(BAR * SR)
    padsig = sum(np.sin(2 * np.pi * hz(root + 12 + iv) * np.arange(n) / SR) for iv in (0, third, 7, 12))
    place(pad, t0, 0.05 * padsig * env(n, 0.3, 0.3))

    # Tremolo-picked twangy lead in the lead sections.
    if section in (2, 4):
        for start, deg, dur in MELODY[bar % 8]:
            n = int(dur * BEAT * SR)
            f = hz(62 + deg)
            t = np.arange(n) / SR
            tone = saw(f, n) * 0.6 + np.sin(2 * np.pi * f * t) * 0.6
            tone = lowpass(tone, 3200)
            trem = 0.55 + 0.45 * np.sign(np.sin(2 * np.pi * (BPM / 60 * 4) * t))
            vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t)
            tone = tone * trem * vib * env(n, 0.005, 0.06)
            place(lead, t0 + start * BEAT, 0.22 * tone)

# Simple slap-back echo on the lead, like a vintage amp.
delay = int(0.75 * BEAT * SR)
lead[delay:] += 0.35 * lead[:-delay]

mix = bass + drums + stabs + pad + lead
# Fade the last two bars.
fade = int(2 * BAR * SR)
end = int(BARS * BAR * SR)
mix[end - fade:end] *= np.linspace(1, 0, fade)
mix = mix[:end]
mix = np.tanh(1.3 * mix / np.max(np.abs(mix)))  # gentle saturation
mix /= np.max(np.abs(mix)) * 1.05
stereo = np.stack([mix, np.roll(mix, int(0.012 * SR)) * 0.97], axis=1)

out = Path(sys.argv[1] if len(sys.argv) > 1 else "App/Vesper/Resources/vesper_theme.m4a")
wav = out.with_suffix(".wav")
with wave.open(str(wav), "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes((stereo * 32767).astype("<i2").tobytes())
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "aac", "-b:a", "192k", str(out)], check=True)
wav.unlink()
print(f"wrote {out} ({end / SR:.1f}s @ {BPM} BPM)")
