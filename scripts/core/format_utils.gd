class_name FormatUtils
extends Node

const SUFFIXES = ["", "K", "M", "B", "T", "q", "Q", "s", "S", "O", "N", "d"]

static func format_number(val: float) -> String:
	if val < 1000:
		if val > 0.0 and val < 1.0:
			return "%.2f" % val
		
		# Prevent deceptive rounding (e.g. 4.8 displayed as 5)
		# Add tiny epsilon to bypass float point precision loss
		var diff = abs(val - round(val))
		if diff > 0.01 and diff < 0.99:
			# Use floor with epsilon to chop off purely partial fractions over .01
			var safe_val = val + 0.000001
			return "%.1f" % (floor(safe_val * 10.0) / 10.0)
			
		return str(int(round(val)))
	
	# 1.25M instead of 1.25e6 per User Request
	var exp = int(floor(log(val) / log(1000)))
	
	# Fallback to scientific only if we exceed supported suffixes (e.g. > 1e36)
	if exp >= SUFFIXES.size():
		var exponent = floor(log(val) / log(10.0))
		var base = val / pow(10, exponent)
		return "%.2fe%d" % [base, int(exponent)]
		
	var suffix = SUFFIXES[min(exp, SUFFIXES.size() - 1)]
	var scaled = (val / pow(1000, exp)) + 0.000001
	
	if scaled >= 100:
		return "%.0f%s" % [floor(scaled), suffix]
	elif scaled >= 10:
		return "%.1f%s" % [floor(scaled * 10.0) / 10.0, suffix]
	else:
		return "%.2f%s" % [floor(scaled * 100.0) / 100.0, suffix]

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

static func format_stat_value(key: String, val: float) -> String:
	var k_low = key.to_lower()
	if k_low.ends_with("_mult") or k_low.ends_with("_bonus") or k_low == "jamming_strength" or k_low == "crit_chance":
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
