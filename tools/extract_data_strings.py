import os
import json
import re
import csv
from pathlib import Path

def extract_data_strings():
    project_dir = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")
    csv_path = project_dir / "localization" / "strings.csv"
    
    existing_keys = set()
    if csv_path.exists():
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.reader(f)
            headers = next(reader, None)
            for row in reader:
                if row:
                    existing_keys.add(row[0])
    
    found_strings = set()
    
    # 1. Parse JSON files for "name" and "description"
    for root, dirs, files in os.walk(project_dir):
        if ".godot" in root or ".git" in root:
            continue
            
        for file in files:
            if file.endswith('.json'):
                file_path = Path(root) / file
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        data = json.load(f)
                        
                    # Recursive function to find "name" and "description"
                    def search_dict(d):
                        if isinstance(d, dict):
                            for k, v in d.items():
                                if k in ["name", "description"] and isinstance(v, str):
                                    found_strings.add(v)
                                else:
                                    search_dict(v)
                        elif isinstance(d, list):
                            for item in d:
                                search_dict(item)
                                
                    search_dict(data)
                except Exception as e:
                    print(f"Error reading {file}: {e}")
                    
            # 2. Parse GDScript dictionaries for "name" and "description"
            elif file.endswith('.gd'):
                file_path = Path(root) / file
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        content = f.read()
                        
                    # matches "name": "something" or "description": "something"
                    matches = re.findall(r'\"(?:name|description)\"\s*:\s*\"([^"\\]*(?:\\.[^"\\]*)*)\"', content)
                    for m in matches:
                        val = m.replace('\\"', '"')
                        found_strings.add(val)
                except Exception as e:
                    print(f"Error reading {file}: {e}")

    new_strings = []
    for s in found_strings:
        s = s.strip()
        if not s: continue
        if s in existing_keys: continue
        if re.match(r'^[0-9\+\-\.\s/KMBT]+$', s): continue
        if s == "..." or s == "---": continue
        
        new_strings.append(s)

    new_strings.sort()
    
    if new_strings:
        with open(csv_path, 'a', encoding='utf-8', newline='') as f:
            writer = csv.writer(f)
            for s in new_strings:
                writer.writerow([s, ""])
        print(f"Added {len(new_strings)} data strings to strings.csv")
    else:
        print("No new data strings found.")

if __name__ == "__main__":
    extract_data_strings()
