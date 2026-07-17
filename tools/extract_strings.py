import os
import re
import csv
from pathlib import Path

def extract_strings():
    project_dir = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")
    csv_path = project_dir / "localization" / "strings.csv"
    
    # Read existing keys
    existing_keys = set()
    if csv_path.exists():
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            for row in reader:
                if row:
                    existing_keys.add(row[0])
    
    # Regex for .tscn files
    # matches text = "something", placeholder_text = "something", tooltip_text = "something"
    tscn_regex = re.compile(r'(?:^|\s)(?:text|placeholder_text|tooltip_text)\s*=\s*"([^"\\]*(?:\\.[^"\\]*)*)"')
    
    # Regex for .gd files
    # matches tr("something")
    gd_regex = re.compile(r'tr\(\s*"([^"\\]*(?:\\.[^"\\]*)*)"\s*\)')

    found_strings = set()
    
    # Walk scenes and scripts
    for root, dirs, files in os.walk(project_dir):
        # exclude some directories
        if ".godot" in root or ".git" in root:
            continue
            
        for file in files:
            file_path = Path(root) / file
            
            if file.endswith('.tscn'):
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    matches = tscn_regex.findall(content)
                    for m in matches:
                        # Unescape simple quotes if needed
                        val = m.replace('\\"', '"')
                        found_strings.add(val)
                        
            elif file.endswith('.gd'):
                with open(file_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    matches = gd_regex.findall(content)
                    for m in matches:
                        val = m.replace('\\"', '"')
                        found_strings.add(val)

    # Filter out obvious placeholders or empty strings
    new_strings = []
    for s in found_strings:
        s = s.strip()
        if not s: continue
        if s in existing_keys: continue
        # Ignore things that are purely numbers or very short symbols
        if re.match(r'^[0-9\+\-\.\s/KMBT]+$', s): continue
        if s == "..." or s == "---": continue
        
        new_strings.append(s)

    new_strings.sort()
    
    if new_strings:
        with open(csv_path, 'a', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            for s in new_strings:
                # Add an empty column for the Turkish translation
                writer.writerow([s, ""])
        print(f"Added {len(new_strings)} new strings to strings.csv")
    else:
        print("No new strings found.")

if __name__ == "__main__":
    extract_strings()
