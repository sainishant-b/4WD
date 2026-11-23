"""Generate the game's sound effects as small 16-bit mono WAVs.

No external assets / libraries needed (stdlib only). Re-run after tweaking:
    python tools/generate_sfx.py
Outputs into ../audio relative to this file.
"""
import math
import os
import random
import struct
import wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "audio")


def write_wav(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack("<h", int(v * 32767))
        w.writeframes(bytes(frames))
    print("wrote", path, "(%.2fs)" % (len(samples) / RATE))


def sawtooth(t, f):
    return 2.0 * (t * f - math.floor(0.5 + t * f))


def engine():
    # 1.000s at base 70 Hz => exactly 70 periods, so it loops seamlessly.
    dur = 1.0
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        # A couple of detuned saws = a low, gritty idle hum.
        v = 0.55 * sawtooth(t, 70.0) + 0.30 * sawtooth(t, 105.0) + 0.15 * sawtooth(t, 140.0)
        out.append(v * 0.28)
    return out


def ding():
    # Short bright two-note chime with a quick exponential decay.
    dur = 0.20
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 16.0)
        v = math.sin(2 * math.pi * 988.0 * t) + 0.6 * math.sin(2 * math.pi * 1319.0 * t)
        out.append(v * env * 0.4)
    return out


def fanfare():
    # Ascending arpeggio for the finish.
    notes = [523.25, 659.25, 783.99, 1046.5]
    seg = 0.14
    out = []
    for idx, f in enumerate(notes):
        n = int(RATE * seg)
        for i in range(n):
            t = i / RATE
            env = math.exp(-t * 6.0) * min(1.0, t * 40.0)
            v = math.sin(2 * math.pi * f * t) + 0.4 * math.sin(2 * math.pi * f * 2 * t)
            out.append(v * env * 0.35)
    return out


def beep():
    # Short countdown tick.
    dur = 0.09
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 22.0)
        out.append(math.sin(2 * math.pi * 660.0 * t) * env * 0.4)
    return out


def go_tone():
    # Brighter, slightly longer "GO!" tone.
    dur = 0.30
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = math.exp(-t * 5.0) * min(1.0, t * 60.0)
        v = math.sin(2 * math.pi * 990.0 * t) + 0.4 * math.sin(2 * math.pi * 1980.0 * t)
        out.append(v * env * 0.4)
    return out


def _noise(seed):
    rng = random.Random(seed)
    return lambda: rng.uniform(-1.0, 1.0)


def boost():
    # Boost pad whoosh: noise swept open (a one-pole low-pass rising) under a
    # sine sliding up, 0.7 s.
    dur = 0.7
    n = int(RATE * dur)
    noise = _noise(1)
    lp = 0.0
    phase = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        k = t / dur
        a = 0.04 + 0.4 * k
        lp += a * (noise() - lp)
        f = 180.0 + 760.0 * k * k
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t * 30.0) * (1.0 - k) ** 1.4
        out.append((lp * 1.6 + 0.3 * math.sin(phase)) * env * 0.55)
    return out


def crash():
    # A counted wall hit: a low thud falling in pitch, a burst of grit and a
    # metallic clank (inharmonic partials), 0.6 s.
    dur = 0.6
    n = int(RATE * dur)
    noise = _noise(2)
    lp = 0.0
    phase = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        f = 45.0 + 60.0 * math.exp(-t * 8.0)
        phase += 2 * math.pi * f / RATE
        thud = math.sin(phase) * math.exp(-t * 7.0)
        lp += 0.35 * (noise() - lp)
        grit = lp * math.exp(-t * 13.0) * 1.6
        clank = sum(math.sin(2 * math.pi * fr * t) for fr in (1730.0, 2410.0, 3170.0)) * math.exp(-t * 11.0) * 0.12
        out.append((thud * 0.8 + grit + clank) * min(1.0, t * 400.0) * 0.6)
    return out


def scrape():
    # Grinding along a wall: gritty noise, pulsing 24 times a second, 0.5 s
    # (a whole number of pulses, so it loops).
    dur = 0.5
    n = int(RATE * dur)
    noise = _noise(3)
    lp = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        lp += 0.3 * (noise() - lp)
        hiss = noise() * 0.25
        pulse = 0.65 + 0.35 * math.sin(2 * math.pi * 24.0 * t)
        out.append((lp * 1.4 + hiss) * pulse * 0.4)
    return out


def jump():
    # Take-off (the dormant obstacle ramps' hop): a rising swoop, 0.4 s.
    dur = 0.4
    n = int(RATE * dur)
    noise = _noise(4)
    lp = 0.0
    phase = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        k = t / dur
        f = 220.0 + 700.0 * k
        phase += 2 * math.pi * f / RATE
        lp += (0.05 + 0.3 * k) * (noise() - lp)
        env = min(1.0, t * 25.0) * (1.0 - k)
        out.append((0.45 * math.sin(phase) + lp) * env * 0.5)
    return out


def land():
    # Touching down: a short thump, 0.3 s.
    dur = 0.3
    n = int(RATE * dur)
    noise = _noise(5)
    lp = 0.0
    phase = 0.0
    out = []
    for i in range(n):
        t = i / RATE
        f = 50.0 + 70.0 * math.exp(-t * 18.0)
        phase += 2 * math.pi * f / RATE
        lp += 0.25 * (noise() - lp)
        v = math.sin(phase) * math.exp(-t * 12.0) + lp * math.exp(-t * 28.0) * 1.5
        out.append(v * min(1.0, t * 500.0) * 0.6)
    return out


if __name__ == "__main__":
    write_wav("engine.wav", engine())
    write_wav("checkpoint.wav", ding())
    write_wav("finish.wav", fanfare())
    write_wav("beep.wav", beep())
    write_wav("go.wav", go_tone())
    write_wav("boost.wav", boost())
    write_wav("crash.wav", crash())
    write_wav("scrape.wav", scrape())
    write_wav("jump.wav", jump())
    write_wav("land.wav", land())
