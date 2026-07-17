import re
from pathlib import Path
import csv

repo = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")

missing_strings = set()

def extract_names(rel_path):
    p = repo / rel_path
    if not p.exists(): return
    content = p.read_text(encoding="utf-8")
    
    # Matches "name": "Something"
    names = re.findall(r'"name"\s*:\s*"([^"]+)"', content)
    for n in names:
        missing_strings.add(n)

# Extract from various databases
extract_names(r"scripts\core\enemy_db.gd")
extract_names(r"scripts\core\module_db.gd")
extract_names(r"scripts\managers\processing_manager.gd")
extract_names(r"scripts\managers\shipyard_manager.gd")
extract_names(r"scripts\managers\research_manager.gd")
extract_names(r"scripts\managers\infrastructure_manager.gd")
extract_names(r"scripts\managers\gathering_manager.gd")

# element_db.gd has ELEMENT_NAMES = {"Symbol": "Name", ...}
p_elem = repo / r"scripts\core\element_db.gd"
if p_elem.exists():
    c_elem = p_elem.read_text(encoding="utf-8")
    # Very rough extraction: inside ELEMENT_NAMES block
    match = re.search(r'var ELEMENT_NAMES = \{(.*?)\}', c_elem, re.DOTALL)
    if match:
        pairs = re.findall(r'"[^"]+"\s*:\s*"([^"]+)"', match.group(1))
        for v in pairs:
            missing_strings.add(v)
            
    # Also ELEMENT_DATA might have "name":
    names = re.findall(r'"name"\s*:\s*"([^"]+)"', c_elem)
    for n in names:
        missing_strings.add(n)

# Hardcoded translations from screenshots we already know
known_translations = {
    "Cassiterite": "Kalay Cevheri",
    "Tin Ore": "Kalay Cevheri",
    "Common Artifact": "Sıradan Eser",
    "Damaged Circuitry": "Hasarlı Devre",
    "Advanced Circuitry": "Gelişmiş Devre",
    "Industrial Frigate": "Endüstriyel Fırkateyn",
    "Ships": "Gemiler",
    "Automation": "Otomasyon",
    "Engineering": "Mühendislik",
    "Operations": "Operasyonlar",
    "COST": "MALİYET",
    "NEXT LEVEL COST": "SONRAKİ SEVİYE MALİYETİ",
    "EFFECTS": "ETKİLER",
    "UNLOCKS": "KİLİTLERİ AÇAR",
    "REQUIRES": "GEREKSİNİMLER",
    "(cross-branch)": "(çapraz dal)",
    "OWNED %s": "SAHİP OLUNAN %s",
    "VALUE %s %s": "DEĞER %s %s",
    "SOURCED FROM": "KAYNAK",
    "CONSUMED BY": "KULLANILDIĞI YER",
    "%.0f%% chance": "%%%.0f şans",
    "%d-%d per kill": "Öldürme başına %d-%d",
    " (Rare)": " (Nadir)",
    "NEEDS RARE GEAR": "NADİR EKİPMAN GEREKLİ",
    "RARE DROPS": "NADİR DÜŞENLER",
    "MODULE DROPS (%d%%)": "MODÜL DÜŞME ORANI (%%%d)",
    "%d per cycle": "Döngü başına %d",
    "%s (%s)": "%s (%s)",
    "T%d": "A%d",
    "Spare Parts": "Yedek Parçalar",
    "IN STOCK": "STOKTA",
    "NOT ENOUGH SPARE PARTS": "YETERLİ YEDEK PARÇA YOK",
    "EMP Overlord": "EMP Derebeyi",
    "Ice Wraith": "Buzul Hayaleti",
    "Glacial Drone": "Buzul Dronu",
    "Glacial Overseer": "Buzul Gözetmeni",
    "Alien Probe": "Uzaylı Sondası",
    "Defense Turret": "Savunma Tareti"
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

added = 0
for k, v in known_translations.items():
    if k not in existing_keys:
        rows.append([k, v])
        existing_keys.add(k)
        added += 1

# Now add all missing_strings using themselves as Turkish placeholder
for s in missing_strings:
    if s not in existing_keys:
        # We don't have a translation for it, but adding it to CSV ensures
        # it is registered and the user can easily find and translate it in the CSV file
        rows.append([s, s]) 
        existing_keys.add(s)
        added += 1

with open(csv_path, 'w', encoding='utf-8', newline='') as f:
    writer = csv.writer(f)
    writer.writerows(rows)

print(f"Added {added} missing strings to strings.csv")
