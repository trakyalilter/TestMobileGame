extends Node

# Renders the offline-boot modal in a target locale and reports any drawn text
# that is still the English source.
#
# The static tr()-scan could not see this screen: its strings are raw literals
# handed to label helpers, and three of them were .to_upper()'d BEFORE
# auto-translate ran, so the lookup key was the uppercased English. Reading the
# rendered labels is the only check that catches all of those.

const LOCALE := "tr"


func _ready() -> void:
	TranslationServer.set_locale(LOCALE)
	var modal: Node = load("res://scenes/ui/offline_boot_modal.tscn").instantiate()
	add_child(modal)
	if modal.has_method("debug_preview"):
		modal.debug_preview()
	for i in 30:
		await get_tree().process_frame

	var english: Array = []
	var shown: Array = []
	for n in _walk(modal):
		var s := ""
		if n is Label: s = (n as Label).text
		elif n is Button: s = (n as Button).text
		elif n is RichTextLabel: s = (n as RichTextLabel).get_parsed_text()
		s = s.strip_edges()
		if s == "" or not (n as Control).is_visible_in_tree(): continue
		# `text` holds the SOURCE for auto-translated Controls -- the translation
		# is applied at draw. atr() is what the player actually sees.
		s = n.atr(s)
		if s in shown: continue
		shown.append(s)
		# Precise test: the drawn text is a defect only if it is itself a CSV KEY
		# that HAS a translation -- i.e. the source leaked through instead of the
		# translation. Guessing "looks English" misfires on Turkish words that
		# happen to be plain ASCII (BAKIR, MANGANEZ).
		if TranslationServer.translate(s) != s:
			english.append(s)

	print("\n======== OFFLINE MODAL (%s) ========" % LOCALE)
	print("visible strings: %d" % shown.size())
	for s in shown:
		print("   %s" % s.replace("\n", " / ").substr(0, 76))
	print("\nstill-English (has a CSV row but rendered as source): %d" % english.size())
	for s in english:
		print("   !! %s" % s.substr(0, 70))
	get_tree().quit()


func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
