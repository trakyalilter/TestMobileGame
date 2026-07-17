import re
from pathlib import Path
import json

repo = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")

def replace_in_file(rel_path, old, new):
    p = repo / rel_path
    if p.exists():
        c = p.read_text(encoding="utf-8")
        if old in c:
            p.write_text(c.replace(old, new), encoding="utf-8")
            print(f"Replaced in {rel_path}: {old.strip()} -> {new.strip()}")

# atlas_page.gd
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"VALUE %s %s" %',
    'tr("VALUE %s %s") %')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"OWNED %s" %',
    'tr("OWNED %s") %')

# research_detail_modal.gd
replace_in_file(r"scripts\ui\research_detail_modal.gd",
    '["[color=%s]COST[/color]" % HDR_COL]',
    '["[color=%s]%s[/color]" % [HDR_COL, tr("COST")]]')
replace_in_file(r"scripts\ui\research_detail_modal.gd",
    '["[color=%s]NEXT LEVEL COST[/color]" % HDR_COL]',
    '["[color=%s]%s[/color]" % [HDR_COL, tr("NEXT LEVEL COST")]]')

# designer_slot_widget.gd
p = repo / r"scripts\ui\designer_slot_widget.gd"
if p.exists():
    c = p.read_text(encoding="utf-8")
    c = c.replace(
        'body += "[color=#%s]COST[/color]     [b][color=#%s]%d[/color][/b]  Spare Parts\\n" % [dim_hex, warn_hex, parts_cost]',
        'body += "[color=#%s]%s[/color]     [b][color=#%s]%d[/color][/b]  %s\\n" % [dim_hex, tr("COST"), warn_hex, parts_cost, tr("Spare Parts")]'
    )
    c = c.replace(
        'body += "[color=#%s]IN STOCK[/color]     [b][color=#%s]%d[/color][/b]" % [dim_hex, have_hex, have]',
        'body += "[color=#%s]%s[/color]     [b][color=#%s]%d[/color][/b]" % [dim_hex, tr("IN STOCK"), have_hex, have]'
    )
    c = c.replace(
        'body += "\\n\\n[color=#%s][b]NOT ENOUGH SPARE PARTS[/b][/color]" % neg_hex',
        'body += "\\n\\n[color=#%s][b]%s[/b][/color]" % [neg_hex, tr("NOT ENOUGH SPARE PARTS")]'
    )
    p.write_text(c, encoding="utf-8")
    print("Replaced in scripts\\ui\\designer_slot_widget.gd")

# research_page.gd
replace_in_file(r"scripts\ui\research_page.gd",
    'tabs.add_child(tab_root)',
    'tabs.add_child(tab_root)\n\t\ttabs.set_tab_title(tab_root.get_index(), tr(tab_name))')

print("Finished second batch replacements.")
