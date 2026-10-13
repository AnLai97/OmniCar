# OmniCar logo, liquid glass version (phuong an D trong tools/preview/logo.html, giao dien chot 13/10/2026):
# nen chat long pastel (oai huong, xanh troi, bac ha, dao) trong o squircle, vong tron + nut play CarPlay bang
# kinh trang mo noi 3D (bong do mem, vet bong phia tren, toi dan o mep, vien sang). Cung hinh nhu logo cu
# (vong ban kinh ngoai 360 day 120, nut play cao 610 bo 48, vien cat 700 / 60, khung 1024).
# GDI+ khong lam mo duoc nen phan tron mau tinh tung diem anh bang C# (LiquidLogo) theo dung cong thuc cua SVG.
#
#   powershell -ExecutionPolicy Bypass -File tools/icons/omnicar_logo_liquid.ps1 -Project .
#
# Ghi assets/icon-1024.png, Prefs/Resources/icon*.png, logo*.png, PackageIcon.png (squircle, goc trong suot) va
# App/Resources/AppIcon60x60@2x/@3x.png (vuong kin: iOS tu cat goc icon app).
# -Out <dir> chi ghi <dir>/icon-1024.png va <dir>/icon-180.png (xem truoc, khong doi gi trong project).
param([string]$Project = ".", [string]$Out = "")

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = "Stop"

$S = 2048; $K = $S / 1024.0   # ve o 2048 roi thu nho

function P([double]$x, [double]$y) { New-Object System.Drawing.PointF(($x * $K), ($y * $K)) }

