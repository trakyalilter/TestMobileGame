param(
    [string[]]$Archetypes = @("optimizer", "casual", "combat"),
    [int[]]   $Seeds       = @(1, 2, 3),
    [int]     $Days        = 5,
    [int]     $TimeoutSec  = 1800,
    [string]  $OutDir      = ""    # optional sub-folder under sim_out for this batch
)

# Run the archetype x seed matrix. Each run is independent; run_sim.ps1
# swaps/restores project.godot per invocation. Runs ACCUMULATE (nothing is
# wiped). With -OutDir, this batch lands in sim_out/<OutDir>/ so batches stay
# separated; analyze.py scans recursively, so one report still covers them all.

$tool = Join-Path $PSScriptRoot "run_sim.ps1"
$total = $Archetypes.Count * $Seeds.Count
$i = 0
foreach ($a in $Archetypes) {
    foreach ($s in $Seeds) {
        $i++
        Write-Host ""
        Write-Host ("=== [{0}/{1}] {2} seed={3} days={4} ===" -f $i, $total, $a, $s, $Days)
        $simArgs = "--archetype=$a --seed=$s --days=$Days"
        if ($OutDir -ne "") {
            $simArgs += " --out=user://sim_out/$OutDir/${a}_${s}.jsonl"
        }
        & $tool -TimeoutSec $TimeoutSec -SimArgs $simArgs
    }
}

$reportDir = Join-Path $env:APPDATA "Godot\app_userdata\horizonidle\sim_out"
if ($OutDir -ne "") { $reportDir = Join-Path $reportDir $OutDir }
Write-Host ""
Write-Host ("Matrix complete ({0} runs). Aggregate with:" -f $total)
Write-Host ("  python tools/analyze.py `"{0}`"" -f $reportDir)
