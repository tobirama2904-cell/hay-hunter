#!/usr/bin/env python3
"""Генератор звуков Hay Hunter — чистый stdlib, без внешних библиотек."""
import math, os, random, struct, wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sounds")
os.makedirs(OUT, exist_ok=True)
random.seed(7)


def save(name, samples):
    path = os.path.join(OUT, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        data = b"".join(struct.pack("<h", max(-32000, min(32000, int(s * 32000)))) for s in samples)
        w.writeframes(data)
    print("  ", name, f"{len(samples)/SR:.2f}s")


def noise(n):
    return [random.uniform(-1, 1) for _ in range(n)]


def lowpass(sig, a):
    out, y = [], 0.0
    for x in sig:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(sig, a):
    out, y, py = [], 0.0, 0.0
    for x in sig:
        y = a * (y + x - py)
        py = x
        out.append(y)
    return out


def env_exp(n, attack=0.01, decay=3.0):
    return [min(1.0, (i / SR) / attack if attack > 0 else 1.0) * math.exp(-decay * i / SR) for i in range(n)]


def sine(n, f, phase=0.0):
    return [math.sin(2 * math.pi * f * i / SR + phase) for i in range(n)]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, v in enumerate(t):
            out[i] += v
    return out


def scale(sig, k):
    return [s * k for s in sig]


def ms(v):
    return int(SR * v / 1000.0)


def rustle(dur=0.45, bright=0.5):
    n = ms(dur * 1000)
    base = lowpass(highpass(noise(n), 0.25), 0.35 + bright * 0.3)
    return [b * en * 0.9 for b, en in zip(base, env_exp(n, 0.004, 6.0))]


save("rustle.wav", rustle(0.4, 0.6))
save("rustle2.wav", rustle(0.75, 0.3))

n = ms(420)
s = mix(scale(rustle(0.42, 0.7), 0.8), scale(lowpass(noise(n), 0.08), 0.5))
save("scoop.wav", [v * e for v, e in zip(s, env_exp(len(s), 0.002, 5.0))])

n = ms(220)
save("dig_hit.wav", [math.sin(2 * math.pi * 90 * i / SR) * math.exp(-18 * i / SR) * 0.9 for i in range(n)])

n = ms(110)
b = mix(scale(sine(n, 1500), 0.55), scale(sine(n, 3000), 0.15))
save("beep.wav", [v * e for v, e in zip(b, env_exp(n, 0.003, 16.0))])

n = ms(700)
c = mix(scale(sine(n, 880), 0.45),
        scale(sine(ms(400), 1318), 0.4) + [0.0] * (n - ms(400)),
        scale(sine(ms(250), 1760), 0.3) + [0.0] * (n - ms(250)))
save("sell.wav", [v * e * 0.8 for v, e in zip(c, env_exp(n, 0.004, 4.5))])

n = ms(300)
click = mix(scale(rustle(0.05, 1.0), 0.7) + [0.0] * (n - ms(50)), scale(sine(n, 1046), 0.3))
save("buy.wav", [v * e for v, e in zip(click, env_exp(n, 0.002, 9.0))])

n = ms(900)
found = [0.0] * n
for off, f in [(0, 659), (ms(140), 880), (ms(300), 1318)]:
    tone = sine(n - off, f)
    for i, v in enumerate(tone):
        found[off + i] += v * math.exp(-5.0 * i / SR) * 0.42
save("found.wav", found)

n = ms(160)
step = mix(scale(lowpass(noise(n), 0.12), 0.55), scale(sine(n, 130), 0.25))
save("step.wav", [v * e for v, e in zip(step, env_exp(n, 0.004, 22.0))])

n = ms(6000)
hum = mix(scale(lowpass(noise(n), 0.02), 0.5), scale(sine(n, 58), 0.10), scale(sine(n, 116), 0.05))
fade = ms(300)
for i in range(fade):
    k = i / fade
    hum[i] *= k
    hum[n - 1 - i] *= k
save("ambient.wav", [h * 0.5 for h in hum])
print("готово ->", os.path.abspath(OUT))
