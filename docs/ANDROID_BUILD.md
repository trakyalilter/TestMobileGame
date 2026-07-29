# Horizon Idle — Android build

Status: **the Android target now builds and installs.** Before this pass there
was no Android export preset, no touch/lifecycle handling, and no mobile
settings anywhere in the project — `docs/HANDOFF.md` logged mobile as PARKED.
This document covers what shipped, how to build it, and what is deliberately
still open.

Verified against **Godot 4.5.1-stable**, export templates 4.5.1-stable,
Android build-tools 34.0.0, platform-tools 37. Output: a signed 96 MB
arm64-v8a APK, manifest confirmed `sensorLandscape` / minSdk 24 / targetSdk 35
/ zero permissions.

---

## Building

**One-time setup**

1. Install the 4.5.1 export templates (Editor → Manage Export Templates).
2. Install an Android SDK with `platform-tools` and `build-tools;34.0.0`.
3. Generate a debug keystore:
   ```
   keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android \
     -keystore debug.keystore -storepass android \
     -dname "CN=Android Debug,O=Android,C=US" -validity 9999 -deststoretype pkcs12
   ```
4. Editor Settings → Export → Android: set `android_sdk_path`,
   `debug_keystore`, `debug_keystore_user` (`androiddebugkey`),
   `debug_keystore_pass` (`android`).

**Build**

```
godot --headless --path <project> --export-debug "Android" out.apk   # or let CI do it
godot --headless --path <project> --export-release "Android" out.apk
```

A **release** build additionally needs a real keystore. Those credentials are
NOT in `export_presets.cfg` on purpose — the `keystore/release*` fields are
left empty so nothing signable ends up in git. Supply them via Editor Settings
or the `GODOT_ANDROID_KEYSTORE_RELEASE_*` environment variables.

**Play Store (AAB)** — the committed preset produces a sideloadable APK
(`gradle_build/use_gradle_build=false`). For an AAB, install the Android build
template (Project → Install Android Build Template), then set
`gradle_build/use_gradle_build=true` and `gradle_build/export_format=1`.

---

## What the preset commits to

| Setting | Value | Why |
|---|---|---|
| `package/unique_name` | `com.haides.horizonidle` | the full game; the demo repo uses `.demo` so both can be installed side by side |
| `architectures` | arm64-v8a only | armeabi-v7a is a dead 32-bit tail; dropping it halves the APK |
| `screen/immersive_mode` | true | full-bleed; the safe-area code below keeps UI off the notch |
| permissions | none | the game is fully offline; asking for nothing is a store-listing asset |
| `texture_format/etc2_astc` | true | the mobile GPU format (paired with the matching import setting) |

---

## What changed in the game

### Orientation and scaling — `project.godot`

`window/handheld/orientation=4` (Sensor Landscape). The shell is a landscape
multi-column layout (188px sidebar + content); **portrait is a redesign, not a
rotation**, so it is locked out rather than shipped broken.

`window/stretch/aspect="expand"` gives a 20:9 phone extra canvas *width*
instead of letterboxing the 16:9 desktop layout. The UI is anchor/container
driven, so the sidebar stays pinned and pages absorb the surplus.

`PlatformInfo.HANDHELD_CONTENT_SCALE` (1.15) magnifies the UI on handhelds
only, applied in `main.gd::_apply_handheld_content_scale` and `main_menu.gd`.
1.15 is the ceiling that still fits the 16-button sidebar: 16 × ~30 units =
~480, and the budget at 1.15 is ~626.

### Touch input — `project.godot`

`pointing/emulate_mouse_from_touch=true` is pinned explicitly. It is Godot's
default, but the entire UI is `InputEventMouseButton`-only (research pan,
building cards, module `gui_input`) — turning it off silently kills every tap,
which is far too quiet a failure to leave implicit.

`pointing/emulate_touch_from_mouse` stays **off**: nothing in the codebase
reads `InputEventScreenTouch`, so mouse→touch synthesis could only double-fire.

### Safe area — `main.gd`

`_apply_safe_area()` insets the `HBoxContainer` shell by the device's notch /
gesture-bar rect, re-running on rotation via `size_changed`. The `Background`
ColorRect is deliberately *not* inset, so the notch region shows the game's
backdrop rather than a black bar.

`PlatformInfo.safe_area_insets()` converts `DisplayServer.get_display_safe_area()`
from raw device pixels into canvas units — the project runs
`stretch/mode=canvas_items`, so the raw rect is meaningless to a Control offset
without that division.

### Hardware Back — `main.gd`, `main_menu.gd`

`application/config/quit_on_go_back=false`, so Back arrives as
`NOTIFICATION_WM_GO_BACK_REQUEST` instead of killing the process mid-modal.

