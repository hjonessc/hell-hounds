# Writes the custom SF Symbol templates (Regular-M only) into the asset catalog:
#   python3 tools/symbols/make_symbols.py HellHounds/Assets.xcassets
# Glyphs are drawn in a 100x100 box (y down), scaled so they stand taller than
# the cap height like the system symbols; holes wind counter-clockwise.
import json, os, sys

PUMPKIN = ("M50,28 C60,22 74,22 84,30 C96,40 98,70 88,84 C80,95 64,96 50,92 "
           "C36,96 20,95 12,84 C2,70 4,40 16,30 C26,22 40,22 50,28 Z "
           "M46,28 C46,20 48,14 52,10 L58,12 C55,16 54,22 54,28 Z")
RIBS = ("M37,30 C26,45 26,75 37,90 C30,75 30,45 37,30 Z "
        "M63,30 C70,45 70,75 63,90 C74,75 74,45 63,30 Z")
FACE = ("M35,40 L28,54 L42,54 Z M65,40 L58,54 L72,54 Z M50,56 L46,63 L54,63 Z "
        "M24,66 C30,88 70,88 76,66 L66,71 L62,67 L56,73 L50,69 L44,73 L38,67 L34,71 Z")
BAT = ("M50,40 L54,32 L56,42 C62,42 68,36 72,30 C80,34 90,34 98,32 C92,40 90,50 92,60 "
       "C86,56 80,56 76,62 C72,56 66,56 62,62 C58,58 54,62 50,70 C46,62 42,58 38,62 "
       "C34,56 28,56 24,62 C20,56 14,56 8,60 C10,50 8,40 2,32 C10,34 20,34 28,30 "
       "C32,36 38,42 44,42 L46,32 Z")
GHOST = ("M22,50 C22,30 34,16 50,16 C66,16 78,30 78,50 L78,88 "
         "C76,94 70,94 67,88 C64,82 58,82 56,88 C53,94 47,94 44,88 "
         "C42,82 36,82 33,88 C30,94 24,94 22,88 Z "
         "M34,44 a6,8 0 1,0 12,0 a6,8 0 1,0 -12,0 Z "
         "M54,44 a6,8 0 1,0 12,0 a6,8 0 1,0 -12,0 Z "
         "M45,64 a5,7 0 1,0 10,0 a5,7 0 1,0 -10,0 Z")

SYMBOLS = {
    "hound.jackolantern": PUMPKIN + " " + FACE,
    "hound.pumpkin": PUMPKIN + " " + RIBS,
    "hound.bat": BAT,
    "hound.ghost": GHOST,
}

TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" xmlns="http://www.w3.org/2000/svg" width="3300" height="2200">
 <g id="Notes">
  <text style="font-size:13px;font-family:sans-serif">Template v.2.0 · drawn for Hell Hounds</text>
 </g>
 <g id="Guides">
  <line id="Baseline-S" style="fill:none;stroke:#27AAE1" x1="263" x2="3036" y1="696" y2="696"/>
  <line id="Capline-S" style="fill:none;stroke:#27AAE1" x1="263" x2="3036" y1="625.541" y2="625.541"/>
  <line id="Baseline-M" style="fill:none;stroke:#27AAE1" x1="263" x2="3036" y1="1126" y2="1126"/>
  <line id="Capline-M" style="fill:none;stroke:#27AAE1" x1="263" x2="3036" y1="1055.54" y2="1055.54"/>
  <line id="Baseline-L" style="fill:none;stroke:#27AAE1" x1="263" x2="3036" y1="1556" y2="1556"/>
  <line id="Capline-L" style="fill:none;stroke:#27AAE1" x1="263" x2="3036" y1="1485.54" y2="1485.54"/>
  <line id="left-margin-Regular-M" style="fill:none;stroke:#00AEEF" x1="1400" x2="1400" y1="1030" y2="1150"/>
  <line id="right-margin-Regular-M" style="fill:none;stroke:#00AEEF" x1="1530" x2="1530" y1="1030" y2="1150"/>
 </g>
 <g id="Symbols">
  <g id="Regular-M" transform="matrix(1.3 0 0 1.3 1400 1022)">
   <path d="{d}"/>
  </g>
 </g>
</svg>
"""

catalog = sys.argv[1]
for name, d in SYMBOLS.items():
    folder = os.path.join(catalog, name + ".symbolset")
    os.makedirs(folder, exist_ok=True)
    svg = name.split(".")[1] + ".svg"
    with open(os.path.join(folder, svg), "w") as f:
        f.write(TEMPLATE.replace("{d}", d))
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump({"info": {"author": "xcode", "version": 1},
                   "symbols": [{"filename": svg, "idiom": "universal"}]}, f, indent=2)
        f.write("\n")
    print("wrote", folder)
