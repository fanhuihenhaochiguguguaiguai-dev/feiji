"""Bake the official V18 oscillator and filtered-noise envelopes to native WAV."""
import math
import random
import wave
from array import array
from pathlib import Path

RATE = 24000
DESTINATION = Path(__file__).resolve().parents[1] / "assets" / "audio"
RANDOM = random.Random(18)
IMPULSES = {
    "gun": (0.11, 960, 240, 0.20), "missile": (0.48, 1900, 115, 0.45),
    "blast": (1.06, 440, 52, 0.55), "scrape": (0.18, 2800, 610, 0.28),
    "fracture": (1.70, 610, 38, 0.65), "water": (0.66, 1450, 330, 0.37),
    "counter": (0.35, 2100, 360, 0.26),
}
TONES = {
    "victory": (440, 550, 660, 880), "lock": (620, 880),
    "warn": (780, 590, 780), "wave": (430, 530),
}

def triangle(phase):
    return 1 - 4 * abs((phase % 1) - 0.5)

def write(name, values):
    with wave.open(str(DESTINATION / (name + ".wav")), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", ""))
        output.writeframes(array("h", (round(max(-1, min(1, x)) * 32767) for x in values)).tobytes())

def impulse(name, duration, start, end, amp):
    last = slow = dc = 0.0
    values = []
    for sample in range(round(RATE * duration)):
        t = sample / RATE / duration
        hz = start * (end / start) ** t
        last = last * 0.64 + (RANDOM.random() - 0.5) * 0.91
        slow += (last - slow) * (1 - math.exp(-math.tau * hz / RATE))
        dc += (slow - dc) * (1 - math.exp(-math.tau * hz * 0.38 / RATE))
        filtered = slow - dc if name in {"gun", "water", "scrape"} else slow
        values.append(filtered * 2.1 * amp * (0.0001 / amp) ** t)
    return values

def cue(notes):
    decay = 0.22
    values = [0.0] * round(RATE * (len(notes) * 0.096 + decay))
    for index, hz in enumerate(notes):
        start = round(index * 0.096 * RATE)
        for sample in range(round(decay * RATE)):
            t = sample / RATE
            gain = 0.13 * t / 0.015 if t <= 0.015 else 0.13 * (0.0001 / 0.13) ** ((t - 0.015) / (decay - 0.015))
            values[start + sample] += triangle(t * hz) * gain
    return values

DESTINATION.mkdir(parents=True, exist_ok=True)
for key, args in IMPULSES.items():
    write(key, impulse(key, *args))
for key, notes in TONES.items():
    write(key, cue(notes))
write("engine", (triangle(t * 64 / RATE) * 0.25 + triangle(t * 53 / RATE) * 0.08 for t in range(RATE)))
last = 0.0
wind = []
for n in range(2 * RATE):
    last = last * 0.78 + (RANDOM.random() - 0.5) * 0.34
    wind.append(last * min(1.0, n / 150.0, (2 * RATE - n) / 150.0))
write("wind", wind)
