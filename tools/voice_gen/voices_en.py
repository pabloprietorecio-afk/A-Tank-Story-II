#!/usr/bin/env python3
"""Voces en inglés (tripulación, radio y tutorial) con Kokoro TTS y el mismo efecto de radio.

Uso:
    pip install kokoro-onnx soundfile        # y ffmpeg en el sistema
    python3 tools/voice_gen/voices_en.py MODELO.onnx VOCES.bin [id ...]

MODELO y VOCES son kokoro-v1.0.int8.onnx y voices-v1.0.bin (model-files-v1.0 de
github.com/thewh1teagle/kokoro-onnx). Escribe assets/voice_en/<id>.ogg y
assets/voice_en/tutorial/tut_<id>.ogg, que el juego usa cuando el idioma es inglés.
Los ids de la tripulación son los de VoiceManager.EVENTS; los del tutorial, los de STEPS.
"""
import os
import subprocess
import sys
import tempfile

CREW = ("am_michael", "en-us")   # voz dentro del tanque
RADIO = ("bm_george", "en-gb")   # base: órdenes y partes por radio
SPEED = 1.05

# id -> (voz, texto)
LINES = {
    "air_clear": (RADIO, "Air attack repelled. The skies are clear."),
    "air_phase": (RADIO, "Air attack! Enemy fighters and bombers inbound. Shoot them down!"),
    "armor_low": (CREW, "Armour critical! One more hit and we're done!"),
    "bonus": (CREW, "Bonus secured! Well done, commander."),
    "cease_fire": (CREW, "Cease fire! Cease fire! There are prisoners in there!"),
    "commander": (RADIO, "Enemy commander down. Their attack is falling apart."),
    "flag_capture": (RADIO, "Flag captured! Excellent work!"),
    "flag_lost": (RADIO, "The enemy has our flag! Get it back!"),
    "flag_taken": (RADIO, "You have the enemy flag! Bring it back to base!"),
    "hit_1": (CREW, "We're hit!"),
    "hit_2": (CREW, "Taking fire!"),
    "kill_1": (CREW, "Target destroyed!"),
    "kill_2": (CREW, "Got him!"),
    "kill_3": (CREW, "Enemy tank down!"),
    "liberation": (RADIO, "The wire is down. The prisoners are free!"),
    "locked": (CREW, "Target locked."),
    "missile": (CREW, "Missile away!"),
    "mission_fail": (RADIO, "Mission failed. We have lost the tank."),
    "mission_start": (RADIO, "Mission begins. Good hunting, commander."),
    "mission_win": (RADIO, "Mission accomplished! Outstanding work."),
    "objective": (RADIO, "Objective destroyed."),
    "pickup": (CREW, "Supplies collected."),
    "radar_1": (CREW, "Contact! Enemy tanks on the radar."),
    "radar_2": (CREW, "Radar shows hostiles ahead. Stay sharp."),
    "raid_1": (RADIO, "Enemy bombers overhead! Get out of the red zone!"),
    "raid_2": (RADIO, "Air raid! Move, move, move!"),
    "reinforcements": (RADIO, "Enemy reinforcements arriving."),
    "shot_down_1": (CREW, "Aircraft down!"),
    "shot_down_2": (CREW, "Splash one!"),
    "strike_1": (RADIO, "Airstrike called in. Keep your head down."),
    "strike_2": (RADIO, "Bombers on the way. Stand clear."),
    "strike_denied": (RADIO, "Request denied. The target is too close to your position."),
    "wave_clear": (RADIO, "Wave cleared. Reload and repair."),
    "wave_start": (RADIO, "New wave incoming. Brace yourselves."),
    # Tutorial (ids de STEPS en levels/modes/tutorial/tutorial_mode.gd).
    "tut_move_a": (RADIO, "Base here. Let's begin. Touch the left side of the screen and push up. Drive to the yellow beacon."),
    "tut_move_b": (RADIO, "Good. Now reverse. Pull the joystick down and back up a few metres."),
    "tut_turn": (RADIO, "To turn the hull, move the joystick left or right. Pass through the three beacons in a zigzag."),
    "tut_turret": (RADIO, "The turret. Drag your finger across the right half of the screen and put the crosshair on the three targets."),
    "tut_fire_a": (RADIO, "Aim at a target and press the fire button."),
    "tut_fire_b": (RADIO, "The cannon is reloading. The bar under the crosshair fills up. When it turns green, fire until you destroy a target."),
    "tut_easy_a": (RADIO, "Easy driving. When you move forward, the hull follows the gun. Aim at the beacon and push straight forward."),
    "tut_easy_b": (RADIO, "You can turn it off in the settings, under easy driving. Go the same way to the second beacon."),
    "tut_camera": (RADIO, "Press the camera button to change view: cockpit, rear and far rear."),
    "tut_radar": (RADIO, "The radar. Dots are enemies. Blue squares, allies. The diamond, your objective. Rings are buildings with rewards, and crosses are rewards. Go to the diamond."),
    "tut_enemy_a": (RADIO, "Stationary enemy practice tank. Destroy it. It will take several shots."),
    "tut_enemy_b": (RADIO, "Now one that is moving. Aim a little ahead and destroy it."),
    "tut_assist_a": (RADIO, "Auto-aim. Open the settings, turn it on and press continue."),
    "tut_assist_b": (RADIO, "Sweep the crosshair over the enemy. It locks on by itself and the crosshair turns orange."),
    "tut_assist_c": (RADIO, "Locked. Above the crosshair you can see its armour and attack. Press release target to let it go."),
    "tut_zoom_a": (RADIO, "Press zoom to use the binoculars."),
    "tut_zoom_b": (RADIO, "Only with zoom do the missile and strike buttons appear. Hit the distant target."),
    "tut_missile": (RADIO, "Guided missile. Lock the enemy with the crosshair and, with zoom on, press missile."),
    "tut_strike_a": (RADIO, "Allied airstrike. With zoom on, aim at the nearby depot and press strike."),
    "tut_strike_b": (RADIO, "Denied. Within thirty metres the bombs would hit you. Call it in on the far depot."),
    "tut_strike_c": (RADIO, "Now call it in on the nearby depot and listen to what base replies."),
    "tut_raid": (RADIO, "Enemy air raid. When you see the red zone, get out of it before the countdown reaches zero."),
    "tut_damage_a": (RADIO, "Damage. An enemy is about to shoot at you. Watch your armour bar, at the bottom."),
    "tut_damage_b": (RADIO, "Pick up the green crate by driving over it. It repairs your armour."),
    "tut_damage_c": (RADIO, "Pick up the blue crate. Fast reload for twenty seconds."),
    "tut_follow_a": (RADIO, "All on me. Press the three-arrow icon on the left and your allies will follow you."),
    "tut_follow_b": (RADIO, "Now drive to the yellow beacon. Your allies will come along and stay with you."),
    "tut_focus_a": (RADIO, "All on target. Aim at the enemy tank and press the target icon with two arrows."),
    "tut_focus_b": (RADIO, "All your allies are attacking what you marked. Wait for them to destroy it."),
    "tut_final": (RADIO, "Final battle. With your two allies, destroy the three enemy tanks and the depot. Use everything you have learned."),
    "tut_end": (RADIO, "Tutorial complete. Well done. You can now start the campaign."),
}

# Efecto de radio: pitido de inicio, filtro de banda de transmisor, compresión y estática
# (igual que en tutorial_voice.py).
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
    root = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "voice_en")
    os.makedirs(os.path.join(root, "tutorial"), exist_ok=True)
    failed = []
    for key in wanted:
        (voice, lang), text = LINES[key]
        out = os.path.join(root, "tutorial", key + ".ogg") if key.startswith("tut_") else os.path.join(root, key + ".ogg")
        try:
            samples, rate = kokoro.create(text, voice=voice, speed=SPEED, lang=lang)
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
            print("ok", key)
        except Exception as error:  # una frase que falla no detiene el resto
            failed.append(key)
            print("FALLO", key, error)
    print(f"{len(wanted) - len(failed)} generadas, {len(failed)} fallidas: {failed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
