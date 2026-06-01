param(
    [string]$Scene      = "res://scenes/sim_runner.tscn",
    [string]$SimArgs    = "",
    [int]   $TimeoutSec  = 300
)

# Run the headless balance-sim harness by temporarily swapping run/main_scene.
# project.godot is backed up and ALWAYS restored (finally), even on crash.

$ErrorActionPreference = "Stop"

$proj     = "C:\Users\ilter-cnc\Documents\horizon-idle\horizonidle-godot"
$godot    = Join-Path $env:TEMP "godot_check\Godot_v4.5.1-stable_win64_console.exe"
$projFile = Join-Path $proj "project.godot"
$backup   = Join-Path $proj "project.godot.simbak"

if (-not (Test-Path $godot))    { throw "Godot binary not found: $godot" }
if (-not (Test-Path $projFile)) { throw "project.godot not found" }

Copy-Item $projFile $backup -Force
try {
    $content   = Get-Content $projFile -Raw
    $pattern   = 'run/main_scene="[^"]*"'
    $replace   = 'run/main_scene="' + $Scene + '"'
    $swapped   = $content -replace $pattern, $replace
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($projFile, $swapped, $utf8NoBom)

    $argList = @("--headless", "--path", $proj)
    if ($SimArgs -ne "") {
        $argList += "--"
        foreach ($a in ($SimArgs -split " ")) {
            if ($a -ne "") { $argList += $a }
        }
    }

    Write-Host "[run_sim] launching headless..."
    $p = Start-Process -FilePath $godot -ArgumentList $argList -NoNewWindow -PassThru
    $done = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $done) {
        Write-Warning "[run_sim] timeout - killing"
        $p.Kill()
    } else {
        Write-Host ("[run_sim] exit code: " + $p.ExitCode)
    }
}
finally {
    Copy-Item $backup $projFile -Force
    Remove-Item $backup -Force
    Write-Host "[run_sim] project.godot restored"
}