Back closes the topmost overlay; with nothing left to dismiss it quits (the
save is already written on the same notification by `GameState`). On the title
screen Back is Exit.

The dismissal contract is narrow on purpose: **a dismissible overlay is a
visible `Control` exposing `close()`.** That excludes the permanent shell
furniture on `ModalLayer` (notification stack, coach overlay, hint arrow)
without name-matching any of it. `close()` was added to
`offline_boot_modal.gd` and `research_detail_modal.gd` to join the contract;
`loot_filter_modal.gd` already had one. **Any new modal must expose `close()`
or Back will quit straight past it.**

### App lifecycle — `game_state.gd`

This is the part an idle game actually lives or dies on.

**Save on pause.** Android can kill a backgrounded app with no further
notification — `NOTIFICATION_WM_CLOSE_REQUEST` never arrives. Without a
`NOTIFICATION_APPLICATION_PAUSED` handler, every home-button press risks
losing up to `PROD_SAVE_INTERVAL` (60s) of progress, and on mobile that is
*every session*.

**Credit the absence on resume.** A pause/resume never re-boots, so
`load_game`'s `last_save_time` diff — the only path that paid out absence —
never runs. `_resume_from_background()` mirrors it exactly: same 10s threshold,
same 24h cap × warp-tree multiplier, same consume-the-window save (v137 FIX
#34). Without it, hours of backgrounded phone silently evaporate.

**Clamp the resume frame.** `MAX_FRAME_DELTA` (1.0s, scaled by
`Engine.time_scale` so the 16× debug speed is not mistaken for a stall). A
resumed app hands `_process` a delta covering the whole absence; managers
accrue per-second off it, so an unclamped frame would pay the entire gap out at
**full active rates on top of** the offline payout for the same window. This
also fixes the equivalent desktop case (laptop sleep, debugger breakpoint).

**Re-anchor the playtime clock.** `Time.get_ticks_msec()` keeps counting while
the OS has the app suspended, so `total_playtime` would bill the absence as
active play.

### Cost removal — `cursor_manager.gd`, `options_page.gd`

`CursorManager` bails immediately on touch platforms. It otherwise bakes four
cursor images and walks the entire tree — plus every `node_added` for the rest
of the session — to set a cursor shape nothing renders. The Sys Config "Cursor
Size" row is hidden on touch for the same reason.

---

## CI

`.github/workflows/android-release.yml` builds and publishes every push to
MissionFlow. Read its header for the one manual step needed to publish to
`trakyalilter/TestMobileGame` rather than this repo.

## Regression probe

```
godot --headless --path <project> res://scenes/android_lifecycle_check.tscn
```

8 assertions, exit code 0 on pass: platform detection and null-safety, the
delta clamp (both that it binds at 3600s and that a 16ms frame passes
untouched), resume crediting, the offline cap, the sub-threshold no-op, resume
with no recorded pause, and the playtime re-anchor. **Currently ALL PASS.**
CI runs it on every build and fails the job on any FAIL.

Run it alongside the existing probes on any change to the save, offline, or
reset paths.

---

## Deliberately still open

Nothing below is a build blocker; all of it is a playtest-on-device job that
this pass could not do without hardware.

1. **Touch-target density.** `PlatformInfo.TOUCH_TARGET_MIN_PX` (44) is
   defined but **not enforced**. A blanket bump is wrong here: 16 sidebar
   buttons × 44 = 704 units against a 720-unit viewport, so the rail would
   overflow. The sidebar needs a real layout decision (scroll, icon rail, or a
   drawer) before any global minimum can land. `content_scale_factor` 1.15 is
   the interim mitigation.
2. **380px density audit** — inventory grid (190 materials / 28 slots), recipe
   list (~100), loot filter (5 rarity × 6 slot × 4 weapon). Tracked in
   `docs/SANITY_CHECKLIST.md` → Mobile Readiness.
3. **Offline replay is not closed-form.** `calculate_offline` loops
   per-action/per-kill (~28,800 iterations at 24h gathering, ~8,640 combat).
   On desktop that is a hitch; on a low-end phone it is an ANR risk — and it
   now runs on **resume**, i.e. at the re-engagement beat, not just at boot.
   This is the highest-value remaining mobile fix. Also in the checklist.
4. **Modals parented outside `ModalLayer` and the current page** are invisible
   to the Back handler. Only `loot_filter_modal` does this today (parented to
   `combat_page`) and it is covered; new ones need to follow suit.
5. **AAB / Play Store signing** — release keystore and the gradle-build switch
   above.
6. **Launcher icons** — `launcher_icons/*` are empty, so Godot falls back to
   its default icon. Needs a 432×432 adaptive foreground/background pair.
