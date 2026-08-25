extends SceneTree
## Reads export_presets.cfg with the SAME parser the exporter uses, and prints
## what Godot actually got out of it.
##
## This exists because a wrong package name is the one mistake in this pipeline
## that cannot be undone: Play binds the app identity to the applicationId of the
## first upload, and a different id is a different app with no migration path for
## anyone who already installed it.
##
## The failure it caught: the generated preset carried `#` comment lines. Godot's
## ConfigFile takes `;` as its comment character, so the export silently fell back
## to the default `com.example.$genname` for every key that followed the comment —
## package name, app name and both keystores — while still producing a perfectly
## valid-looking 52 MB bundle. Nothing downstream of the export noticed.
##
## So the assert happens here, on the parsed preset, before the build: a run that
## would ship the wrong identity dies in seconds instead of after Gradle.
##
## Env:
##   EXPECT_PACKAGE  the applicationId the workflow intends to ship (required)
##   PRESET_NAME     preset section to read, default "preset.0"
##   REQUIRE_KEYS    comma-separated option keys that must be non-empty. The
##                   release pipeline passes its keystore keys here: they sit
##                   after the package name in the generated file, so they are the
##                   next casualty of a parse that stops early, and an unsigned
##                   release is a Play rejection rather than a silent one.

func _init() -> void:
	var expect := OS.get_environment("EXPECT_PACKAGE")
	var section := OS.get_environment("PRESET_NAME")
	if section == "":
		section = "preset.0"
	var opts := "%s.options" % section

	var cf := ConfigFile.new()
	var err := cf.load("res://export_presets.cfg")
	if err != OK:
		printerr("::error::Godot cannot parse export_presets.cfg (ConfigFile error %d). " % err
			+ "The exporter would see NO preset at all.")
		quit(1)
		return

	if not cf.has_section(opts):
		printerr("::error::export_presets.cfg has no [%s] section — the preset is malformed." % opts)
		_dump_sections(cf)
		quit(1)
		return

	# Print every key that survived the parse. When the parser stops early, this
	# list simply ends at the last key it read, which names the offending line.
	print("--- options Godot parsed out of [%s] ---" % opts)
	for k in cf.get_section_keys(opts):
		var v = cf.get_value(opts, k)
		if String(k).find("pass") >= 0:
			v = "***"
		print("  %s = %s" % [k, v])

	var got := String(cf.get_value(opts, "package/unique_name", ""))
	print("")
	print("package/unique_name as parsed: '%s'" % got)

	if expect == "":
		printerr("::error::EXPECT_PACKAGE is not set — refusing to pass a check that verifies nothing.")
		quit(1)
		return
	if got == "":
		printerr("::error::the preset Godot reads has NO package/unique_name, so the export "
			+ "would fall back to the default com.example.$genname. Expected '%s'." % expect)
		quit(1)
		return
	if got != expect:
		printerr("::error::the preset Godot reads says '%s', not '%s'." % [got, expect])
		quit(1)
		return

	for key in OS.get_environment("REQUIRE_KEYS").split(",", false):
		var k := String(key).strip_edges()
		if k == "":
			continue
		if String(cf.get_value(opts, k, "")) == "":
			printerr("::error::%s is empty in the parsed preset — a key the build depends on did not survive the parse." % k)
			quit(1)
			return

	print("OK  Godot parses the preset and reads package/unique_name = %s" % got)
	quit(0)

func _dump_sections(cf: ConfigFile) -> void:
	print("sections present: %s" % str(cf.get_sections()))
