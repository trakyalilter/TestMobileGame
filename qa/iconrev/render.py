import resvg_py
from PIL import Image
import io, os

d = r"C:\Users\gokbe\Documents\horizonidle\qa\iconrev"
files = {
    "A": "A_sunrise.svg",
    "B": "B_comet_horizon.svg",
    "C": "C_comet_mark.svg",
    "D": "D_sunrise_sigil.svg",
}

# navy backdrop to composite over (icons are opaque tiles, but ensure no alpha surprises)
def load512(path):
    svg = open(path, "r", encoding="utf-8").read()
    png_bytes = resvg_py.svg_to_bytes(svg_string=svg, width=512, height=512)
    img = Image.open(io.BytesIO(bytes(png_bytes))).convert("RGBA")
    # flatten over black to mimic a worst-case dark Steam list bg
    bg = Image.new("RGBA", img.size, (18, 18, 22, 255))
    return Image.alpha_composite(bg, img).convert("RGB")

for k, fn in files.items():
    src = os.path.join(d, fn)
    big = load512(src)
    big.save(os.path.join(d, f"{k}_512.png"))
    for s in (48, 32, 24, 16):
        small = big.resize((s, s), Image.LANCZOS)
        small.save(os.path.join(d, f"{k}_{s}.png"))
        # magnify nearest-neighbor for human inspection
        mag = small.resize((s*12, s*12), Image.NEAREST)
        mag.save(os.path.join(d, f"{k}_{s}_mag.png"))
    print(f"{k} rendered")

# Build contact sheets: one per size showing all 4 magnified side by side
labels = ["A", "B", "C", "D"]
for s in (32, 16):
    tiles = [Image.open(os.path.join(d, f"{x}_{s}_mag.png")) for x in labels]
    w = sum(t.width for t in tiles) + 30*3
    h = max(t.height for t in tiles)
    sheet = Image.new("RGB", (w, h), (40, 40, 46))
    x = 0
    for t in tiles:
        sheet.paste(t, (x, 0))
        x += t.width + 30
    sheet.save(os.path.join(d, f"_sheet_{s}.png"))
    print(f"sheet {s} done")

# also a 512 comparison sheet (downscaled to 256 each, 2x2)
comp = Image.new("RGB", (256*2+20, 256*2+20), (40,40,46))
pos = {"A":(0,0),"B":(276,0),"C":(0,276),"D":(276,276)}
for k in labels:
    im = Image.open(os.path.join(d, f"{k}_512.png")).resize((256,256), Image.LANCZOS)
    comp.paste(im, pos[k])
comp.save(os.path.join(d, "_sheet_512.png"))
print("512 sheet done")
print("ALL DONE")
