# ============================================================================
# Player-like bot matrix launcher (v135).
#
#   powershell -File tools\run_players.ps1 -Smoke        # gate+drywalk+3 quick runs (~5-10 min)
#   powershell -File tools\run_players.ps1               # full 4 archetypes x 5 seeds matrix
#   powershell -File tools\run_players.ps1 -Determinism  # same-seed double run + byte diff
#
# Output: sim_out\players\<stamp>\player_<arch>_<seed>.jsonl (+ digest via
#   python tools\funnel_report.py <dir>)
# ============================================================================
param(
    [switch]$Smoke,
    [switch]$Determinism,
    [int]$Days = 14,
    [string]$Until = "funnel_end",
    [string]$Godot = "$env:TEMP\godot_check\Godot_v4.5.1-stable_win64_console.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outDir = Join-Path $root "sim_out\players\$stamp"
New-Item -ItemType Directory -Force $outDir | Out-Null

# 1) Zero-grants gate -- never run a matrix on a policy that cheats.
& powershell -NoProfile -File (Join-Path $root "tools\check_player_policy.ps1")
if ($LASTEXITCODE -ne 0) { Write-Host "[matrix] gate failed - aborting"; exit 1 }

function Run-Bot([string]$arch, [int]$seedv, [string]$untilv, [int]$daysv, [string]$suffix = "") {
    $out = Join-Path $outDir "player_${arch}_${seedv}${suffix}.jsonl"
    Write-Host "[matrix] $arch seed=$seedv until=$untilv days=$daysv"
    & $Godot --headless --path $root res://scenes/player_bot.tscn -- `
        "--archetype=$arch" "--seed=$seedv" "--days=$daysv" "--until=$untilv" "--out=$out" 2>$null |
        Select-String -Pattern "\[PBOT\]\[(SUMMARY|WALL|WARN)\]|\[FUN\]\[" | ForEach-Object { Write-Host $_.Line }
}

# 2) Dry-walk -- chain must be fully mappable before any timed run.
Write-Host "[matrix] dry-walk..."
$dw = & $Godot --headless --path $root res://scenes/player_bot.tscn -- --drywalk 2>$null | Out-String
Write-Host $dw
if ($dw -match "DRYWALK\] FAILED") { Write-Host "[matrix] dry-walk failed - aborting"; exit 1 }

if ($Determinism) {
    Run-Bot "follower" 11 "first_boss" 7 "_a"
    Run-Bot "follower" 11 "first_boss" 7 "_b"
    $a = Get-Content (Join-Path $outDir "player_follower_11_a.jsonl")
    $b = Get-Content (Join-Path $outDir "player_follower_11_b.jsonl")
    $diff = Compare-Object $a $b
    if ($diff) {
        Write-Host "[matrix] DETERMINISM FAIL: $($diff.Count) differing lines" -ForegroundColor Red
        $diff | Select-Object -First 6 | Format-Table | Out-String | Write-Host
        exit 1
    }
    Write-Host "[matrix] determinism OK (byte-identical runs)" -ForegroundColor Green
    exit 0
}

if ($Smoke) {
    foreach ($s in 11, 22, 33) { Run-Bot "follower" $s "first_boss" 7 }
} else {
    foreach ($arch in "follower", "efficient", "drifter", "overnighter") {
        foreach ($s in 11, 22, 33, 44, 55) { Run-Bot $arch $s $Until $Days }
    }
}
Write-Host "[matrix] done -> $outDir"
Write-Host "[matrix] digest: python tools\funnel_report.py `"$outDir`""
