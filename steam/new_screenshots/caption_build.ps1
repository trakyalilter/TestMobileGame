# Adds branded caption bands to the gameplay screenshots and exports 1920x1080 PNGs via headless Chrome.
# Output -> ./captioned
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) { throw "Chrome not found" }
$dir = $PSScriptRoot
$out = Join-Path $dir 'captioned'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$profileDir = Join-Path $env:TEMP 'shotcap_chrome_profile'

$items = @(
  @{ f='mine';         kicker='Skilling - Core loop';   head='ONE TASK, ALWAYS PROGRESSING'; sub='Commit to a single operation and bank XP and resources - online or offline. Every skill climbs to level 100.' },
  @{ f='engineering';  kicker='Crafting';               head='REFINE RAW ORE INTO AN EMPIRE'; sub='Chain dozens of recipes across refining, alloys, electronics, batteries and munitions.' },
  @{ f='infra';        kicker='Automation';             head='BUILD ONCE. PRODUCE FOREVER.';  sub='Power-gridded extractors and refineries keep producing in the background - even while you are offline.' },
  @{ f='research';     kicker='Tech tree';              head='RESEARCH YOUR OWN PATH';        sub='A seven-branch network unlocks new actions, recipes, ships, sectors and prestige powers.' },
  @{ f='inventory';    kicker='Economy';                head='EVERY SLOT IS A DECISION';      sub='A slot-limited hold and a living market - refine it, sell it, or make room for something better.' },
  @{ f='shipdesigner'; kicker='Ship loadouts';          head='DESIGN THE SHIP, WIN THE FIGHT'; sub='Slot weapons, shields, reactors and armor across hull tiers - save a loadout for every sector.' },
  @{ f='combat';       kicker='Auto-battler combat';    head='WIN BEFORE THE FIGHT BEGINS';   sub='Your loadout does the fighting - engage sectors, loot rare modules and alloys, and push deeper.' }
)

$css = @'
<style>
@import url('https://fonts.googleapis.com/css2?family=Orbitron:wght@500;700;900&display=swap');
*{margin:0;padding:0;box-sizing:border-box;}
html,body{background:#000;}
.stage{position:relative;width:1920px;height:1080px;overflow:hidden;font-family:'Orbitron',Arial,sans-serif;}
.shot{position:absolute;inset:0;width:1920px;height:1080px;object-fit:cover;}
.band{position:absolute;left:0;right:0;bottom:0;height:42%;
  background:linear-gradient(to bottom, rgba(4,6,14,0) 0%, rgba(4,6,14,0.55) 42%, rgba(4,6,14,0.9) 100%);}
.cap{position:absolute;left:78px;bottom:70px;right:78px;border-left:5px solid #ffd14c;padding-left:32px;}
.kicker{color:#ffd14c;font-weight:700;font-size:23px;letter-spacing:7px;text-transform:uppercase;}
.head{color:#f5f9ff;font-weight:900;font-size:58px;line-height:1.04;margin-top:14px;text-shadow:0 3px 22px rgba(0,0,0,0.75);}
.sub{color:#bfe0ff;font-weight:500;font-size:27px;line-height:1.45;margin-top:18px;max-width:1480px;text-shadow:0 2px 14px rgba(0,0,0,0.85);}
</style>
'@

foreach ($it in $items) {
  $src = Join-Path $dir "$($it.f).png"
  if (-not (Test-Path $src)) { "MISSING $($it.f).png"; continue }
  $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($src))
  $html = @"
<!doctype html><html><head><meta charset="utf-8">$css</head><body>
<div class="stage">
<img class="shot" src="data:image/png;base64,$b64"/>
<div class="band"></div>
<div class="cap">
<div class="kicker">$($it.kicker)</div>
<div class="head">$($it.head)</div>
<div class="sub">$($it.sub)</div>
</div>
</div></body></html>
"@
  $htmlPath = Join-Path $env:TEMP "cap_$($it.f).html"
  Set-Content -Path $htmlPath -Value $html -Encoding utf8
  $png = Join-Path $out "$($it.f).png"
  if (Test-Path $png) { Remove-Item $png -Force }
  $url = 'file:///' + ($htmlPath -replace '\\','/')
  & $chrome --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check `
    --user-data-dir="$profileDir" --force-device-scale-factor=1 --window-size="1920,1080" `
    --virtual-time-budget=6000 --screenshot="$png" "$url" | Out-Null
  if (Test-Path $png) { "OK   $($it.f).png  ($([math]::Round((Get-Item $png).Length/1KB)) KB)" } else { "FAIL $($it.f)" }
}
"Done -> $out"