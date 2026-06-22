# Rasterizes the Steam capsule SVGs in this folder to exact-size PNGs via headless Chrome.
# Chrome renders the Orbitron webfont, so PNGs match the in-app previews. Output -> ./png
$chrome = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) { throw "Chrome not found at $chrome" }
$dir = $PSScriptRoot
$out = Join-Path $dir 'png'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$profileDir = Join-Path $env:TEMP 'steam_chrome_profile'

$assets = @(
  @{ f = 'small_capsule';    w = 462;  h = 174 },
  @{ f = 'header_capsule';   w = 920;  h = 430 },
  @{ f = 'main_capsule';     w = 1232; h = 706 },
  @{ f = 'vertical_capsule'; w = 748;  h = 896 },
  @{ f = 'library_capsule';  w = 600;  h = 900 },
  @{ f = 'library_hero';     w = 3840; h = 1240 },
  @{ f = 'page_background';  w = 1438; h = 810 },
  @{ f = 'library_logo';     w = 1280; h = 720 }
)

Add-Type -AssemblyName System.Drawing
foreach ($a in $assets) {
  $svg = Join-Path $dir "$($a.f).svg"
  $png = Join-Path $out "$($a.f).png"
  if (Test-Path $png) { Remove-Item $png -Force }
  $url = 'file:///' + ($svg -replace '\\', '/')
  & $chrome --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check `
    --user-data-dir="$profileDir" --force-device-scale-factor=1 --default-background-color=00000000 `
    --window-size="$($a.w),$($a.h)" --virtual-time-budget=8000 --screenshot="$png" "$url" | Out-Null
  if (Test-Path $png) {
    $img = [System.Drawing.Image]::FromFile($png)
    "{0,-20} {1}x{2}  ({3} KB)" -f "$($a.f).png", $img.Width, $img.Height, [math]::Round((Get-Item $png).Length / 1KB)
    $img.Dispose()
  } else {
    "FAIL  $($a.f)"
  }
}
"Done -> $out"