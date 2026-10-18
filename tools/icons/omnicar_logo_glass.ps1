# OmniCar logo, glass version (the approved OmniCar look, see tools/preview/index.html#split): dark HarmonyOS
# glass squircle with a faint top sheen and a hairline rim, the ring + CarPlay play button in bright white with a
# soft white glow. No blue. Same shapes as SCPCLogoImage (the dock button in SCPCarSplit.mm).
# Rendered with .NET System.Drawing so it needs no Python.
#
#   powershell -ExecutionPolicy Bypass -File tools/icons/omnicar_logo_glass.ps1 -Project .
#
# Writes assets/icon-1024.png, Prefs/Resources/icon*.png, logo*.png, PackageIcon.png (squircle, transparent
# corners) and App/Resources/AppIcon60x60@2x/@3x.png (opaque square: iOS masks app icons itself).
# -Out <dir> writes only <dir>/icon-1024.png and <dir>/icon-180.png (preview, nothing in the project changes).
param([string]$Project = ".", [string]$Out = "")

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$UNIT = 1024; $SS = 4; $N = $UNIT * $SS
$BG_TOP = [System.Drawing.Color]::FromArgb(0x33, 0x37, 0x3F)      # kinh toi: sang hon o tren
$BG_BOTTOM = [System.Drawing.Color]::FromArgb(0x0C, 0x0D, 0x10)
$RIM = [System.Drawing.Color]::FromArgb(70, 255, 255, 255)          # vien sang manh (0.5 pt kieu HarmonyOS)

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
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 0), (P 0 1024), $BG_TOP, $BG_BOTTOM)
    if ($opaque) {
        $tile = New-Object System.Drawing.Drawing2D.GraphicsPath
        $tile.AddRectangle((New-Object System.Drawing.RectangleF(0, 0, $N, $N)))
        $g.FillPath($bg, $tile)
    } else {
        $g.FillPath((New-Object System.Drawing.SolidBrush($RIM)), (Squircle 1.0))   # vien sang manh
        $tile = Squircle 0.993
        $g.FillPath($bg, $tile)
    }
    $g.SetClip($tile)
    # Vet sang kinh o nua tren (trang 9% o mep tren -> 0 o giua), trai het chieu cao de khong lap lai khi to path
    $sheen = New-Object System.Drawing.Drawing2D.LinearGradientBrush((P 0 -1), (P 0 1025),
        [System.Drawing.Color]::FromArgb(24, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $blend = New-Object System.Drawing.Drawing2D.ColorBlend(3)
    $blend.Colors = @([System.Drawing.Color]::FromArgb(24, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255), [System.Drawing.Color]::FromArgb(0, 255, 255, 255))
    $blend.Positions = @([single]0, [single]0.5, [single]1)
    $sheen.InterpolationColors = $blend
    $g.FillRectangle($sheen, 0, 0, $N, $N)

    # Quang sang trang toa ra ngoai vong (khong lan vao trong): cac vong mong 3 don vi tu mep ngoai (ban kinh 360)
    # ra 408, sang ~22% sat mep roi nhat dan ve 0
    $tri = PlayTriangle 512 512 610 48
    for ($k = 0; $k -lt 16; $k++) {
        $r = 361.5 + $k * 3
        $a = [int](56 * [Math]::Pow(1 - $k / 16.0, 2))
        $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb($a, 255, 255, 255), (3.2 * $SS))
        $g.DrawEllipse($pen, (512 - $r) * $SS, (512 - $r) * $SS, 2 * $r * $SS, 2 * $r * $SS)
        $pen.Dispose()
    }

    # Vong tron trang (ban kinh ngoai 360, day 120)
    $white = [System.Drawing.Brushes]::White
    $ring = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Alternate)
    $ring.AddEllipse(152 * $SS, 152 * $SS, 720 * $SS, 720 * $SS)
    $ring.AddEllipse(272 * $SS, 272 * $SS, 480 * $SS, 480 * $SS)
    $g.FillPath($white, $ring)
    # Nut play: vien cat bang mau nen (ca 3 goc xuyen qua vong) roi tam giac trang
    $cut = PlayTriangle 512 512 700 60
    $g.FillPath($bg, $cut)
    $g.FillPath($sheen, $cut)
    $g.FillPath($white, $tri)
    $g.ResetClip()
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

# Nen gradient toi chi co ~40 muc xam -> soc ngang; them nhieu +-1.5 muc vao RGB (giu alpha) de xoa soc.
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class OmniDither {
    public static void Apply(Bitmap bmp, int seed) {
        var r = new Random(seed);
        var rect = new Rectangle(0, 0, bmp.Width, bmp.Height);
        var d = bmp.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
        int n = d.Stride * d.Height; var px = new byte[n];
        Marshal.Copy(d.Scan0, px, 0, n);
        for (int i = 0; i < n; i += 4) {
            if (px[i + 3] == 0) continue;
            int e = (int)Math.Round((r.NextDouble() + r.NextDouble() - 1.0) * 1.5);
            for (int c = 0; c < 3; c++) px[i + c] = (byte)Math.Max(0, Math.Min(255, px[i + c] + e));
        }
        Marshal.Copy(px, 0, d.Scan0, n);
        bmp.UnlockBits(d);
    }
}
"@

function Save([System.Drawing.Bitmap]$src, [int]$px, [string]$path) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    $im = Resize $src $px
    [OmniDither]::Apply($im, $px)
    $im.Save((Join-Path (Resolve-Path $dir) (Split-Path -Leaf $path)), [System.Drawing.Imaging.ImageFormat]::Png)
    $im.Dispose()
    Write-Output "wrote $path ($px px)"
}

$root = (Resolve-Path $Project).Path
$tile = Render $false
if ($Out) {
    Save $tile 1024 (Join-Path $Out "icon-1024.png")
    Save $tile 180 (Join-Path $Out "icon-180.png")
    $tile.Dispose()
    return
}
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
