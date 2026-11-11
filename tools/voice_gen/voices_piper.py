#!/usr/bin/env python3
"""Voces en alemán y ruso con modelos Piper (VITS) y sherpa-onnx. ALTERNATIVA: YA NO SE USA.

Las voces de alemán y ruso que lleva el juego se generan ahora con Supertonic 3 (voices_supertonic.py)
porque se entienden mejor con el efecto de radio (comprobado con check_voices.py). Este guion se
conserva por si hiciera falta volver a Piper: sus modelos tienen conjuntos de datos CC0 (ver el
MODEL_CARD de cada uno) y no obligan a avisar de que la voz es sintética.

Indonesio: el modelo Piper id_ID-news_tts NO se usa. Su ficha oficial es errónea (apunta a un
conjunto de datos de malayalam), pero el conjunto del que toma el nombre, INDspeech_NEWS_TTS, se
publica con licencia CC BY-NC-SA 4.0 (solo uso no comercial). Las voces indonesias se generan con
Supertonic 3: ver voices_supertonic.py.

Uso:
    pip install "sherpa-onnx<2" soundfile    # (la 2.x quitó espeak) y ffmpeg en el sistema
    # modelos de https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models, descomprimidos en CARPETA:
    #   vits-piper-de_DE-thorsten-high, vits-piper-de_DE-thorsten_emotional-medium,
    #   vits-piper-ru_RU-denis-medium, vits-piper-ru_RU-dmitri-medium
    python3 tools/voice_gen/voices_piper.py CARPETA CODIGO [id ...]

Los textos están en lines/<codigo>.txt; escribe assets/voice_<codigo>/ con el mismo efecto de radio
que el resto de voces (ver voices_lang.py).
"""
import glob
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from voices_lang import CREW, FILTER, load_lines  # noqa: E402

# código -> (modelo de la tripulación, modelo de la radio, velocidad)
MODELS = {
    "de": ("vits-piper-de_DE-thorsten-high", "vits-piper-de_DE-thorsten_emotional-medium", 1.0),
    "ru": ("vits-piper-ru_RU-denis-medium", "vits-piper-ru_RU-dmitri-medium", 1.0),
}


def load_tts(folder: str, name: str):
    import sherpa_onnx
    path = os.path.join(folder, name)
    model = glob.glob(os.path.join(path, "*.onnx"))[0]
    vits = sherpa_onnx.OfflineTtsVitsModelConfig(
        model=model, tokens=os.path.join(path, "tokens.txt"), data_dir=os.path.join(path, "espeak-ng-data"))
    config = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(vits=vits, num_threads=2))
    return sherpa_onnx.OfflineTts(config)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    import numpy as np
    import soundfile as sf

    folder, code = sys.argv[1], sys.argv[2]
    lines = load_lines(code)
    crew_name, radio_name, speed = MODELS[code]
    engines = {crew_name: load_tts(folder, crew_name)}
    if radio_name not in engines:
        engines[radio_name] = load_tts(folder, radio_name)
    wanted = sys.argv[3:] or list(lines)
    root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "voice_" + code)
    os.makedirs(os.path.join(root, "tutorial"), exist_ok=True)
    failed = []
    for key in wanted:
        tts = engines[crew_name if key in CREW else radio_name]
        out = os.path.join(root, "tutorial", key + ".ogg") if key.startswith("tut_") else os.path.join(root, key + ".ogg")
        try:
            audio = tts.generate(lines[key], sid=0, speed=speed)
            samples = np.array(audio.samples, dtype=np.float32)
            if samples.size == 0:
                raise RuntimeError("audio vacío")
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                wav = tmp.name
            sf.write(wav, samples, audio.sample_rate)
            subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                 "-f", "lavfi", "-i", "sine=f=1200:d=0.15",
                 "-f", "lavfi", "-i", "anoisesrc=d=40:c=white:a=0.5",
                 "-filter_complex", FILTER, "-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "4", out],
                check=True)
            os.unlink(wav)
            print("ok", key, flush=True)
        except Exception as error:
            failed.append(key)
            print("FALLO", key, error, flush=True)
    print(f"{len(wanted) - len(failed)} generadas, {len(failed)} fallidas: {failed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
