import os
from pathlib import Path

repo = Path(r"c:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot")

def replace_in_file(rel_path, old, new):
    p = repo / rel_path
    if p.exists():
        c = p.read_text(encoding="utf-8")
        if old in c:
            p.write_text(c.replace(old, new), encoding="utf-8")
            print(f"Replaced in {rel_path}: {old.strip()} -> {new.strip()}")
        else:
            print(f"Not found in {rel_path}: {old.strip()}")

replace_in_file(
    r"scripts\ui\designer_slot_widget.gd",
    'type_lbl.text = tr("%s %d") % [slot_type.to_upper(), _get_type_number()]',
    'type_lbl.text = tr("%s %d") % [tr(slot_type.to_upper()), _get_type_number()]'
)

replace_in_file(
    r"scripts\ui\info_card.gd",
    'type_lbl.text = tr("MATRIX CORE · %s SLOT") % _host_slot_ctx.to_upper()',
    'type_lbl.text = tr("MATRIX CORE · %s SLOT") % tr(_host_slot_ctx.to_upper())'
)

print("Done.")
