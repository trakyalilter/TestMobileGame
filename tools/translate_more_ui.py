import re
from pathlib import Path
import json

repo = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")

missing_keys = set()

# 1. Look for English text that needs tr()
def replace_in_file(rel_path, old, new):
    p = repo / rel_path
    if p.exists():
        c = p.read_text(encoding="utf-8")
        if old in c:
            p.write_text(c.replace(old, new), encoding="utf-8")
            print(f"Replaced in {rel_path}: {old.strip()} -> {new.strip()}")

# atlas_page.gd
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"rate": "%.0f%% chance" % (entry[1] * 100)',
    '"rate": tr("%.0f%% chance") % (entry[1] * 100)')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"rate": "%d-%d per kill" % [entry[1], entry[2]],',
    '"rate": tr("%d-%d per kill") % [entry[1], entry[2]],')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"name": enemy_name + " (Rare)",',
    '"name": enemy_name + tr(" (Rare)"),')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '_make_chip("NEEDS RARE GEAR", Color(1.0, 0.76, 0.30), 9)',
    '_make_chip(tr("NEEDS RARE GEAR"), Color(1.0, 0.76, 0.30), 9)')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '_make_caption(uses_list, "RARE DROPS", UITheme.COLORS["warning"])',
    '_make_caption(uses_list, tr("RARE DROPS"), UITheme.COLORS["warning"])')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '_make_caption(uses_list, "MODULE DROPS (%d%%)" % int(drop_chance * 100)',
    '_make_caption(uses_list, tr("MODULE DROPS (%d%%)") % int(drop_chance * 100)')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"rate": "%d per cycle" %',
    '"rate": tr("%d per cycle") %')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '_make_caption(sources_list, "SOURCED FROM"',
    '_make_caption(sources_list, tr("SOURCED FROM")')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '_make_caption(uses_list, "CONSUMED BY"',
    '_make_caption(uses_list, tr("CONSUMED BY")')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"%s (%s)" % [source["name"], source["rate"]]',
    '"%s (%s)" % [tr(source["name"]), tr(source["rate"])]')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"%s (%s)" % [use["name"], use["rate"]]',
    '"%s (%s)" % [tr(use["name"]), tr(use["rate"])]')
replace_in_file(r"scripts\ui\atlas_page.gd",
    '"%s (%s)" % [src["name"], src["rate"]]',
    '"%s (%s)" % [tr(src["name"]), tr(src["rate"])]')
replace_in_file(r"scripts\ui\atlas_page.gd",
    'tier_lbl.text = "T%d" % tier',
    'tier_lbl.text = tr("T%d") % tier')

# research_detail_modal.gd
replace_in_file(r"scripts\ui\research_detail_modal.gd",
    '["[color=%s]EFFECTS[/color]" % HDR_COL]',
    '["[color=%s]%s[/color]" % [HDR_COL, tr("EFFECTS")]]')
replace_in_file(r"scripts\ui\research_detail_modal.gd",
    '["[color=%s]UNLOCKS[/color]" % HDR_COL]',
    '["[color=%s]%s[/color]" % [HDR_COL, tr("UNLOCKS")]]')
replace_in_file(r"scripts\ui\research_detail_modal.gd",
    '"[color=%s]REQUIRES[/color]\\n" % HDR_COL',
    '"[color=%s]%s[/color]\\n" % [HDR_COL, tr("REQUIRES")]')
replace_in_file(r"scripts\ui\research_detail_modal.gd",
    'lines2.append("• " + str(u))',
    'lines2.append("• " + tr(str(u)))')
replace_in_file(r"scripts\ui\research_detail_modal.gd",
    '  [color=%s](cross-branch)[/color]" % HINT_COL)',
    '  [color=%s]%s[/color]" % [HINT_COL, tr("(cross-branch)")])')

# gathering_action_widget.gd
# %s%s: %s -> %s%s: %s (colon is fine, but check where rate is formed)

print("Finished replacements.")
