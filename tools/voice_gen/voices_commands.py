#!/usr/bin/env python3
"""Voces de las órdenes a los aliados («todos conmigo», «todos libres», «atacad mi objetivo»).

Uso:
    pip install kokoro-onnx soundfile        # y ffmpeg en el sistema
    python3 tools/voice_gen/voices_commands.py MODELO.onnx VOCES.bin [id ...]

Escribe assets/voice/<id>.ogg (español, voz «em_alex») y assets/voice_en/<id>.ogg (inglés, voz
«am_michael»), con el mismo efecto de radio que el resto de voces del juego.
"""
import os
import subprocess
import sys
import tempfile

SPEED = 1.05
# id -> {idioma: (voz, código de idioma de Kokoro, texto)}
LINES = {
    "follow_on": {
        "es": ("em_alex", "es", "¡Todos conmigo! Recibido, os seguimos."),
        "en": ("am_michael", "en-us", "All units, on me! Roger, following you."),
    },
    "follow_off": {
        "es": ("em_alex", "es", "Todos libres. Actuad por vuestra cuenta."),
        "en": ("am_michael", "en-us", "All units, break off. Act at your discretion."),
    },
    "focus_fire": {
        "es": ("em_alex", "es", "¡Todos contra mi objetivo! ¡Fuego!"),
        "en": ("am_michael", "en-us", "All units, engage my target! Fire!"),
    },
    "focus_none": {
        "es": ("em_alex", "es", "Sin objetivo a la vista."),
        "en": ("am_michael", "en-us", "No target in sight."),
    },
}
OUT = {"es": "voice", "en": "voice_en"}

FILTER = (
    "[0]aresample=22050,highpass=f=350,lowpass=f=3000,acompressor=threshold=0.15:ratio=6:makeup=2,"
    "asoftclip=type=tanh,adelay=250[v];"
    "[1]aresample=22050,volume=0.06,afade=t=in:d=0.02,afade=t=out:st=0.1:d=0.05[b1];"
    "[2]aresample=22050,highpass=f=400,lowpass=f=3500,volume=0.08[n];"
    "[b1][v]concat=n=2:v=0:a=1[bv];[bv][n]amix=inputs=2:normalize=0:duration=first,"
    "apad=pad_dur=0.15,alimiter=limit=0.95"
)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    import soundfile as sf
    from kokoro_onnx import Kokoro

    kokoro = Kokoro(sys.argv[1], sys.argv[2])
    wanted = sys.argv[3:] or list(LINES)
    root = os.path.join(os.path.dirname(__file__), "..", "..", "assets")
    failed = []
    for key in wanted:
        for language, (voice, code, text) in LINES[key].items():
            out = os.path.join(root, OUT[language], key + ".ogg")
            try:
                samples, rate = kokoro.create(text, voice=voice, speed=SPEED, lang=code)
                with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                    wav = tmp.name
                sf.write(wav, samples, rate)
                subprocess.run(
                    ["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                     "-f", "lavfi", "-i", "sine=f=1200:d=0.15",
                     "-f", "lavfi", "-i", "anoisesrc=d=40:c=white:a=0.5",
                     "-filter_complex", FILTER, "-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "4", out],
                    check=True)
                os.unlink(wav)
                print("ok", language, key)
            except Exception as error:
                failed.append((language, key))
                print("FALLO", language, key, error)
    print("fallidas:", failed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
