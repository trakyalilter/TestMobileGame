# FULL HEADLESS BOOT CHECK.
#
# The reliable smoke test for this project: --check-only is SYNTAX-only and misses
# undeclared locals and type errors, so the real check is booting the game and reading
# what the engine says.
#
# WHY THIS IS A SCRIPT AND NOT A GREP YOU RETYPE.
# The pattern lived as prose in four docs as
#     SCRIPT ERROR|not declared|Nonexistent function|Cannot infer
# and every one of the last three is a SCRIPT ERROR substring, so the whole thing only
# ever caught GDScript runtime faults. It matched none of:
#     ERROR:                 engine errors, including resource load failures
#     Failed to load / instantiate / open
#     USER ERROR:            push_error() from our own code
#     Invalid call / Invalid access / Invalid get index / Attempt to call
# A resource that fails to load produces ERROR: and nothing else, so a broken scene
# reference booted "clean". That is how the invalid-UID warnings in atlas_page.tscn and
# warp_page.tscn stayed unseen -- they only surfaced when a probe that instantiates
# main.tscn happened to print them.
#
# WARNINGS ARE REPORTED, NOT FAILED. A WARNING is Godot saying it recovered (the UID
# fallbacks resolve by text path and load fine). Failing on them would hand the repo
# another permanently-red check, which is how phase_gate_spike and bounty_check stopped
# being read. They print; the exit code ignores them.
#
# WHAT THIS DOES NOT COVER: the boot instantiates the project's main scene and whatever
# that pulls in. Pages loaded lazily on first visit (atlas, warp) are NOT touched, so a
# broken page scene can still pass here. i18n_overflow_check walks every page and is the
# probe that catches those.
#
#   powershell -NoProfile -File tools/boot_check.ps1
#   powershell -NoProfile -File tools/boot_check.ps1 -Seconds 30
#   powershell -NoProfile -File tools/boot_check.ps1 -Scene res://scenes/some_probe.tscn

param(
    [int]$Seconds = 18,
    [string]$Scene = "",
    [string]$Godot = ""
)

if ($Godot -eq "") {
    $Godot = Join-Path $env:TEMP "godot_check\Godot_v4.5.1-stable_win64_console.exe"
}
if (-not (Test-Path $Godot)) {
    Write-Host "[BOOT] Godot not found at $Godot"
    Write-Host "[BOOT] extract Godot_v4.5.1-stable_win64.exe.zip to %TEMP%\godot_check\ or pass -Godot"
    exit 2
}

# Anything here means the engine or a script actually failed.
$ERROR_PAT = 'SCRIPT ERROR|^ERROR:|USER ERROR|Failed to load|Failed to instantiate|Failed to open|Parse Error|not declared|Nonexistent function|Cannot infer|Invalid call|Invalid access|Invalid get index|Invalid set index|Attempt to call'
# Anything here means the engine recovered but something is off.
$WARN_PAT = '^WARNING:|USER WARNING|invalid UID'

# NOT $args -- that is a PowerShell automatic variable and assigning it inside a script
# with param() is how the first version of this file failed to parse at all.
$gargs = @("--headless", "--path", ".")
if ($Scene -ne "") { $gargs += $Scene } else { $gargs += @("--quit-after", "$Seconds") }

Write-Host ("[BOOT] " + $Godot + " " + ($gargs -join " "))
$out = & $Godot @gargs 2>&1 | ForEach-Object { $_.ToString() }

# @( ) around Select-String: a SINGLE match returns a scalar MatchInfo in PS 5.1, and
# .Count on a scalar is $null, which silently turns every count below into nothing.
$errs = @($out | Select-String -Pattern $ERROR_PAT)
$warns = @($out | Select-String -Pattern $WARN_PAT)
$ne = $errs.Count
$nw = $warns.Count

if ($nw -gt 0) {
    Write-Host ("[BOOT] " + $nw + " warning line(s) - engine recovered, not failing on these:")
    $warns | Select-Object -First 12 | ForEach-Object { Write-Host ("[BOOT]   " + $_.Line.Trim()) }
    if ($nw -gt 12) { Write-Host ("[BOOT]   ... and " + ($nw - 12) + " more") }
}

if ($ne -gt 0) {
    Write-Host ("[BOOT] " + $ne + " ERROR line(s):")
    $errs | Select-Object -First 20 | ForEach-Object { Write-Host ("[BOOT]   " + $_.Line.Trim()) }
    if ($ne -gt 20) { Write-Host ("[BOOT]   ... and " + ($ne - 20) + " more") }
    Write-Host ("[BOOT] RESULT: FAIL - " + $ne + " error line(s), " + $nw + " warning line(s)")
    exit 1
}

Write-Host ("[BOOT] RESULT: PASS - 0 error line(s), " + $nw + " warning line(s)")
exit 0
