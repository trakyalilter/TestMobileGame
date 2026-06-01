param(
    [int]$IntervalSec = 5
)

# Live monitor for balance-sim runs. Run in its own terminal while a matrix is
# going. Shows, every IntervalSec: each run's line count + done/running status,
# its latest heartbeat snapshot, and the live aggregate (analyze.py over the
# completed runs). Ctrl-C to stop.

$dir = Join-Path $env:APPDATA "Godot\app_userdata\horizonidle\sim_out"
$analyze = Join-Path $PSScriptRoot "analyze.py"

while ($true) {
    Clear-Host
    Write-Host ("=== sim_out monitor @ {0} ===" -f (Get-Date -Format "HH:mm:ss"))
    Write-Host $dir
    Write-Host ""

    if (Test-Path $dir) {
        $files = Get-ChildItem $dir -Filter *.jsonl -ErrorAction SilentlyContinue | Sort-Object Name
        foreach ($f in $files) {
            $lines = (Get-Content $f.FullName -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
            $done  = Select-String -Path $f.FullName -Pattern '"t":"summary"' -Quiet -ErrorAction SilentlyContinue
            $status = if ($done) { "DONE   " } else { "running" }
            # last snapshot for a quick live read of progress
            $lastSnap = Get-Content $f.FullName -ErrorAction SilentlyContinue |
                        Select-String -Pattern '"t":"snap"' | Select-Object -Last 1
            $prog = ""
            if ($lastSnap) {
                $obj = $lastSnap.Line | ConvertFrom-Json
                $prog = ("d{0} g{1} p{2} warps{3} lifeCr{4:N0}" -f `
                    $obj.day, $obj.g_lvl, $obj.p_lvl, $obj.total_warps, $obj.lifetime_credits)
            }
            Write-Host ("  {0,-22} {1,5} ln  [{2}]  {3}" -f $f.Name, $lines, $status, $prog)
        }
    } else {
        Write-Host "  (no sim_out dir yet)"
    }

    Write-Host ""
    Write-Host "--- aggregate (completed runs) ---"
    python $analyze 2>$null

    Start-Sleep -Seconds $IntervalSec
}