function Squircle([double]$scale = 1.0) {
    $h = $S / 2.0
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

# Tam giac bo goc bang cung tron ban kinh r (giong SCPCRoundedTriangle / omnicar_logo_glass.ps1)
function PlayTriangle([double]$cx, [double]$cy, [double]$h, [double]$r) {
    $w = $h * 0.9
    $pts = @(@(($cx - $w / 2 + $w / 6), ($cy - $h / 2)), @(($cx - $w / 2 + $w / 6), ($cy + $h / 2)), @(($cx + $w / 2 + $w / 6), $cy))
    $out = New-Object 'System.Collections.Generic.List[System.Drawing.PointF]'
    for ($i = 0; $i -lt 3; $i++) {
        $a = $pts[($i + 2) % 3]; $v = $pts[$i]; $b = $pts[($i + 1) % 3]
        $ux = $a[0] - $v[0]; $uy = $a[1] - $v[1]; $lu = [Math]::Sqrt($ux * $ux + $uy * $uy); $ux /= $lu; $uy /= $lu
        $wx = $b[0] - $v[0]; $wy = $b[1] - $v[1]; $lw = [Math]::Sqrt($wx * $wx + $wy * $wy); $wx /= $lw; $wy /= $lw
        $th = [Math]::Acos([Math]::Max(-1.0, [Math]::Min(1.0, $ux * $wx + $uy * $wy)))
        $t = $r / [Math]::Tan($th / 2)
        $bx = $ux + $wx; $by = $uy + $wy; $lb = [Math]::Sqrt($bx * $bx + $by * $by); $bx /= $lb; $by /= $lb
        $cx2 = $v[0] + $bx * $r / [Math]::Sin($th / 2); $cy2 = $v[1] + $by * $r / [Math]::Sin($th / 2)
        $a0 = [Math]::Atan2($v[1] + $uy * $t - $cy2, $v[0] + $ux * $t - $cx2); $a1 = [Math]::Atan2($v[1] + $wy * $t - $cy2, $v[0] + $wx * $t - $cx2)
        $da = (($a1 - $a0 + [Math]::PI) % (2 * [Math]::PI) + 2 * [Math]::PI) % (2 * [Math]::PI) - [Math]::PI
        for ($j = 0; $j -le 24; $j++) { $ang = $a0 + $da * $j / 24; $out.Add((P ($cx2 + $r * [Math]::Cos($ang)) ($cy2 + $r * [Math]::Sin($ang)))) }
    }
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddPolygon($out.ToArray())
    return $path
}

function Ring {
    $ring = New-Object System.Drawing.Drawing2D.GraphicsPath([System.Drawing.Drawing2D.FillMode]::Alternate)
    $ring.AddEllipse(152 * $K, 152 * $K, 720 * $K, 720 * $K)
    $ring.AddEllipse(272 * $K, 272 * $K, 480 * $K, 480 * $K)
    return $ring
}

# Mat na (0..255) ve bang GDI+: action nhan Graphics, ve trang len nen den
function Mask([scriptblock]$draw) {
    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::Black)
    & $draw $g
    $g.Dispose()
    $m = [LiquidLogo]::ToMask($bmp)
    $bmp.Dispose()
    return , $m
}

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices;
public static class LiquidLogo {
    public static float[] ToMask(Bitmap b) {
        var d = b.LockBits(new Rectangle(0, 0, b.Width, b.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int n = d.Stride * d.Height; var px = new byte[n]; Marshal.Copy(d.Scan0, px, 0, n); b.UnlockBits(d);
        var m = new float[b.Width * b.Height];
        for (int i = 0; i < m.Length; i++) m[i] = px[i * 4 + 1] / 255f;
        return m;
    }
    // Lam mo hop 3 lan (gan Gauss), ban kinh r diem anh
    public static float[] Blur(float[] src, int s, int r) {
        var a = (float[])src.Clone(); var t = new float[a.Length];
        for (int pass = 0; pass < 3; pass++) {
            for (int y = 0; y < s; y++) { float acc = 0; int row = y * s;
                for (int x = -r; x <= r; x++) acc += a[row + Math.Max(0, Math.Min(s - 1, x))];
                for (int x = 0; x < s; x++) { t[row + x] = acc / (2 * r + 1);
                    acc += a[row + Math.Min(s - 1, x + r + 1)] - a[row + Math.Max(0, x - r)]; } }
            for (int x = 0; x < s; x++) { float acc = 0;
                for (int y = -r; y <= r; y++) acc += t[Math.Max(0, Math.Min(s - 1, y)) * s + x];
                for (int y = 0; y < s; y++) { a[y * s + x] = acc / (2 * r + 1);
                    acc += t[Math.Min(s - 1, y + r + 1) * s + x] - t[Math.Max(0, y - r) * s + x]; } }
        }
        return a;
    }
    static readonly float[][] Blobs = {   // mau, tam (khung 1024), ban kinh
        new float[] { 0xB7, 0xA6, 0xFF, 260, 240, 420 }, new float[] { 0x8F, 0xD3, 0xFF, 800, 320, 380 },
        new float[] { 0x9D, 0xF2, 0xD8, 760, 850, 360 }, new float[] { 0xFF, 0xC2, 0xD6, 220, 830, 340 } };
    // Nen chat long: hinh tron mau lam mo (stdDeviation sd) chong len nen #EEF0FB theo thu tu nhu SVG
    static void Liquid(float u, float v, float sd, out float r, out float g, out float b) {
        r = 0xEE; g = 0xF0; b = 0xFB;
        foreach (var bl in Blobs) {
            float dx = u - bl[3], dy = v - bl[4], d = (float)Math.Sqrt(dx * dx + dy * dy);
            float w = 1f / (1f + (float)Math.Exp((d - bl[5]) / (sd * 0.62f)));
            r += (bl[0] - r) * w; g += (bl[1] - g) * w; b += (bl[2] - b) * w;
        }
    }
    static float Clamp(float x) { return x < 0 ? 0 : x > 1 ? 1 : x; }
    public static Bitmap Render(int s, float[] tile, float[] mark, float[] shadow, float[] rim, float[] edge, bool opaque) {
        var bmp = new Bitmap(s, s, PixelFormat.Format32bppArgb);
        var d = bmp.LockBits(new Rectangle(0, 0, s, s), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        var px = new byte[d.Stride * s]; float k = 1024f / s;
        for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
            int i = y * s + x; float u = (x + .5f) * k, v = (y + .5f) * k;
            float r, g, b; Liquid(u, v, 110, out r, out g, out b);
            float sh = Clamp(0.5f - v / 1024f) * 2f * 0.5f;                    // vet sang tren o: trang 50% -> 0 o giua
            r += (255 - r) * sh; g += (255 - g) * sh; b += (255 - b) * sh;
            int si = Math.Max(0, y - (int)(30 / k)) * s + x;                    // bong do cua logo lech xuong 30
            float so = shadow[si] * 0.30f; r *= 1 - so; g *= 1 - so; b *= 1 - so;
            float m = mark[i];
            if (m > 0) {   // kinh trang mo: nen mo hon + phu trang 55% + vet bong + toi dan ra mep
                float gr, gg, gb; Liquid(u, v, 180, out gr, out gg, out gb);
                gr += (255 - gr) * .55f; gg += (255 - gg) * .55f; gb += (255 - gb) * .55f;
                float ex = (u - 420) / 430f, ey = (v - 230) / 220f;
                if (ex * ex + ey * ey < 1) { float sp = .75f * (1 - Clamp((v - 10) / 440f)) * .55f;
                    gr += (255 - gr) * sp; gg += (255 - gg) * sp; gb += (255 - gb) * sp; }
                float rx = (u - 358) / 819f, ry = (v - 307) / 819f, rr = (float)Math.Sqrt(rx * rx + ry * ry);
                float dk = Clamp((rr - .75f) / .25f) * .35f; gr *= 1 - dk; gg *= 1 - dk; gb *= 1 - dk;
                float ra = rim[i] * m;                                          // vien sang: 95% tren trai -> 25% -> 55% duoi
                if (ra > 0) { float t = Clamp((u * .4f + v) / (1024f * 1.4f));
                    float al = t < .5f ? .95f + (.25f - .95f) * t * 2 : .25f + (.55f - .25f) * (t - .5f) * 2;
                    gr += (255 - gr) * ra * al; gg += (255 - gg) * ra * al; gb += (255 - gb) * ra * al; }
                r += (gr - r) * m; g += (gg - g) * m; b += (gb - b) * m;
            }
            float e = edge[i] * .7f; r += (255 - r) * e; g += (255 - g) * e; b += (255 - b) * e;   // vien squircle
            float a = opaque ? 1 : tile[i];
            int o = y * d.Stride + x * 4;
            px[o] = (byte)Math.Round(Math.Min(255, b)); px[o + 1] = (byte)Math.Round(Math.Min(255, g));
            px[o + 2] = (byte)Math.Round(Math.Min(255, r)); px[o + 3] = (byte)Math.Round(a * 255);
        }
        Marshal.Copy(px, 0, d.Scan0, px.Length); bmp.UnlockBits(d);
        return bmp;
    }
}
"@

$white = [System.Drawing.Brushes]::White
$black = [System.Drawing.Brushes]::Black
$tileM = Mask { param($g) $g.FillPath($white, (Squircle 1.0)) }
$markM = Mask { param($g) $g.FillPath($white, (Ring)); $g.FillPath($black, (PlayTriangle 512 512 700 60)); $g.FillPath($white, (PlayTriangle 512 512 610 48)) }
$rimM = Mask { param($g)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, (10 * $K))
    $g.DrawEllipse($pen, 152 * $K, 152 * $K, 720 * $K, 720 * $K); $g.DrawEllipse($pen, 272 * $K, 272 * $K, 480 * $K, 480 * $K)
    $g.FillPath($black, (PlayTriangle 512 512 700 60))   # vien vong khong lo qua nut play
    $g.DrawPath($pen, (PlayTriangle 512 512 610 48)); $pen.Dispose() }
$edgeM = Mask { param($g) $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, (6 * $K)); $g.DrawPath($pen, (Squircle 0.992)); $pen.Dispose() }
$shadowM = [LiquidLogo]::Blur($markM, $S, [int](22 * $K * 1.7))

# Thu nho tung nua cho cac co nho van net
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
$tile = [LiquidLogo]::Render($S, $tileM, $markM, $shadowM, $rimM, $edgeM, $false)
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

$square = [LiquidLogo]::Render($S, $tileM, $markM, $shadowM, $rimM, $edgeM, $true)
Save $square 120 (Join-Path $root "App\Resources\AppIcon60x60@2x.png")
Save $square 180 (Join-Path $root "App\Resources\AppIcon60x60@3x.png")
$square.Dispose()
