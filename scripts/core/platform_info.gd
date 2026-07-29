class_name PlatformInfo
extends RefCounted
## PlatformInfo — the single answer to "are we running on a phone?".
##
## Deliberately NOT an autoload: every entry point is static, so the core
## autoloads (GameState / CursorManager / ClickFX) can ask without caring about
## the autoload order in project.godot.
##
## The game is desktop-first (see CLAUDE.md). Every mobile-specific branch in
## this codebase goes through `is_touch()` or `is_handheld()`, so the whole
## Android surface is one grep away.

## Android's own guideline is 48dp; 44 canvas units at the handheld content
## scale below lands in the same place. Used by the density audit, not yet
## enforced globally — see docs/ANDROID_BUILD.md.
const TOUCH_TARGET_MIN_PX := 44.0

## Extra UI magnification applied on handhelds. The base viewport is a 1280x720
## desktop layout; on a 6" screen that puts body text near the legibility floor.
## 1.15 buys back the text without pushing the 16-button sidebar past the
## viewport height (16 x ~30 units = ~480, budget at 1.15 is ~626).
const HANDHELD_CONTENT_SCALE := 1.15


static func is_android() -> bool:
	return OS.get_name() == "Android"


static func is_ios() -> bool:
	return OS.get_name() == "iOS"


## A phone or tablet — the platforms with an app lifecycle (pause/resume), a
## notch, and a hardware Back gesture.
static func is_handheld() -> bool:
	return is_android() or is_ios()


## True on handhelds, and on a desktop touchscreen with no mouse attached.
## A touch-capable laptop that still has a mouse stays on the desktop path.
static func is_touch() -> bool:
	if is_handheld():
		return true
	return DisplayServer.is_touchscreen_available() \
		and not DisplayServer.has_feature(DisplayServer.FEATURE_MOUSE)


## Notch / rounded-corner / gesture-bar insets as (left, top, right, bottom).
##
## `DisplayServer.get_display_safe_area()` reports raw device pixels; the game
## runs `stretch/mode=canvas_items`, so those have to be divided down into
## canvas units before they mean anything to a Control offset. Returns ZERO off
## handhelds and whenever the window size isn't known yet.
static func safe_area_insets(vp: Viewport) -> Vector4:
	if vp == null or not is_handheld():
		return Vector4.ZERO

	var win: Vector2i = DisplayServer.window_get_size()
	if win.x <= 0 or win.y <= 0:
		return Vector4.ZERO

	# Fullscreen is the only mode Android gives us, so screen space and window
	# space are the same rect here.
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO

	var left := float(maxi(safe.position.x, 0))
	var top := float(maxi(safe.position.y, 0))
	var right := float(maxi(win.x - (safe.position.x + safe.size.x), 0))
	var bottom := float(maxi(win.y - (safe.position.y + safe.size.y), 0))

	var canvas: Vector2 = vp.get_visible_rect().size
	var sx: float = canvas.x / float(win.x)
	var sy: float = canvas.y / float(win.y)
	return Vector4(left * sx, top * sy, right * sx, bottom * sy)
