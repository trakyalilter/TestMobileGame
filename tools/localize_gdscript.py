import os
import re
from pathlib import Path

def localize_gdscript_files():
    project_dir = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")
    
    # Regex to match:
    # 1. .text = , .tooltip_text = , .placeholder_text = 
    # 2. " or '
    # 3. String content (handling escaped quotes)
    # 4. Closing quote
    pattern = re.compile(r'(\.(?:text|tooltip_text|placeholder_text)\s*=\s*)(["\'])((?:(?!\2|\\).|\\.)*)\2')
    
    modified_count = 0
    file_count = 0
    
    def replacer(match):
        prefix = match.group(1)
        quote = match.group(2)
        content = match.group(3)
        
        # Avoid translating if string has no alphabetical characters (e.g. "0", "!", "---")
        # Also avoid if it's just BBCode tags like "[center]" or "[img=18]res://...[/img]"
        # A simple heuristic: must contain at least one word character that is not inside [] or res://
        
        # Strip bbcode tags temporarily to check if there's actual text
        text_without_bbcode = re.sub(r'\[.*?\]', '', content)
        text_without_paths = re.sub(r'res://\S+', '', text_without_bbcode)
        
        if not re.search(r'[a-zA-Z]', text_without_paths):
            return match.group(0) # Do not modify
            
        # Also, check if it's already wrapped in tr() or similar in the original line?
        # The regex only matches the exact assignment, so if it was `.text = tr("...")`
        # the prefix would be `.text = tr(` which doesn't match `.text = `. So we are safe!
        
        return f'{prefix}tr({quote}{content}{quote})'
        
    for root, dirs, files in os.walk(project_dir):
        if ".godot" in root or ".git" in root:
            continue
            
        for file in files:
            if file.endswith('.gd'):
                file_path = Path(root) / file
                
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        lines = f.readlines()
                        
                    changed = False
                    for i in range(len(lines)):
                        original = lines[i]
                        # Don't apply if line already contains tr(
                        if 'tr(' in original:
                            continue
                            
                        modified = pattern.sub(replacer, original)
                        if modified != original:
                            lines[i] = modified
                            changed = True
                            modified_count += 1
                            
                    if changed:
                        with open(file_path, 'w', encoding='utf-8') as f:
                            f.writelines(lines)
                        file_count += 1
                        print(f"Updated {file}")
                        
                except Exception as e:
                    print(f"Error processing {file_path}: {e}")
                    
    print(f"\nFinished! Wrapped {modified_count} strings across {file_count} files.")

if __name__ == "__main__":
    localize_gdscript_files()
