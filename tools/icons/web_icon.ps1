# Icon of the bundled "Web" app (App/Web): white opaque square (iOS masks app icons itself), a browser window drawn
# with the OmniCar blue gradient (#2563EB -> #0B1026): rounded frame, title bar with three dots, a play button in
# the page. Same .NET System.Drawing renderer as omnicar_logo_white.ps1.
#
#   powershell -ExecutionPolicy Bypass -File tools/icons/web_icon.ps1 -Project .
param([string]$Project = ".")

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$UNIT = 1024; $SS = 4; $N = $UNIT * $SS
$BLUE_TOP = [System.Drawing.Color]::FromArgb(0x25, 0x63, 0xEB)
$BLUE_BOTTOM = [System.Drawing.Color]::FromArgb(0x0B, 0x10, 0x26)

function P([double]$x, [double]$y) { New-Object System.Drawing.PointF(($x * $SS), ($y * $SS)) }

function RoundedRectPath([double]$x, [double]$y, [double]$w, [double]$h, [double]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = 2 * $r * $SS
    $p.AddArc($x * $SS, $y * $SS, $d, $d, 180, 90)
    $p.AddArc(($x + $w) * $SS - $d, $y * $SS, $d, $d, 270, 90)
    $p.AddArc(($x + $w) * $SS - $d, ($y + $h) * $SS - $d, $d, $d, 0, 90)
    $p.AddArc($x * $SS, ($y + $h) * $SS - $d, $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}

# Play triangle (rounded corners) centred on (cx, cy), height h
function PlayTriangle([double]$cx, [double]$cy, [double]$h, [double]$r) {
    $w = $h * 0.9
    $pts = @(@(($cx - $w / 2 + $w / 6), ($cy - $h / 2)), @(($cx - $w / 2 + $w / 6), ($cy + $h / 2)), @(($cx + $w / 2 + $w / 6), $cy))
    $out = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    $n = 3
    for ($i = 0; $i -lt $n; $i++) {
        $a = $pts[($i + $n - 1) % $n]; $v = $pts[$i]; $b = $pts[($i + 1) % $n]
        $ux = $a[0] - $v[0]; $uy = $a[1] - $v[1]; $lu = [Math]::Sqrt($ux * $ux + $uy * $uy); $ux /= $lu; $uy /= $lu
        $wx = $b[0] - $v[0]; $wy = $b[1] - $v[1]; $lw = [Math]::Sqrt($wx * $wx + $wy * $wy); $wx /= $lw; $wy /= $lw
        $th = [Math]::Acos([Math]::Max(-1.0, [Math]::Min(1.0, $ux * $wx + $uy * $wy)))
        $t = $r / [Math]::Tan($th / 2)
        $bx = $ux + $wx; $by = $uy + $wy; $lb = [Math]::Sqrt($bx * $bx + $by * $by); $bx /= $lb; $by /= $lb
        $cx2 = $v[0] + $bx * $r / [Math]::Sin($th / 2); $cy2 = $v[1] + $by * $r / [Math]::Sin($th / 2)
        $a0 = [Math]::Atan2($v[1] + $uy * $t - $cy2, $v[0] + $ux * $t - $cx2); $a1 = [Math]::Atan2($v[1] + $wy * $t - $cy2, $v[0] + $wx * $t - $cx2)
        $da = (($a1 - $a0 + [Math]::PI) % (2 * [Math]::PI) + 2 * [Math]::PI) % (2 * [Math]::PI) - [Math]::PI
        for ($k = 0; $k -le 24; $k++) { $ang = $a0 + $da * $k / 24; $out.Add((P ($cx2 + $r * [Math]::Cos($ang)) ($cy2 + $r * [Math]::Sin($ang)))) }
    }
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddPolygon($out.ToArray())
    return $p
}

function Render() {
    $bmp = New-Object System.Drawing.Bitmap($N, $N, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.FillRectangle([System.Drawing.Brushes]::White, 0, 0, $N, $N)
    $blue = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 0), (P 1024 1024), $BLUE_TOP, $BLUE_BOTTOM)
    $white = [System.Drawing.Brushes]::White
    # Browser window: outer frame 760x600, inner cut-out
    $g.FillPath($blue, (RoundedRectPath 132 212 760 600 70))
    $g.FillPath($white, (RoundedRectPath 196 348 632 400 34))      # page area
    # Title bar dots
    foreach ($dx in 0, 76, 152) { $g.FillEllipse($white, (196 + $dx) * $SS, 254 * $SS, 48 * $SS, 48 * $SS) }
    # Play button in the page
    $g.FillPath($blue, (PlayTriangle 512 548 240 26))
    $g.Dispose()
    return $bmp
}

function Resize([System.Drawing.Bitmap]$src, [int]$px) {
    $cur = $src
    while ($cur.Width -ge $px * 4) {
        $half = $cur.Width / 2
        $next = New-Object System.Drawing.Bitmap($half, $half, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($next)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.DrawImage($cur, (New-Object System.Drawing.Rectangle(0, 0, $half, $half)), 0, 0, $cur.Width, $cur.Height, [System.Drawing.GraphicsUnit]::Pixel)
        $g.Dispose()
        if ($cur -ne $src) { $cur.Dispose() }
        $cur = $next
    }
    $dst = New-Object System.Drawing.Bitmap($px, $px, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.DrawImage($cur, (New-Object System.Drawing.Rectangle(0, 0, $px, $px)), 0, 0, $cur.Width, $cur.Height, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    if ($cur -ne $src) { $cur.Dispose() }
    return $dst
}

$root = (Resolve-Path $Project).Path
$dir = Join-Path $root "App\Web\Resources"
if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
$icon = Render
foreach ($pair in @(@("AppIcon60x60@2x.png", 120), @("AppIcon60x60@3x.png", 180))) {
    $im = Resize $icon $pair[1]
    $im.Save((Join-Path $dir $pair[0]), [System.Drawing.Imaging.ImageFormat]::Png)
    $im.Dispose()
    Write-Output ("wrote " + $pair[0] + " (" + $pair[1] + " px)")
}
$icon.Dispose()
