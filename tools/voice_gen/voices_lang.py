#!/usr/bin/env python3
"""Voces del juego en otros idiomas (tripulación, radio, tutorial y órdenes) con Kokoro TTS.

Uso:
    pip install kokoro-onnx soundfile        # y ffmpeg en el sistema (japonés: pip install "misaki[ja]")
    python3 tools/voice_gen/voices_lang.py MODELO.onnx VOCES.bin CODIGO [id ...]

CODIGO es el del idioma (fr, it, ja, pt, hi...). Los textos están en lines/<codigo>.txt (una
línea «id|texto»; los ids de la tripulación son los de VoiceManager.EVENTS y los del tutorial,
tut_<id> de STEPS). Escribe assets/voice_<codigo>/<id>.ogg y assets/voice_<codigo>/tutorial/tut_<id>.ogg
con el mismo efecto de radio que el resto de voces. Si falta un clip, el juego usa el español.
"""
import os
import subprocess
import sys
import tempfile

# código -> (voz de tripulación, voz de radio); cada voz es (nombre en Kokoro, idioma de fonemas).
VOICES = {
    "fr": (("ff_siwis", "fr-fr"), ("ff_siwis", "fr-fr")),
    "it": (("im_nicola", "it"), ("if_sara", "it")),
    "ja": (("jm_kumo", "ja"), ("jf_alpha", "ja")),
    "pt": (("pm_alex", "pt-br"), ("pm_santa", "pt-br")),
    "hi": (("hm_omega", "hi"), ("hf_alpha", "hi")),
}
SPEED = {"ja": 1.0, "hi": 1.0}
# Eventos que dice la tripulación dentro del tanque; el resto, la radio de la base.
CREW = {
    "armor_low", "bonus", "cease_fire", "hit_1", "hit_2", "kill_1", "kill_2", "kill_3", "locked",
    "missile", "pickup", "radar_1", "radar_2", "shot_down_1", "shot_down_2",
    "follow_on", "follow_off", "focus_fire", "focus_none",
}

FILTER = (
    "[0]aresample=22050,highpass=f=350,lowpass=f=3000,acompressor=threshold=0.15:ratio=6:makeup=2,"
    "asoftclip=type=tanh,adelay=250[v];"
    "[1]aresample=22050,volume=0.06,afade=t=in:d=0.02,afade=t=out:st=0.1:d=0.05[b1];"
    "[2]aresample=22050,highpass=f=400,lowpass=f=3500,volume=0.08[n];"
    "[b1][v]concat=n=2:v=0:a=1[bv];[bv][n]amix=inputs=2:normalize=0:duration=first,"
    "apad=pad_dur=0.15,alimiter=limit=0.95"
)


def load_lines(code: str) -> dict:
    lines = {}
    path = os.path.join(os.path.dirname(__file__), "lines", code + ".txt")
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            raw = raw.strip()
            if raw:
                key, text = raw.split("|", 1)
                lines[key] = text
    return lines


def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    import soundfile as sf
    from kokoro_onnx import Kokoro

    code = sys.argv[3]
    lines = load_lines(code)
    kokoro = Kokoro(sys.argv[1], sys.argv[2])
    g2p = None
    if code == "ja":
        from misaki import ja
        g2p = ja.JAG2P()
    wanted = sys.argv[4:] or list(lines)
    root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "voice_" + code)
    os.makedirs(os.path.join(root, "tutorial"), exist_ok=True)
    failed = []
    for key in wanted:
        crew, radio = VOICES[code]
        voice, lang = crew if key in CREW else radio
        out = os.path.join(root, "tutorial", key + ".ogg") if key.startswith("tut_") else os.path.join(root, key + ".ogg")
        try:
            text = lines[key]
            if g2p is not None:
                samples, rate = kokoro.create(g2p(text), voice=voice, speed=SPEED.get(code, 1.05), lang=lang, is_phonemes=True)
            else:
                samples, rate = kokoro.create(text, voice=voice, speed=SPEED.get(code, 1.05), lang=lang)
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
            print("ok", key, flush=True)
        except Exception as error:  # una frase que falla no detiene el resto
            failed.append(key)
            print("FALLO", key, error, flush=True)
    print(f"{len(wanted) - len(failed)} generadas, {len(failed)} fallidas: {failed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
