#!/usr/bin/env python3
"""Busca en Wikimedia Commons grabaciones candidatas y lista licencia, tamaño y descripción."""
import json, re, sys, time, urllib.parse, urllib.request

API = "https://commons.wikimedia.org/w/api.php"
UA = {"User-Agent": "ATankStory-audio-fetch/1.0 (github.com/pabloprietorecio-afk/Tank-Ahead)"}
QUERIES = sys.argv[1:] or [
    "Hitler 1939", "Hitler 1941", "Kriegserklärung", "Deutschlandsender", "Goebbels", "Rundfunk 1939", "Rundfunk 1944",
    "German radio 1940", "BBC 1944", "D-Day broadcast", "Montgomery", "Levitan", "Stalin 1941", "radio broadcast 1944",
    "tank engine", "Panzer", "tank sound", "T-34", "Sherman tank", "diesel engine", "tracked vehicle", "Kettenfahrzeug",
    "bulldozer", "tractor engine", "engine idle", "V12 engine", "excavator",
    "Spitfire", "Merlin engine", "Messerschmitt", "Mustang", "propeller aircraft", "B-17", "radial engine", "Stuka",
    "Ju 52", "flyby", "flypast", "warbird", "aircraft engine", "DC-3", "Lancaster", "Propellerflugzeug", "airplane flying",
    "anti-aircraft", "Flak", "artillery", "cannon shot", "distant explosion", "gunfire",
]


def clean(html):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html or "")).strip()


for query in QUERIES:
    params = {
        "action": "query", "format": "json", "generator": "search", "gsrnamespace": "6",
        "gsrsearch": "filetype:audio " + query, "gsrlimit": "40", "prop": "imageinfo",
        "iiprop": "url|size|mime|extmetadata",
    }
    data = None
    for attempt in range(5):
        time.sleep(6 + attempt * 20)
        try:
            request = urllib.request.Request(API + "?" + urllib.parse.urlencode(params), headers=UA)
            data = json.load(urllib.request.urlopen(request, timeout=40))
            break
        except Exception as error:
            print(f"## {query}: ERROR {error}")
    if data is None:
        continue
    pages = sorted(data.get("query", {}).get("pages", {}).values(), key=lambda p: p.get("index", 0))
    print(f"## {query}: {len(pages)}")
    for page in pages:
        if "DPLA" in page["title"] or "Radio Oranje" in page["title"] or page["title"].startswith(("File:De-", "File:En-", "File:LL-")):
            continue
        info = (page.get("imageinfo") or [{}])[0]
        meta = info.get("extmetadata", {})
        get = lambda key: clean(meta.get(key, {}).get("value", ""))
        print("%s | %s | %d KB | %s | %s | %s | %s" % (
            page["title"], info.get("mime", "?"), info.get("size", 0) // 1024, get("LicenseShortName"),
            get("DateTimeOriginal")[:20], get("Artist")[:40], get("ImageDescription")[:160]))
