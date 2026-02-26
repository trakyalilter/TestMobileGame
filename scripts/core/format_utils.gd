class_name FormatUtils
extends Node

const SUFFIXES = ["", "K", "M", "B", "T", "q", "Q", "s", "S", "O", "N", "d"]

static func format_number(val: float) -> String:
	var abs_val = abs(val)
	var sign_str = "-" if val < 0 else ""

	if abs_val < 1000:
		if abs_val > 0.0 and abs_val < 1.0:
			return "%s%.2f" % [sign_str, abs_val]
		
		# Prevent deceptive rounding
		var diff = abs(abs_val - round(abs_val))
		if diff > 0.01 and diff < 0.99:
			var safe_val = abs_val + 0.000001
			return "%s%.1f" % [sign_str, floor(safe_val * 10.0) / 10.0]
			
		return "%s%s" % [sign_str, str(int(round(abs_val)))]
	
	# Suffix formatting
	var exp = int(floor(log(abs_val) / log(1000)))
	
	if exp >= SUFFIXES.size():
		var exponent = floor(log(abs_val) / log(10.0))
		var base = abs_val / pow(10, exponent)
		return "%s%.2fe%d" % [sign_str, base, int(exponent)]
		
	var suffix = SUFFIXES[min(exp, SUFFIXES.size() - 1)]
	var scaled = (abs_val / pow(1000, exp)) + 0.000001
	
	if scaled >= 100:
		return "%s%.0f%s" % [sign_str, floor(scaled), suffix]
	elif scaled >= 10:
		return "%s%.1f%s" % [sign_str, floor(scaled * 10.0) / 10.0, suffix]
	else:
		return "%s%.2f%s" % [sign_str, floor(scaled * 100.0) / 100.0, suffix]

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
	"energy_gen": "GEN",
	"jamming_strength": "JAMMING",
	"atk_speed_bonus": "COOLING"
}

static func format_stat_label(key: String) -> String:
	var key_lower = key.to_lower()
	return STAT_LABELS.get(key_lower, key.replace("_", " ").to_upper())

static func format_stat_value(key: String, val: Variant) -> String:
	if typeof(val) == TYPE_STRING:
		if not val.is_valid_float() and not val.is_valid_int():
			return val
	elif typeof(val) != TYPE_INT and typeof(val) != TYPE_FLOAT:
		return str(val)
		
	var f_val: float = float(val)
	var k_low = key.to_lower()
	if k_low.ends_with("_mult") or k_low.ends_with("_bonus") or k_low == "jamming_strength" or k_low == "crit_chance":
		return "+%d%%" % int(f_val * 100)
	return format_number(f_val)

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
