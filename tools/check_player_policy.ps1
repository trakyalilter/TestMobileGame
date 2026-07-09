# ============================================================================
# Zero-grants static gate for the player-like bot (v135).
#
# The player-like sim's entire value is that it EARNS everything -- the moment a
# grant sneaks in, its funnel numbers become progression_bot-style floors and
# every wall report is untrustworthy. This gate greps the three player-bot
# files for the tokens that implement grants/cheats anywhere in the sim layer
# and fails loudly. Run before every matrix (run_players.ps1 calls it first).
#
#   powershell -File tools\check_player_policy.ps1
#
# Exit 0 = clean, 1 = violation(s) printed.
# ============================================================================

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

$files = @(
    "scripts\sim\policies\player_like.gd",
    "scripts\sim\mission_actions.gd",
    "scripts\sim\player_bot.gd"
)

# Token -> why it is banned in a zero-grants sim.
$banned = [ordered]@{
    "add_element("          = "grants materials the player never earned"
    "add_currency("         = "grants credits (selling is done via policy_base.sell_surplus, which lives OUTSIDE the scanned files)"
    "generate_module_drop(" = "fabricates module drops instead of earning them from real combat loot"
    "unlocked_techs.append" = "force-unlocks research without paying (progression.gd's representative-drops shortcut)"
    "total_warps ="         = "direct warp-state write"
    "total_warps +="        = "direct warp-state write"
    "warp_shards ="         = "direct warp-state write"
    "warp_shards +="        = "direct warp-state write"
    "boss_kills["           = "direct kill-ledger write (wins must come from real combat; runner-side hygiene CLEAR uses .clear())"
    "lifetime_credits ="    = "direct prestige-score write"
}

$violations = 0
foreach ($rel in $files) {
    $path = Join-Path $root $rel
    if (-not (Test-Path $path)) {
        Write-Host "[gate] MISSING FILE: $rel" -ForegroundColor Yellow
        continue
    }
    $lineNo = 0
    foreach ($line in Get-Content $path) {
        $lineNo++
        foreach ($tok in $banned.Keys) {
            if ($line.Contains($tok)) {
                # Comments explaining the ban are fine; code is not.
                $trim = $line.TrimStart()
                if ($trim.StartsWith("#")) { continue }
                Write-Host ("[gate] VIOLATION {0}:{1}  token '{2}' -- {3}" -f $rel, $lineNo, $tok, $banned[$tok]) -ForegroundColor Red
                Write-Host ("        {0}" -f $line.Trim())
                $violations++
            }
        }
    }
}

if ($violations -gt 0) {
    Write-Host "[gate] FAILED: $violations grant-token violation(s). The player-like sim must EARN everything." -ForegroundColor Red
    exit 1
}
Write-Host "[gate] clean -- zero grant tokens in player-bot files." -ForegroundColor Green
exit 0
