#!/usr/bin/env python3
"""Comprueba las voces de un idioma «de ida y vuelta»: las transcribe con Whisper y compara lo oído
con el texto de lines/<codigo>.txt. Sirve para cazar frases mal pronunciadas sin saber el idioma
(así se vio que el japonés leía «一機» como «ichi ki» y que el ruso de Piper se entendía peor).

No sustituye a un oído nativo: mide si se entiende, no si suena natural. En frases de una o dos
palabras el reconocedor falla a veces aunque la voz esté bien.

Uso:
    pip install onnxruntime kaldi-native-fbank soundfile numpy       # y ffmpeg en el sistema
    # modelo: https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-turbo.tar.bz2
    python3 tools/voice_gen/check_voices.py CARPETA_WHISPER CODIGO [id ...]

CODIGO es el del juego (fr, it, ja, pt, id, hi, de, ru). Escribe la nota de cada frase (1.00 = lo
oído coincide con el texto), la media y las frases con peor nota junto a lo que se entendió.

Whisper se decodifica aquí a mano (y no con el reconocedor de sherpa-onnx) porque hay que juntar
los bytes de todos los tokens antes de pasarlos a texto: en hindi y japonés una letra ocupa varios
tokens y, si se convierten uno a uno, se pierden.
"""
import base64
import os
import subprocess
import sys
import tempfile
import unicodedata
from difflib import SequenceMatcher

# Idiomas en los que se compara letra a letra (sin espacios fiables o con varias grafías válidas).
BY_CHARACTER = {"ja", "hi"}


class Whisper:
    def __init__(self, folder: str) -> None:
        import onnxruntime as ort

        options = ort.SessionOptions()
        options.inter_op_num_threads = 1
        options.intra_op_num_threads = 2
        self.encoder = ort.InferenceSession(
            os.path.join(folder, "turbo-encoder.int8.onnx"), sess_options=options, providers=["CPUExecutionProvider"])
        self.decoder = ort.InferenceSession(
            os.path.join(folder, "turbo-decoder.int8.onnx"), sess_options=options, providers=["CPUExecutionProvider"])
        meta = self.encoder.get_modelmeta().custom_metadata_map
        self.layers = int(meta["n_text_layer"])
        self.context = int(meta["n_text_ctx"])
        self.state = int(meta["n_text_state"])
        self.mels = int(meta["n_mels"])
        self.sot = int(meta["sot"])
        self.eot = int(meta["eot"])
        self.blank = int(meta["blank_id"])
        self.banned = [int(meta[key]) for key in ("no_timestamps", "sot", "no_speech", "translate")]
        self.start = list(map(int, meta["sot_sequence"].split(","))) + [int(meta["no_timestamps"])]
        self.languages = dict(zip(meta["all_language_codes"].split(","), map(int, meta["all_language_tokens"].split(","))))
        self.table = {}
        with open(os.path.join(folder, "turbo-tokens.txt"), encoding="utf-8") as handle:
            for line in handle:
                token, index = line.split()
                self.table[int(index)] = token

    def _features(self, wave):
        import kaldi_native_fbank as knf
        import numpy as np

        options = knf.WhisperFeatureOptions()
        options.dim = self.mels
        bank = knf.OnlineWhisperFbank(options)
        bank.accept_waveform(16000, wave)
        bank.input_finished()
        frames = np.stack([bank.get_frame(i) for i in range(bank.num_frames_ready)])
        log = np.log10(np.maximum(frames, 1e-10))
        log = np.maximum(log, log.max() - 8.0)
        mel = np.pad((log + 4.0) / 4.0, ((0, 1000), (0, 0)))  # 10 s de silencio al final, para que cierre la frase
        return mel.T[None].astype(np.float32)

    def transcribe(self, wave, language: str) -> str:
        import numpy as np

        cross_k, cross_v = self.encoder.run(None, {self.encoder.get_inputs()[0].name: self._features(wave)})
        self_k = np.zeros((self.layers, 1, self.context, self.state), dtype=np.float32)
        self_v = self_k.copy()
        names = [item.name for item in self.decoder.get_inputs()]
        prompt = list(self.start)
        prompt[1] = self.languages[language]

        def step(tokens, offset, keys, values):
            out = self.decoder.run(None, {
                names[0]: np.array([tokens], dtype=np.int64), names[1]: keys, names[2]: values,
                names[3]: cross_k, names[4]: cross_v, names[5]: np.array([offset], dtype=np.int64)})
            logits = out[0][0, -1]
            logits[self.banned] = -np.inf
            return logits, out[1], out[2]

        logits, self_k, self_v = step(prompt, 0, self_k, self_v)
        logits[[self.eot, self.blank]] = -np.inf
        offset = len(prompt)
        token = int(logits.argmax())
        result = []
        while token != self.eot and len(result) < 200:
            result.append(token)
            logits, self_k, self_v = step([token], offset, self_k, self_v)
            offset += 1
            token = int(logits.argmax())
        raw = b"".join(base64.b64decode(self.table[index]) for index in result if index in self.table)
        return raw.decode("utf-8", errors="replace").strip()


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKC", text).lower().replace("ё", "е")
    kept = "".join(char if (unicodedata.category(char)[0] in "LMN" or char.isspace()) else " " for char in text)
    return " ".join(kept.split())


def best_ratio(wanted: list, got: list, window: int) -> float:
    """Parecido entre lo esperado y lo oído. Con frases cortas Whisper a veces repite la frase desde
    el principio; por eso se prueba también cortando lo oído donde vuelve a empezar y se toma lo mejor."""
    best = SequenceMatcher(None, wanted, got).ratio()
    for index in range(1, len(got)):
        size = min(window, index)
        if got[index:index + size] == got[:size]:
            best = max(best, SequenceMatcher(None, wanted, got[:index]).ratio())
    return best


def load_audio(path: str):
    import soundfile as sf

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav = tmp.name
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ar", "16000", "-ac", "1", wav], check=True)
    wave, _rate = sf.read(wav, dtype="float32")
    os.unlink(wav)
    return wave


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    folder, code = sys.argv[1], sys.argv[2]
    only = set(sys.argv[3:])
    here = os.path.dirname(__file__)
    lines = {}
    with open(os.path.join(here, "lines", code + ".txt"), encoding="utf-8") as handle:
        for raw in handle:
            if "|" in raw:
                key, text = raw.rstrip("\n").split("|", 1)
                lines[key] = text
    root = os.path.join(here, "..", "..", "assets", "voice_" + code)
    whisper = Whisper(folder)
    scores = []
    for key, text in lines.items():
        if only and key not in only:
            continue
        path = os.path.join(root, "tutorial", key + ".ogg") if key.startswith("tut_") else os.path.join(root, key + ".ogg")
        if not os.path.exists(path):
            print("FALTA", key)
            continue
        heard = whisper.transcribe(load_audio(path), code)
        wanted, got = normalize(text), normalize(heard)
        if code in BY_CHARACTER:
            ratio = best_ratio(list(wanted.replace(" ", "")), list(got.replace(" ", "")), 6)
        else:
            ratio = best_ratio(wanted.split(), got.split(), 3)
        scores.append((ratio, key, text, heard[:200]))
        print(f"{ratio:.2f} {key}", flush=True)
    if not scores:
        return 1
    scores.sort()
    print("\nMEDIA %.3f de %d frases. Las de peor nota:" % (sum(item[0] for item in scores) / len(scores), len(scores)))
    for ratio, key, text, heard in scores[:10]:
        print(f"  {ratio:.2f} {key}\n     texto: {text}\n     oído : {heard}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
