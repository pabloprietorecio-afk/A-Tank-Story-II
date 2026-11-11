#!/usr/bin/env python3
"""Descarga de Wikimedia Commons las grabaciones elegidas, las pasa a OGG mono y transcribe las
de voz (para elegir los extractos sabiendo qué se dice). Deja todo en audio_raw/."""
import os, subprocess, sys, time, urllib.parse, urllib.request

UA = {"User-Agent": "ATankStory-audio-fetch/1.0 (github.com/pabloprietorecio-afk/Tank-Ahead)"}
# id: (archivo en Commons, idioma si es voz, [inicio s, duración s] opcional)
FILES = {
    "churchill_valour": ("Winston Churchill - Be Ye Men of Valour.ogg", "en", None),
    "eisenhower_dday": ("Gen. Dwight D. Eisenhower s D-Day order of the day.mp3", "en", None),
    "roosevelt_infamy": ("Roosevelt Infamy.ogg", "en", None),
    "chamberlain_war": ("Chamberlain-war-declaration.ogg", "en", None),
    "bbc_byam_dday": ("Guy Byam - D-Day parachute drop.flac", "en", None),
    "bbc_border_1944": ("4-sep-1944 BBC army crossing Dutch border.ogg", "en", None),
    "levitan_attack": ("Levitan USSR attacked.ogg", "ru", None),
    "hitler_1945": ("Adolf Hitler’s last speech.ogg", "de", None),
    "hitler_1943": ("Hit43.ogg", "de", None),
    "hitler_x": ("Hit.ogg", "de", None),
    "hitler_1935": ("Adolf Hitler Speech in 1935.ogg", "de", None),
    "tank_centurion_ride": ("Centurion tank, starten, rijden en stoppen - SoundCloud - Beeld en Geluid.ogg", None, None),
    "tank_centurion_idle": ("Centurion tank, stationair, pompen en afschakelen - SoundCloud - Beeld en Geluid.ogg", None, None),
    "tank_sherman_idle": ("Sherman tank, rijden, stationair en stoppen - SoundCloud - Beeld en Geluid.ogg", None, None),
    "tank_sherman_drive": ("Sherman tank, rijden en manoeuvreren - SoundCloud - Beeld en Geluid.ogg", None, None),
    "tank_sherman_fast": ("Sherman tank, met grote snelheid rijden - SoundCloud - Beeld en Geluid.ogg", None, None),
    "plane_spitfire": ("Spitfire fly past at RAF Halton.ogg", None, None),
    "plane_merlin": ("RR Merlin 66-266.ogg", None, None),
    "plane_dc3": ("McDonnell Douglas DC-3 Dakota, vliegen - SoundCloud - Beeld en Geluid.ogg", None, [0, 240]),
    "plane_steady": ("Propeller-plane-flying-steady-01.wav", None, None),
    "plane_trimotor": ("EAA Ford TriMotor NC8407.ogg", None, None),
    "gun_sexton": ("Sexton artillery firing.oga", None, None),
}

os.makedirs("audio_raw", exist_ok=True)
log = open("audio_raw/README.txt", "a")
model = None
for key, (name, lang, window) in sorted(FILES.items(), key=lambda item: item[1][1] is not None):
    if os.path.exists(f"audio_raw/{key}.ogg"):
        continue
    url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(name)
    source = "source_" + key
    ok = False
    for attempt in range(6):
        time.sleep(20 + attempt * 50)
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=180) as response, open(source, "wb") as out:
                out.write(response.read())
            ok = True
            break
        except Exception as error:
            print("ERROR", key, error, flush=True)
    if not ok:
        log.write(f"{key}: NO DESCARGADO ({name})\n")
        continue
    out = f"audio_raw/{key}.ogg"
    cut = ["-ss", str(window[0]), "-t", str(window[1])] if window else []
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", source, *cut, "-vn", "-ac", "1", "-ar", "32000", "-c:a", "libvorbis", "-q:a", "5", out], check=False)
    duration = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", out], capture_output=True, text=True).stdout.strip()
    print("OK", key, duration, flush=True)
    log.write(f"{key}: {duration} s | {name}\n")
    if lang:
        try:
            if model is None:
                from faster_whisper import WhisperModel
                model = WhisperModel("small", device="cpu", compute_type="int8")
            segments, _info = model.transcribe(out, language=lang, vad_filter=True)
            with open(f"audio_raw/{key}.txt", "w") as text:
                for segment in segments:
                    text.write("%7.1f %7.1f %s\n" % (segment.start, segment.end, segment.text.strip()))
        except Exception as error:
            print("ERROR transcripción", key, error, flush=True)
    os.remove(source)
log.close()
