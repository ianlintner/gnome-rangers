#!/usr/bin/env python3
"""Synthesise the placeholder forest ambient loop (soft wind through leaves).

Stdlib only. Writes a seamless 12 s mono 22.05 kHz WAV: low-passed noise with slow gust
modulation, plus a faint higher "leaf rustle" band. The result is original work (CC-BY-4.0 like
the other generated assets). Replace with a CC0 recording later; the level only references the
file path through `AmbientLoop` in the scene.

Usage: tools/audio/make_ambient_loop.py [out.wav]
"""
from __future__ import annotations

import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 22050
SECONDS = 12
FADE = RATE  # one second of equal-power crossfade makes the loop seamless


def synthesise(seed: int = 7) -> list[float]:
    rng = random.Random(seed)
    total = RATE * (SECONDS + 1)
    low = rustle = 0.0
    out: list[float] = []
    for n in range(total):
        white = rng.uniform(-1.0, 1.0)
        low += 0.012 * (white - low)  # slow low-pass: the wind body
        rustle += 0.25 * (white - rustle)  # brighter band: leaves
        t = n / RATE
        gust = 0.55 + 0.45 * math.sin(2 * math.pi * t / 6.0) * math.sin(2 * math.pi * t / 4.0 + 1.0)
        out.append(low * 9.0 * gust + (white - rustle) * 0.05 * gust**2)
    # Equal-power crossfade of the tail into the head so the loop point is silent.
    body = out[: RATE * SECONDS]
    tail = out[RATE * SECONDS :]
    for i in range(min(FADE, len(tail))):
        k = i / FADE
        body[i] = body[i] * math.sin(k * math.pi / 2) + tail[i] * math.cos(k * math.pi / 2)
    peak = max(abs(s) for s in body) or 1.0
    return [s / peak * 0.5 for s in body]


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("assets/audio/forest_ambient_loop.wav")
    out.parent.mkdir(parents=True, exist_ok=True)
    samples = synthesise()
    with wave.open(str(out), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in samples))
    print(f"wrote {out} ({out.stat().st_size // 1024} KiB, {SECONDS} s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
