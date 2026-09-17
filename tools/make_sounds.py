#!/usr/bin/python3
"""Generate the sounds, so the repository carries no opaque binaries.

An alert you dread is an alert you eventually mute, and a muted alert is worse
than none — so these are built to be noticed rather than to frighten. They are
struck tones, not beeps: a soft attack, partials that decay at different rates
the way a real bell or a wooden bar does, and consonant intervals. The reference
is a station or airport chime, which exists to make a room look up without
raising anybody's pulse.

Deliberately nothing like a siren. Outside is where sirens come from, and a
laptop that imitates one leaves you working out which you just heard.
"""
import argparse
import math
import pathlib
import struct
import wave

RATE = 48000

# ratio to the fundamental, its share of the loudness, how much faster it fades
VOICES = {
    # Warm and round, like a doorbell two rooms away.
    "bell":    [(1.0, 1.00, 1.0), (2.0, 0.50, 1.5), (3.0, 0.22, 2.1),
                (4.2, 0.10, 2.8), (5.4, 0.05, 3.4)],
    # Wooden and short, like a mallet on a bar. The gentlest of the three.
    "marimba": [(1.0, 1.00, 1.0), (3.9, 0.28, 2.2), (9.2, 0.07, 3.6)],
    # Glassy, with a long shimmer that fades on its own.
    "glass":   [(1.0, 1.00, 1.0), (2.7, 0.34, 1.3), (5.4, 0.14, 1.9),
                (8.1, 0.05, 2.6)],
}

DECAY = {"bell": 0.62, "marimba": 0.26, "glass": 1.15}


def struck(freq: float, voice: str, seconds: float, gain: float) -> list[float]:
    """One struck note: soft on, then left to ring."""
    partials = VOICES[voice]
    tau = DECAY[voice]
    attack = int(RATE * 0.009)          # gentle enough to have no click in it
    total = int(RATE * seconds)
    loudest = sum(a for _, a, _ in partials)

    out = []
    for i in range(total):
        t = i / RATE
        value = sum(
            amp * math.sin(2 * math.pi * freq * ratio * t) * math.exp(-t * fade / tau)
            for ratio, amp, fade in partials
        )
        value /= loudest
        if i < attack:
            value *= i / attack
        # Take the very end down to nothing so files can be concatenated cleanly.
        if i > total - attack:
            value *= (total - i) / attack
        out.append(value * gain)
    return out


def mix(layers: list[tuple[float, list[float]]]) -> list[float]:
    """Notes laid over one another at given offsets, so each rings on into the
    next instead of stopping dead when the next begins."""
    length = max(int(RATE * at) + len(samples) for at, samples in layers)
    out = [0.0] * length
    for at, samples in layers:
        start = int(RATE * at)
        for i, s in enumerate(samples):
            out[start + i] += s
    peak = max((abs(s) for s in out), default=1.0)
    return [s / peak * 0.72 for s in out] if peak > 0.72 else out


def write(path: pathlib.Path, samples: list[float]) -> None:
    with wave.open(str(path), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples))


# Rising, because rising asks a question and falling closes one. Kept inside a
# fourth: wide enough to be a signal, narrow enough not to be a fanfare.
ALERTS = {
    "bell":    [(0.00, 523.25, 2.2), (0.34, 698.46, 2.6)],
    "marimba": [(0.00, 587.33, 1.1), (0.16, 739.99, 1.1), (0.32, 880.00, 1.5)],
    "glass":   [(0.00, 880.00, 3.0), (0.46, 880.00, 3.0)],
}

CLEARS = {
    "bell":    [(0.00, 698.46, 2.4), (0.34, 523.25, 2.8)],
    "marimba": [(0.00, 880.00, 1.1), (0.16, 739.99, 1.1), (0.32, 587.33, 1.5)],
    "glass":   [(0.00, 880.00, 2.6), (0.40, 659.25, 3.0)],
}


def build(voice: str, plan: list[tuple[float, float, float]], gain: float) -> list[float]:
    return mix([(at, struck(freq, voice, length, gain)) for at, freq, length in plan])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--voice", default="all", choices=[*VOICES, "all"])
    args = parser.parse_args()

    out = pathlib.Path(__file__).resolve().parent.parent / "assets"
    out.mkdir(exist_ok=True)
    voices = list(VOICES) if args.voice == "all" else [args.voice]

    for voice in voices:
        for kind, plans, gain in (("alert", ALERTS, 0.62), ("clear", CLEARS, 0.40)):
            samples = build(voice, plans[voice], gain)
            path = out / f"{kind}-{voice}.wav"
            write(path, samples)
            print(f"  {path.name:<20} {len(samples) / RATE:.2f}s  "
                  f"{path.stat().st_size / 1024:>4.0f} KB")


if __name__ == "__main__":
    main()
