#!/usr/bin/env python3
"""Convierte un tramo estable de una grabación real en un bucle sin costura (no va en el APK).

Uso: real_loop.py ENTRADA SALIDA.wav INICIO DURACIÓN [FUNDIDO=1.0] [PICO_DB=-3] [FILTRO_FFMPEG]
Toma [INICIO, INICIO+DURACIÓN+FUNDIDO] de la grabación y funde su cola con su principio
(fundido de igual potencia), así el final enlaza con el comienzo. Escribe WAV mono a 22 050 Hz
y su .import en bucle.
"""
import hashlib, os, subprocess, sys, wave
import numpy as np

SR = 22050
src, out, start, length = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
fade = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0
peak_db = float(sys.argv[6]) if len(sys.argv) > 6 else -3.0
# Filtro extra (p. ej. realce de medios: el altavoz de un móvil apenas da graves).
extra = "," + sys.argv[7] if len(sys.argv) > 7 else ""
raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-ss", str(start), "-t", str(length + fade), "-i", src,
                      "-ac", "1", "-ar", str(SR), "-af", "highpass=f=45" + extra, "-f", "f32le", "-"], capture_output=True, check=True).stdout
x = np.frombuffer(raw, dtype=np.float32).astype(np.float64)
n, f = int(length * SR), int(fade * SR)
x = x[: n + f]
t = np.linspace(0.0, np.pi / 2.0, f)
loop = x[:n].copy()
loop[:f] = x[:f] * np.sin(t) + x[n:n + f] * np.cos(t)
loop *= 10 ** (peak_db / 20.0) / max(np.abs(loop).max(), 1e-9)
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((loop * 32767).astype("<i2").tobytes())
name = os.path.basename(out)
res = "res://assets/audio/" + name
digest = hashlib.md5(res.encode()).hexdigest()
imp = out + ".import"
uid = ""
if os.path.exists(imp):
    for line in open(imp):
        if line.startswith("uid="):
            uid = line
with open(imp, "w") as fh:
    fh.write(f'[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n{uid}path="res://.godot/imported/{name}-{digest}.sample"\n\n[deps]\n\n'
             f'source_file="{res}"\ndest_files=["res://.godot/imported/{name}-{digest}.sample"]\n\n[params]\n\n'
             "force/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\n"
             "edit/normalize=false\nedit/loop_mode=2\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=2\n")
print(f"{out}: {length:.1f} s, pico {peak_db} dB")
