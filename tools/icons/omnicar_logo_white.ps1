# OmniCar logo, white version: white squircle tile, ring + CarPlay play button filled with the cosmic-blue
# gradient (#2563EB -> #0B1026), the same drawing as SCPCLogoImage (the dock button in SCPCarSplit.mm) and
# the glyph of omnicar_logo.py. Rendered with .NET System.Drawing so it needs no Python.
#
#   powershell -ExecutionPolicy Bypass -File tools/icons/omnicar_logo_white.ps1 -Project .
#
# Writes assets/icon-1024.png, Prefs/Resources/icon*.png, logo*.png, PackageIcon.png (squircle, transparent
# corners) and App/Resources/AppIcon60x60@2x/@3x.png (opaque square: iOS masks app icons itself).
param([string]$Project = ".")

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$UNIT = 1024; $SS = 4; $N = $UNIT * $SS
$BLUE_TOP = [System.Drawing.Color]::FromArgb(0x25, 0x63, 0xEB)
$BLUE_BOTTOM = [System.Drawing.Color]::FromArgb(0x0B, 0x10, 0x26)
$EDGE = [System.Drawing.Color]::FromArgb(0xE3, 0xE6, 0xEA)   # faint rim so the white tile reads on white pages

function P([double]$x, [double]$y) { New-Object System.Drawing.PointF(($x * $SS), ($y * $SS)) }

# Superellipse (n = 5) outline as a polygon, like harmony_icon.py; $scale < 1 insets it around the center.
function Squircle([double]$scale = 1.0) {
    $h = $N / 2.0
    $pts = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt 1440; $i++) {
        $t = 2 * [Math]::PI * $i / 1440
        $c = [Math]::Cos($t); $s = [Math]::Sin($t)
        $x = $h + $h * $scale * [Math]::Sign($c) * [Math]::Pow([Math]::Abs($c), 2 / 5.0)
        $y = $h + $h * $scale * [Math]::Sign($s) * [Math]::Pow([Math]::Abs($s), 2 / 5.0)
        $pts.Add((New-Object System.Drawing.PointF($x, $y)))
    }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddPolygon($pts.ToArray())
    return $path
}

# Polygon with corners rounded by true arcs of radius $r (same construction as harmony_icon.py / SCPCRoundedTriangle).
function RoundedPolygon([double[][]]$pts, [double]$r) {
    $out = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $n = $pts.Count
    for ($i = 0; $i -lt $n; $i++) {
        $a = $pts[($i + $n - 1) % $n]; $v = $pts[$i]; $b = $pts[($i + 1) % $n]
        $ux = $a[0] - $v[0]; $uy = $a[1] - $v[1]; $lu = [Math]::Sqrt($ux * $ux + $uy * $uy); $ux /= $lu; $uy /= $lu
        $wx = $b[0] - $v[0]; $wy = $b[1] - $v[1]; $lw = [Math]::Sqrt($wx * $wx + $wy * $wy); $wx /= $lw; $wy /= $lw
        $th = [Math]::Acos([Math]::Max(-1.0, [Math]::Min(1.0, $ux * $wx + $uy * $wy)))
        $t = $r / [Math]::Tan($th / 2)
        $bx = $ux + $wx; $by = $uy + $wy; $lb = [Math]::Sqrt($bx * $bx + $by * $by); $bx /= $lb; $by /= $lb
        $cx = $v[0] + $bx * $r / [Math]::Sin($th / 2); $cy = $v[1] + $by * $r / [Math]::Sin($th / 2)
        $p0x = $v[0] + $ux * $t; $p0y = $v[1] + $uy * $t
        $p1x = $v[0] + $wx * $t; $p1y = $v[1] + $wy * $t
        $a0 = [Math]::Atan2($p0y - $cy, $p0x - $cx); $a1 = [Math]::Atan2($p1y - $cy, $p1x - $cx)
        $da = (($a1 - $a0 + [Math]::PI) % (2 * [Math]::PI) + 2 * [Math]::PI) % (2 * [Math]::PI) - [Math]::PI
        for ($k = 0; $k -le 24; $k++) {
            $ang = $a0 + $da * $k / 24
            $out.Add((P ($cx + $r * [Math]::Cos($ang)) ($cy + $r * [Math]::Sin($ang))))
        }
    }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddPolygon($out.ToArray())
    return $path
}

