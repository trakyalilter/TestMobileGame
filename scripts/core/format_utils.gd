class_name FormatUtils
extends Node

const SUFFIXES = ["", "K", "M", "B", "T", "q", "Q", "s", "S", "O", "N", "d"]

static func format_number(val: float) -> String:
	if val < 1000:
		if val > 0.0 and val < 1.0:
			return "%.2f" % val
		return str(int(val))
	
	# PHASE 47: Scientific Diegesis (Sensor Reading Logic)
	# Use standard suffixes for K, shift to scientific for M+
	if val >= 1000000.0:
		var exponent = floor(log(val) / log(10.0))
		var base = val / pow(10, exponent)
		# Format: 1.25e6
		return "%.2fe%d" % [base, int(exponent)]
		
	var exp = int(floor(log(val) / log(1000)))
	var suffix = SUFFIXES[min(exp, SUFFIXES.size() - 1)]
	var scaled = val / pow(1000, exp)
	
	if scaled >= 100:
		return "%.0f%s" % [scaled, suffix]
	elif scaled >= 10:
		return "%.1f%s" % [scaled, suffix]
	else:
		return "%.2f%s" % [scaled, suffix]

const STAT_LABELS = {
	"atk_energy": "ENERGY ATK",
	"atk_kinetic": "KINETIC ATK",
	"energy_load": "POWER DRAW",
	"max_shield": "SHIELD",
	"shield_regen": "REGEN",
	"def": "ARMOR",
	"hp": "HULL",
	"eva": "EVASION",
	"energy_capacity": "CAPACITY",
	"atk_speed_mult": "SPEED",
	"shield_regen_mult": "REGEN+",
	"energy_gen": "GEN"
}

static func format_stat_label(key: String) -> String:
	var key_lower = key.to_lower()
	return STAT_LABELS.get(key_lower, key.replace("_", " ").to_upper())

static func format_stat_value(key: String, val: float) -> String:
	if key.to_lower().ends_with("_mult"):
		return "+%d%%" % int(val * 100)
	return format_number(val)

static func format_time(seconds: float) -> String:
	if seconds < 60:
		return "%.1fs" % seconds
	elif seconds < 3600:
		var mins = int(seconds / 60)
		var secs = int(seconds) % 60
		return "%dm %ds" % [mins, secs]
	else:
		var hrs = int(seconds / 3600)
		var mins = int(seconds / 60) % 60
		return "%dh %dm" % [hrs, mins]
