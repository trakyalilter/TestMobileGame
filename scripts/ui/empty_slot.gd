extends PanelContainer

func _ready():
	var frame = StyleBoxFlat.new()
	frame.bg_color = Color(0.05, 0.05, 0.07, 0.4) # Very faint
	frame.set_border_width_all(1)
	frame.border_color = Color(0.2, 0.3, 0.4, 0.2) # Dim blue tint
	frame.set_corner_radius_all(2)
	
	# Clean, hollow frame for empty space
	add_theme_stylebox_override("panel", frame)
