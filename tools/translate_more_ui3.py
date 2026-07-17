import re
from pathlib import Path
import csv

repo = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")

def replace_in_file(rel_path, old, new):
    p = repo / rel_path
    if p.exists():
        c = p.read_text(encoding="utf-8")
        if old in c:
            p.write_text(c.replace(old, new), encoding="utf-8")
            print(f"Replaced in {rel_path}: {old.strip()} -> {new.strip()}")

# module_widget.gd
replace_in_file(r"scripts\ui\module_widget.gd",
    '"POWER DRAW: %d\\n"', 'tr("POWER DRAW: %d\\n")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"POWER: +%d\\n"', 'tr("POWER: +%d\\n")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"Durability: %d/100\\n"', 'tr("Durability: %d/100\\n")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"%s total damage, %.2f hits/s"', 'tr("%s total damage, %.2f hits/s")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"Shield Capacity"', 'tr("Shield Capacity")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"Integrity Reinforcement"', 'tr("Integrity Reinforcement")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"Comparing with: %s"', 'tr("Comparing with: %s")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"SET: %s"', 'tr("SET: %s")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"%d / %d pieces equipped"', 'tr("%d / %d pieces equipped")')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"[color=silver]* %s: [color=white]%s[/color][/color]%s%s\\n" % [label,',
    '"[color=silver]* %s: [color=white]%s[/color][/color]%s%s\\n" % [tr(label),')
replace_in_file(r"scripts\ui\module_widget.gd",
    '"%s: %s\\n" % [label,',
    '"%s: %s\\n" % [tr(label),')
replace_in_file(r"scripts\ui\module_widget.gd",
    'slot_type.capitalize()', 'tr(slot_type.capitalize())')

# Add to strings.csv
known_translations = {
    "POWER DRAW: %d\n": "GÜÇ ÇEKİMİ: %d\n",
    "POWER: +%d\n": "GÜÇ: +%d\n",
    "Durability: %d/100\n": "Dayanıklılık: %d/100\n",
    "%s total damage, %.2f hits/s": "Toplam hasar %s, %.2f vuruş/sn",
    "Shield Capacity": "Kalkan Kapasitesi",
    "Integrity Reinforcement": "Bütünlük Takviyesi",
    "Comparing with: %s": "Karşılaştırılan: %s",
    "SET: %s": "SET: %s",
    "%d / %d pieces equipped": "%d / %d parça takılı",
    "Req: %s": "Gereksinim: %s",
    "Req: %s (Warp Tree)": "Gereksinim: %s (Warp Ağacı)"
}

csv_path = repo / r"localization\strings.csv"
existing_keys = set()
rows = []
if csv_path.exists():
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) > 0:
                existing_keys.add(row[0])
            rows.append(row)

for k, v in known_translations.items():
    if k not in existing_keys:
        rows.append([k, v])
        existing_keys.add(k)

with open(csv_path, 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(rows)

print("Finished third batch replacements.")
