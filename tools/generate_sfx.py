"""Generate the game's sound effects as small 16-bit mono WAVs.

No external assets / libraries needed (stdlib only). Re-run after tweaking:
    python tools/generate_sfx.py
Outputs into ../audio relative to this file.
"""
import math
import os
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


if __name__ == "__main__":
    write_wav("engine.wav", engine())
    write_wav("checkpoint.wav", ding())
    write_wav("finish.wav", fanfare())
    write_wav("beep.wav", beep())
    write_wav("go.wav", go_tone())
