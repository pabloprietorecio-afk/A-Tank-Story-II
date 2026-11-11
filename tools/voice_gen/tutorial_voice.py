#!/usr/bin/env python3
"""Locuciones del tutorial con Kokoro TTS (misma voz de radio que el resto del juego).

Uso:
    pip install kokoro-onnx soundfile        # y ffmpeg en el sistema
    python3 tools/voice_gen/tutorial_voice.py MODELO.onnx VOCES.bin [id ...]

MODELO y VOCES son kokoro-v1.0.int8.onnx y voices-v1.0.bin (versión model-files-v1.0 de
github.com/thewh1teagle/kokoro-onnx). Escribe assets/voice/tutorial/tut_<id>.ogg.
Si una frase falla se avisa y se sigue: el juego muestra esa instrucción solo con texto.
"""
import os
import subprocess
import sys
import tempfile

VOICE = "em_santa"
SPEED = 1.05

# id del paso (ver STEPS en levels/modes/tutorial/tutorial_mode.gd) -> lo que dice la radio.
LINES = {
    "move_a": "Aquí base. Empezamos. Toca el lado izquierdo de la pantalla y empuja hacia arriba. Avanza hasta la baliza amarilla.",
    "move_b": "Bien. Ahora marcha atrás. Tira del joystick hacia abajo y retrocede unos metros.",
    "turn": "Para girar el casco, mueve el joystick a izquierda o derecha. Pasa por las tres balizas en zigzag.",
    "turret": "La torreta. Arrastra el dedo por la mitad derecha de la pantalla y pon la mira sobre las tres dianas.",
    "fire_a": "Apunta a una diana y pulsa el botón de disparo.",
    "fire_b": "El cañón está recargando. La barra bajo la mira se llena. Cuando esté verde, dispara hasta destruir una diana.",
    "easy_a": "Movimiento fácil. Al avanzar, el casco sigue al cañón. Apunta a la baliza y empuja solo hacia delante.",
    "easy_b": "Se desactiva en ajustes, movimiento fácil. Ve del mismo modo hasta la segunda baliza.",
    "camera": "Pulsa el botón de cámara para cambiar de vista: cabina, trasera y trasera lejana.",
    "radar": "El radar. Los puntos son enemigos. Los cuadros azules, aliados. El rombo, tu objetivo. Los anillos son edificios con premio y las cruces, premios. Ve hasta el rombo.",
    "enemy_a": "Tanque enemigo de prácticas, parado. Destrúyelo. Harán falta varios disparos.",
    "enemy_b": "Ahora uno en movimiento. Apunta un poco por delante y destrúyelo.",
    "assist_a": "Apuntado automático. Abre los ajustes, actívalo y pulsa continuar.",
    "assist_b": "Pasa la mira sobre el enemigo. Se fija solo y la mira se vuelve naranja.",
    "assist_c": "Fijado. Sobre la mira ves su blindaje y su ataque. Pulsa liberar objetivo para soltarlo.",
    "zoom_a": "Pulsa zoom para usar los prismáticos.",
    "zoom_b": "Solo con zoom aparecen el misil y el avión. Acierta a la diana lejana.",
    "missile": "Misil guiado. Fija al enemigo con la mira y, con el zoom puesto, pulsa misil.",
    "strike_a": "Bombardeo aliado. Con el zoom puesto, apunta al depósito cercano y pulsa avión.",
    "strike_b": "Denegado. A menos de treinta metros las bombas te alcanzarían. Pídelo sobre el depósito lejano.",
    "strike_c": "Ahora pídelo sobre el depósito cercano y escucha qué responde la base.",
    "raid": "Bombardeo enemigo. Cuando veas la zona roja, sal de ella antes de que la cuenta llegue a cero.",
    "damage_a": "Daño. Un enemigo te va a disparar. Mira tu barra de blindaje, abajo.",
    "damage_b": "Recoge la caja verde pasando por encima. Repara tu blindaje.",
    "damage_c": "Recoge la caja azul. Recarga rápida durante veinte segundos.",
    "follow_a": "Todos conmigo. Pulsa el icono de las tres flechas, a la izquierda, y tus aliados te seguirán.",
    "follow_b": "Ahora conduce hasta la baliza amarilla. Tus aliados vendrán contigo y te acompañarán.",
    "focus_a": "Todos al objetivo. Apunta al tanque enemigo y pulsa el icono de la diana con dos flechas.",
    "focus_b": "Todos tus aliados atacan lo que has señalado. Espera a que lo destruyan.",
    "final": "Combate final. Con tus dos aliados, destruye los tres tanques enemigos y el depósito. Usa todo lo aprendido.",
    "end": "Tutorial completado. Buen trabajo. Ya puedes empezar la campaña.",
}

# Efecto de radio: pitido de inicio, filtro de banda de transmisor, compresión y estática.
RADIO = (
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
    out_dir = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "voice", "tutorial")
    os.makedirs(out_dir, exist_ok=True)
    failed = []
    for key in wanted:
        out = os.path.join(out_dir, f"tut_{key}.ogg")
        try:
            samples, rate = kokoro.create(LINES[key], voice=VOICE, speed=SPEED, lang="es")
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
                wav = tmp.name
            sf.write(wav, samples, rate)
            subprocess.run(
                ["ffmpeg", "-y", "-loglevel", "error", "-i", wav,
                 "-f", "lavfi", "-i", "sine=f=1200:d=0.15",
                 "-f", "lavfi", "-i", "anoisesrc=d=40:c=white:a=0.5",
                 "-filter_complex", RADIO, "-ac", "1", "-ar", "22050", "-c:a", "libvorbis", "-q:a", "4", out],
                check=True)
            os.unlink(wav)
            print("ok", key)
        except Exception as error:  # una frase que falla no detiene el resto
            failed.append(key)
            print("FALLO", key, error)
    print(f"{len(wanted) - len(failed)} generadas, {len(failed)} fallidas: {failed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
