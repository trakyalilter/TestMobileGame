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

# ---- App / shortcut icon (Sunrise Sigil) -------------------------------------
# Renders app_icon.svg (full, used >=64px) and app_icon_small.svg (comet/moon &
# ring hairlines stripped + brighter sun core, used <=48px) at 512 via Chrome,
# high-quality-downscales each, and packs png/icon_*.png plus a multi-resolution
# icon.ico (the Windows shortcut / Steam client icon). No ImageMagick needed.
function Render-IconSvg([string]$name) {
  $svg = Join-Path $dir "$name.svg"
  $png = Join-Path $out ($name + '_512.png')
  $url = 'file:///' + ($svg.Replace('\', '/'))
  & $chrome --headless=new --disable-gpu --hide-scrollbars --no-first-run --no-default-browser-check `
    --user-data-dir="$profileDir" --force-device-scale-factor=1 --default-background-color=00000000 `
    --window-size=512,512 --virtual-time-budget=8000 --screenshot="$png" "$url" | Out-Null
  return $png
}
function Resize-Icon([string]$src, [int]$size, [string]$dest) {
  $s = [System.Drawing.Image]::FromFile($src)
  $b = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($b)
  $g.InterpolationMode  = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode    = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.SmoothingMode      = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.DrawImage($s, (New-Object System.Drawing.Rectangle 0, 0, $size, $size))
  $g.Dispose()
  $b.Save($dest, [System.Drawing.Imaging.ImageFormat]::Png); $b.Dispose(); $s.Dispose()
}
function Write-Ico([string[]]$pngs, [string]$ico) {
  $fr = foreach ($p in $pngs) {
    $by = [System.IO.File]::ReadAllBytes($p)
    $im = [System.Drawing.Image]::FromFile($p); $w = $im.Width; $h = $im.Height; $im.Dispose()
    [pscustomobject]@{ w = $w; h = $h; by = $by }
  }
  $ms = New-Object System.IO.MemoryStream; $bw = New-Object System.IO.BinaryWriter($ms)
  $bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$fr.Count)   # ICONDIR header
  $off = 6 + ($fr.Count * 16)
  foreach ($f in $fr) {
    $wb = if ($f.w -ge 256) { 0 } else { $f.w }; $hb = if ($f.h -ge 256) { 0 } else { $f.h }
    $bw.Write([byte]$wb); $bw.Write([byte]$hb); $bw.Write([byte]0); $bw.Write([byte]0)
    $bw.Write([uint16]1); $bw.Write([uint16]32); $bw.Write([uint32]$f.by.Length); $bw.Write([uint32]$off); $off += $f.by.Length
  }
  foreach ($f in $fr) { $bw.Write($f.by) }                                   # PNG-encoded frames (Vista+)
  $bw.Flush(); [System.IO.File]::WriteAllBytes($ico, $ms.ToArray()); $ms.Dispose()
}
$full  = Render-IconSvg 'app_icon'
$small = Render-IconSvg 'app_icon_small'
Resize-Icon $full  256 (Join-Path $out 'icon_256.png')
Resize-Icon $full  128 (Join-Path $out 'icon_128.png')
Resize-Icon $full  64  (Join-Path $out 'icon_64.png')
Resize-Icon $small 48  (Join-Path $out 'icon_48.png')
Resize-Icon $small 32  (Join-Path $out 'icon_32.png')
Resize-Icon $small 16  (Join-Path $out 'icon_16.png')
$icoFrames = @('icon_256', 'icon_128', 'icon_64', 'icon_48', 'icon_32', 'icon_16') | ForEach-Object { Join-Path $out ($_ + '.png') }
$icoPath = Join-Path $dir 'icon.ico'
Write-Ico $icoFrames $icoPath
"icon.ico  -> {0}  ({1} KB, {2} frames)" -f $icoPath, [math]::Round((Get-Item $icoPath).Length / 1KB), $icoFrames.Count
"app icon  -> {0}" -f (Join-Path $out 'icon_256.png')

"Done -> $out"