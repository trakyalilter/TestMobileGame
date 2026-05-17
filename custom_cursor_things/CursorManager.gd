extends Node
## CursorManager — autoload singleton for game-wide custom cursor.
##
## Setup:
##   Project > Project Settings > Autoload
##   Add this script with name "CursorManager", Enable = true.
##
## Two ways to use it once installed:
##
## 1. AUTOMATIC (recommended for 90% of cases):
##    Set any Control node's `mouse_default_cursor_shape` in the inspector.
##    Button defaults to POINTING_HAND, so every button gets the pointer
##    cursor for free. Set locked buttons to FORBIDDEN. No code needed.
##
## 2. MANUAL (for in-game cursor changes during gameplay):
##    CursorManager.set_state(CursorManager.State.WAIT)
##    CursorManager.set_state(CursorManager.State.DEFAULT)
##
## Notes:
##   - Cursor textures are 64x64 with hotspot at center (32,32).
##   - On web, max cursor size is 128x128. We're well under.
##   - This uses the HARDWARE cursor path (zero input lag) — never
##     fall back to a Sprite2D following the mouse, it adds a frame
##     of latency that players feel even if they can't articulate it.

enum State { DEFAULT, POINTER, FORBIDDEN, WAIT }

# Adjust these paths to wherever you put the PNGs in your project.
const CURSOR_DEFAULT   := preload("res://assets/cursors/cursor_default.png")
const CURSOR_POINTER   := preload("res://assets/cursors/cursor_pointer.png")
const CURSOR_FORBIDDEN := preload("res://assets/cursors/cursor_forbidden.png")
const CURSOR_WAIT      := preload("res://assets/cursors/cursor_wait.png")

# Hotspot = the pixel inside the image that represents the actual click
# point. For centered reticles, this is the middle of the image.
const HOTSPOT := Vector2(32, 32)

var _current_state: State = State.DEFAULT


func _ready() -> void:
	# Register all four cursor textures against Godot's built-in cursor
	# shape slots. This is the trick that makes Control nodes work
	# automatically — any Control with mouse_default_cursor_shape set
	# will pick up the right texture without per-node wiring.
	Input.set_custom_mouse_cursor(CURSOR_DEFAULT,   Input.CURSOR_ARROW,         HOTSPOT)
	Input.set_custom_mouse_cursor(CURSOR_POINTER,   Input.CURSOR_POINTING_HAND, HOTSPOT)
	Input.set_custom_mouse_cursor(CURSOR_FORBIDDEN, Input.CURSOR_FORBIDDEN,     HOTSPOT)
	Input.set_custom_mouse_cursor(CURSOR_WAIT,      Input.CURSOR_WAIT,          HOTSPOT)
	Input.set_custom_mouse_cursor(CURSOR_WAIT,      Input.CURSOR_BUSY,          HOTSPOT)

	# Start in default state.
	set_state(State.DEFAULT)


## Force the cursor into a specific state from code. Use this for moments
## that aren't tied to a Control node hover — prestige animations, save
## loads, scene transitions, "you can't afford this" feedback after a click.
func set_state(state: State) -> void:
	_current_state = state
	match state:
		State.DEFAULT:   Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		State.POINTER:   Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND)
		State.FORBIDDEN: Input.set_default_cursor_shape(Input.CURSOR_FORBIDDEN)
		State.WAIT:      Input.set_default_cursor_shape(Input.CURSOR_WAIT)


func get_state() -> State:
	return _current_state


## Convenience: run something with the WAIT cursor, then snap back to
## DEFAULT. Useful for prestige sequences and async loads.
##
## Example:
##   await CursorManager.with_wait(prestige_sequence())
func with_wait(awaitable) -> Variant:
	var prev := _current_state
	set_state(State.WAIT)
	var result = await awaitable
	set_state(prev)
	return result
