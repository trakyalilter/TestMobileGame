extends Label

func setup(text_val: String, color: Color, start_pos: Vector2):
	text = text_val
	modulate = color
	
	# v55.1: Add random offset to prevent text overlapping
	var x_offset = randf_range(-40, 40)
	var y_offset = randf_range(-20, 20)
	start_pos += Vector2(x_offset, y_offset)
	
	position = start_pos
	
	# Rich Aesthetics: Scaling based on impact
	var target_scale = Vector2(1.2, 1.2)
	var anim_duration = 1.0
	
	if "DODGE" in text_val.to_upper():
		target_scale = Vector2(1.8, 1.8) # Massive pop for dodge
		anim_duration = 0.8 # Snappier
	elif "CRIT" in text_val.to_upper():
		target_scale = Vector2(2.0, 2.0)
		modulate = Color(1.0, 0.8, 0.0) # Golden crit
	
	# Animation (Pop + Float + Fade)
	scale = Vector2(0.3, 0.3)
	
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Move Up
	tween.tween_property(self, "position", start_pos + Vector2(0, -80), anim_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fade Out
	tween.tween_property(self, "modulate:a", 0.0, anim_duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	# Scale Pop
	tween.tween_property(self, "scale", target_scale, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	
	tween.chain().tween_callback(queue_free)
