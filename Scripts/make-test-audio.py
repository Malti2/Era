#!/usr/bin/env python3
"""Writes two short sine-wave WAVs plus a non-audio file into testaudio/ for the import test."""
import math
import os
import struct
import wave

os.makedirs("testaudio", exist_ok=True)
for name, freq in [("Testton Alpha", 440), ("Testton Beta", 523)]:
    with wave.open(f"testaudio/{name}.wav", "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(b"".join(
            struct.pack("<h", int(10000 * math.sin(2 * math.pi * freq * i / 44100)))
            for i in range(44100 * 3)
        ))
with open("testaudio/Notiz.txt", "w") as f:
    f.write("keine Audiodatei")
