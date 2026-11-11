#!/usr/bin/env python3
"""Voces del juego en indonesio, alemán y ruso con Supertonic 3 (Supertone Inc.) y sherpa-onnx.

Kokoro no habla ninguno de los tres. Para el indonesio no hay otra voz que se pueda usar en un juego
comercial (la de Piper, id_ID-news_tts, toma su nombre de un conjunto de datos CC BY-NC-SA, solo
para uso no comercial; ver voices_piper.py). En alemán y ruso las voces de Piper valen por licencia,
pero con el efecto de radio se entienden peor: al transcribirlas con Whisper y compararlas con el
texto (misma medida para los dos motores; 1 = se oye lo escrito), el ruso sacó de media 0,76 con
Piper y 0,92 con Supertonic, y el alemán 0,88 y 0,94. Ver check_voices.py.

El modelo se publica con la licencia BigScience Open RAIL-M: uso libre de regalías, sin reclamar
derechos sobre el audio generado, con restricciones de uso (no suplantar a nadie, no desinformar...)
y la obligación de AVISAR de que el contenido está generado por una máquina. El aviso de que las
voces son sintéticas va en la ficha de Play Store: ver store/aviso_voces_ia.md.

Uso:
    pip install "sherpa-onnx>=1.13,<2" soundfile     # probado con la 1.13.8; y ffmpeg en el sistema
    # modelo de https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models, descomprimido en CARPETA:
    #   sherpa-onnx-supertonic-3-tts-int8-2026-05-11
    python3 tools/voice_gen/voices_supertonic.py CARPETA CODIGO [id ...]

Los textos están en lines/<codigo>.txt; escribe assets/voice_<codigo>/ con el mismo efecto de radio
que el resto de voces (ver voices_lang.py).
"""
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(__file__))
from voices_lang import CREW, FILTER, load_lines  # noqa: E402

MODEL = "sherpa-onnx-supertonic-3-tts-int8-2026-05-11"
# Las diez voces van por orden alfabético: 0-4 = F1..F5 (mujer), 5-9 = M1..M5 (hombre).
# código -> (voz de la tripulación, voz de la radio, velocidad)
VOICES = {
    # M3 (voz de hombre firme, con autoridad) y F3 (locutora clara, de estilo informativo)
    "id": (7, 2, 1.05),
    "ru": (7, 2, 1.05),
    "de": (7, 2, 1.05),
}
STEPS = 16


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    import numpy as np
    import sherpa_onnx
    import soundfile as sf

    folder, code = os.path.join(sys.argv[1], MODEL), sys.argv[2]
    lines = load_lines(code)
    crew_sid, radio_sid, speed = VOICES[code]
    config = sherpa_onnx.OfflineTtsConfig(model=sherpa_onnx.OfflineTtsModelConfig(
        supertonic=sherpa_onnx.OfflineTtsSupertonicModelConfig(
            duration_predictor=os.path.join(folder, "duration_predictor.int8.onnx"),
            text_encoder=os.path.join(folder, "text_encoder.int8.onnx"),
            vector_estimator=os.path.join(folder, "vector_estimator.int8.onnx"),
            vocoder=os.path.join(folder, "vocoder.int8.onnx"),
            tts_json=os.path.join(folder, "tts.json"),
            unicode_indexer=os.path.join(folder, "unicode_indexer.bin"),
            voice_style=os.path.join(folder, "voice.bin")),
        num_threads=2, provider="cpu"))
    if not config.validate():
        print("Configuración no válida: revisa la carpeta del modelo")
        return 1
    tts = sherpa_onnx.OfflineTts(config)
    wanted = sys.argv[3:] or list(lines)
    root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "voice_" + code)
    os.makedirs(os.path.join(root, "tutorial"), exist_ok=True)
    failed = []
    for key in wanted:
        out = os.path.join(root, "tutorial", key + ".ogg") if key.startswith("tut_") else os.path.join(root, key + ".ogg")
        try:
            generation = sherpa_onnx.GenerationConfig()
            generation.sid = crew_sid if key in CREW else radio_sid
            generation.num_steps = STEPS
            generation.speed = speed
            # Ojo: hay que asignar el diccionario entero; `generation.extra["lang"] = ...` no hace nada
            # (devuelve una copia) y el modelo leería el texto como si fuera inglés.
            generation.extra = {"lang": code}
            audio = tts.generate(lines[key], generation)
            samples = np.array(audio.samples, dtype=np.float32)
            if samples.size == 0:
                raise RuntimeError("audio vacío")
            # Supertonic sale más bajo que Kokoro: se lleva el pico a 0,85 para igualar el volumen.
            samples = samples / max(1e-6, float(np.abs(samples).max())) * 0.85
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
