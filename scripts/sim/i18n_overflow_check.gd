extends Node

# Locale overflow sweep. Boots the real UI in a target locale, walks every page,
# and reports any Label/Button whose drawn text is wider than the box it sits in.
# Controls auto-translate at draw time, so `text` is still the English key --
# every measurement goes through TranslationServer.translate().

const LOCALE := "tr"
const PAGES := ["gathering", "processing", "infrastructure", "shipyard", "research",
	"combat", "mission", "designer", "inventory", "options", "atlas", "bounty"]

var _hits: Array = []
var _seen: Dictionary = {}


func _ready() -> void:
	TranslationServer.set_locale(LOCALE)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	for i in 8:
		await get_tree().process_frame

	for pg in PAGES:
		if not main.has_method("switch_to"):
			print("!! main has no switch_to()"); break
		main.switch_to(pg)
		for i in 6:
			await get_tree().process_frame
		_scan(main, pg)

	_report()
	get_tree().quit()


func _scan(root: Node, page: String) -> void:
	for n in _walk(root):
		if not (n is Control): continue
		var c: Control = n
		if not c.is_visible_in_tree(): continue
		if c.size.x <= 4.0: continue

		var raw: String = ""
		var avail: float = c.size.x
		if c is Label:
			# Wrapping labels reflow instead of overflowing -- not a defect.
			if (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF: continue
			raw = (c as Label).text
		elif c is Button:
			raw = (c as Button).text
			var sb: StyleBox = c.get_theme_stylebox("normal")
			if sb: avail -= sb.content_margin_left + sb.content_margin_right
			var ic: Texture2D = (c as Button).icon
			if ic: avail -= ic.get_width() + 4.0
		else:
			continue
		if raw.strip_edges() == "": continue

		var shown: String = TranslationServer.translate(raw)
		if shown == raw: continue          # untranslated -- English already fits

		var font: Font = c.get_theme_font("font")
		if font == null: continue
		var fs: int = c.get_theme_font_size("font_size")
		var w: float = font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if w <= avail + 1.0: continue

		var key: String = "%s|%s" % [c.get_path(), raw]
		if _seen.has(key): continue
		_seen[key] = true
		_hits.append({
			"page": page, "node": String(c.name), "cls": c.get_class(),
			"en": raw, "tr": shown, "need": w, "have": avail,
			"over": w - avail, "clip": _clips(c), "fs": fs, "path": String(c.get_path()),
		})


func _clips(c: Control) -> String:
	var clip: bool = (c.clip_text if c is Label else (c.clip_text if c is Button else false))
	var ell: bool = false
	if c is Label: ell = (c as Label).text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS
	elif c is Button: ell = (c as Button).text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS
	if clip and ell: return "ellipsis"
	if clip: return "HARD-CUT"
	return "spills"


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for ch in n.get_children():
		out.append_array(_walk(ch))
	return out


func _report() -> void:
	print("\n================ %s OVERFLOW SWEEP ================" % LOCALE.to_upper())
	if _hits.is_empty():
		print("no overflow found"); return
	_hits.sort_custom(func(a, b): return a["over"] > b["over"])
	var by_mode: Dictionary = {}
	for h in _hits:
		by_mode[h["clip"]] = int(by_mode.get(h["clip"], 0)) + 1
		print("%-12s %-9s over %4.0fpx  fs %2d  need %4.0f have %4.0f  %-26s -> %s" % [
			h["page"], h["clip"], h["over"], h["fs"], h["need"], h["have"],
			h["en"].substr(0, 26), h["tr"].substr(0, 30)])
		print("               %s" % h["path"].right(72))
	print("\n%d overflowing (%s)" % [_hits.size(), by_mode])