# CarPlay play triangle centred on (cx, cy), height h, corners rounded by r (omnicar_logo.py tri_c).
function PlayTriangle([double]$cx, [double]$cy, [double]$h, [double]$r) {
    $w = $h * 0.9
    $pts = @(
        @(($cx - $w / 2 + $w / 6), ($cy - $h / 2)),
        @(($cx - $w / 2 + $w / 6), ($cy + $h / 2)),
        @(($cx + $w / 2 + $w / 6), $cy)
    )
    return RoundedPolygon $pts $r
}

function Render([bool]$opaque) {
    $bmp = New-Object System.Drawing.Bitmap($N, $N, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $white = [System.Drawing.Brushes]::White
    if ($opaque) {
        $g.FillRectangle($white, 0, 0, $N, $N)
    } else {
        $g.FillPath((New-Object System.Drawing.SolidBrush($EDGE)), (Squircle 1.0))
        $g.FillPath($white, (Squircle 0.992))
    }
    $blue = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 0), (P 1024 1024), $BLUE_TOP, $BLUE_BOTTOM)
    # Ring: outer radius 360, width 120
    $ring = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Alternate)
    $ring.AddEllipse(152 * $SS, 152 * $SS, 720 * $SS, 720 * $SS)
    $ring.AddEllipse(272 * $SS, 272 * $SS, 480 * $SS, 480 * $SS)
    $g.FillPath($blue, $ring)
    # Play: white cut, then the blue triangle (all three corners break through the ring)
    $g.FillPath($white, (PlayTriangle 512 512 700 60))
    $g.FillPath($blue, (PlayTriangle 512 512 610 48))
    $g.Dispose()
    return $bmp
}

# Stepwise halving before the final resize keeps small sizes crisp.
function Resize([System.Drawing.Bitmap]$src, [int]$px) {
    $cur = $src
    while ($cur.Width -ge $px * 4) {
        $half = $cur.Width / 2
        $next = New-Object System.Drawing.Bitmap($half, $half, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($next)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.DrawImage($cur, (New-Object System.Drawing.Rectangle(0, 0, $half, $half)), 0, 0, $cur.Width, $cur.Height, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        if ($cur -ne $src) { $cur.Dispose() }
        $cur = $next
    }
    $dst = New-Object System.Drawing.Bitmap($px, $px, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.DrawImage($cur, (New-Object System.Drawing.Rectangle(0, 0, $px, $px)), 0, 0, $cur.Width, $cur.Height, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    if ($cur -ne $src) { $cur.Dispose() }
    return $dst
}

function Save([System.Drawing.Bitmap]$src, [int]$px, [string]$path) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $im = Resize $src $px
    $im.Save((Join-Path (Resolve-Path $dir) (Split-Path -Leaf $path)), [System.Drawing.Imaging.ImageFormat]::Png)
    $im.Dispose()
    Write-Output "wrote $path ($px px)"
}

$root = (Resolve-Path $Project).Path
$tile = Render $false
$res = Join-Path $root "Prefs\Resources"
Save $tile 1024 (Join-Path $root "assets\icon-1024.png")
Save $tile 29  (Join-Path $res "icon.png")
Save $tile 58  (Join-Path $res "icon@2x.png")
Save $tile 87  (Join-Path $res "icon@3x.png")
Save $tile 64  (Join-Path $res "logo.png")
Save $tile 128 (Join-Path $res "logo@2x.png")
Save $tile 192 (Join-Path $res "logo@3x.png")
Save $tile 256 (Join-Path $res "PackageIcon.png")
$tile.Dispose()

$square = Render $true
Save $square 120 (Join-Path $root "App\Resources\AppIcon60x60@2x.png")
Save $square 180 (Join-Path $root "App\Resources\AppIcon60x60@3x.png")
$square.Dispose()
