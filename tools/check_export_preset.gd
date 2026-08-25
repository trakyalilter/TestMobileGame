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
## ConfigFile takes `;` as its comment character, and `#` is not a comment at all —
## the parse does NOT fail, which is what made this so quiet. Instead the comment
## text is folded into the name of the key that follows it, whitespace and all:
##
##     # The Play identity. PERMANENT from the first upload.
##     package/unique_name="com.horizon.idle"
##
## loads, with error code OK, as the single key
##
##     #ThePlayidentity.PERMANENTfromthefirstupload.package/unique_name
##
## So exactly one key is destroyed — the first one after the comment — and every
## key after that survives. Here that key was package/unique_name, so the export
## fell back to the default com.example.$genname while signing, versions and
## architectures all applied normally and a perfectly valid 52 MB bundle came out.
## Nothing downstream of the export noticed.
##
## So the assert happens here, on the parsed preset, before the build: a run that
## would ship the wrong identity dies in seconds instead of after Gradle.
##
## Env:
##   EXPECT_PACKAGE  the applicationId the workflow intends to ship (required)
##   PRESET_NAME     preset section to read, default "preset.0"
##   REQUIRE_KEYS    comma-separated option keys that must be non-empty. The
##                   release pipeline passes its keystore keys here, since an
##                   unsigned or wrongly-signed release is a Play rejection.
##                   Values may be of any type — read them with str(), never
##                   String(), which has no constructor for a bool and throws.
##                   A throw inside _init aborts before quit() runs, and the
##                   process then hangs rather than failing; the workflow wraps
##                   this call in `timeout` so that can never wedge a job.

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

	# Print every key as Godot named it. A '#' line shows up here as a mangled key
	# with the comment text welded to its front, which points straight at the
	# offending line instead of leaving a value mysteriously absent.
	print("--- options Godot parsed out of [%s] ---" % opts)
	for k in cf.get_section_keys(opts):
		var v = cf.get_value(opts, k)
		if str(k).find("pass") >= 0:
			v = "***"
		print("  %s = %s" % [k, v])

	var got := str(cf.get_value(opts, "package/unique_name", ""))
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
		var k := str(key).strip_edges()
		if k == "":
			continue
		if str(cf.get_value(opts, k, "")) == "":
			printerr("::error::%s is empty in the parsed preset — a key the build depends on did not survive the parse." % k)
			quit(1)
			return

	print("OK  Godot parses the preset and reads package/unique_name = %s" % got)
	quit(0)

func _dump_sections(cf: ConfigFile) -> void:
	print("sections present: %s" % str(cf.get_sections()))
