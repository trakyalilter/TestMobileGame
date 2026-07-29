extends Node
## CursorManager — autoload singleton for game-wide custom cursor.
##
## Two ways to use it once installed:
##
## 1. AUTOMATIC: every BaseButton is auto-upgraded to the pointer cursor
##    (see _apply_button_cursor). No per-node wiring needed.
##
## 2. MANUAL (in-game cursor changes during gameplay):
##    CursorManager.set_state(CursorManager.State.WAIT)
##    CursorManager.set_state(CursorManager.State.DEFAULT)
##
## Size:
##   Source art is 64x64. The cursor is re-baked at the player's chosen
##   size (persisted in GameState.game_settings["cursor_size"]) by
##   resampling the image and scaling the hotspot to match. This keeps the
##   HARDWARE cursor path (zero input lag) — never fall back to a Sprite2D
##   following the mouse, it adds a frame of latency players can feel.

enum State { DEFAULT, POINTER, FORBIDDEN, WAIT }

const CURSOR_DEFAULT   := preload("res://assets/cursors/cursor_default.png")
const CURSOR_POINTER   := preload("res://assets/cursors/cursor_pointer.png")
const CURSOR_FORBIDDEN := preload("res://assets/cursors/cursor_forbidden.png")
const CURSOR_WAIT      := preload("res://assets/cursors/cursor_wait.png")

# Selectable sizes (pixels). Source art is 64; these downscale cleanly.
const SIZE_SMALL  := 24
const SIZE_MEDIUM := 36
const SIZE_LARGE  := 52
const DEFAULT_SIZE := SIZE_MEDIUM

# Which source texture feeds each built-in cursor slot. WAIT doubles as BUSY.
# All four are universal — the same cursor set runs on every page. (Per-page
# idle cursors were removed; the default ARROW cursor is now used everywhere.)
var _sources := {
	Input.CURSOR_ARROW:         CURSOR_DEFAULT,
	Input.CURSOR_POINTING_HAND: CURSOR_POINTER,
	Input.CURSOR_FORBIDDEN:     CURSOR_FORBIDDEN,
	Input.CURSOR_WAIT:          CURSOR_WAIT,
	Input.CURSOR_BUSY:          CURSOR_WAIT,
}

var _current_state: State = State.DEFAULT
var _size: int = DEFAULT_SIZE


func _ready() -> void:
	# ANDROID: there is no pointer to draw. Baking four cursor images and then
	# walking the whole tree (plus every node_added for the rest of the session)
	# to set a cursor shape nothing renders is pure boot cost on the platform
	# that can least afford it. Bail before any of it.
	if PlatformInfo.is_touch():
		return

	# Persisted size. GameState is declared earlier in project.godot's
	# autoload list, so its save (and game_settings) is already loaded.
	_bake(int(GameState.game_settings.get("cursor_size", DEFAULT_SIZE)))

	set_state(State.DEFAULT)

	# Auto-pointer for every button. Godot 4 defaults Control.mouse_default
	# _cursor_shape to ARROW, so buttons would show the default cursor, not
	# the pointer. Upgrade any button still on the default shape to POINTING
	# _HAND — both for buttons already in the tree and any created later
	# (this codebase builds most buttons in code). Buttons that deliberately
	# set another shape (e.g. FORBIDDEN on a locked node) are left alone.
	get_tree().node_added.connect(_apply_button_cursor)
	_scan_existing(get_tree().root)


## Re-bake all cursors at `px` size and register them. Call this live from
## the Options screen; it takes effect immediately. No-op on touch platforms
## (the Sys Config cursor row is hidden there — see options_page).
func apply_size(px: int) -> void:
	if PlatformInfo.is_touch():
		return
	_bake(px)


func get_size() -> int:
	return _size


func _bake(px: int) -> void:
	px = clampi(px, 12, 128)  # OS hardware-cursor ceiling is ~128
	_size = px
	for shape in _sources:
		_apply_cursor(shape, _sources[shape])


# Resize `tex` to the current cursor size and register it against `shape`
# with a centred hotspot.
func _apply_cursor(shape: int, tex: Texture2D) -> void:
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	if img.get_width() != _size or img.get_height() != _size:
		img.resize(_size, _size, Image.INTERPOLATE_LANCZOS)
	Input.set_custom_mouse_cursor(ImageTexture.create_from_image(img), shape, Vector2(_size, _size) * 0.5)


func _scan_existing(n: Node) -> void:
	_apply_button_cursor(n)
	for c in n.get_children():
		_scan_existing(c)


func _apply_button_cursor(n: Node) -> void:
	if n is BaseButton and n.mouse_default_cursor_shape == Control.CURSOR_ARROW:
		n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


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


## Convenience: run something with the WAIT cursor, then snap back.
##   await CursorManager.with_wait(prestige_sequence())
func with_wait(awaitable) -> Variant:
	var prev := _current_state
	set_state(State.WAIT)
	var result = await awaitable
	set_state(prev)
	return result
