Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Set-Location "$PSScriptRoot\..\out\build\release"
$env:XBE_CAPTURE_DIR = "captures"
$p = Start-Process -FilePath ".\aa_roas.exe" -PassThru
Start-Sleep -Seconds 7

# Take a screenshot of primary screen
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$gfx = [System.Drawing.Graphics]::FromImage($bmp)
$gfx.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)

$outDir = "$PSScriptRoot\..\screenshots"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir }
$outPath = Join-Path $outDir "screen_sample.png"
$bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
$gfx.Dispose()
$bmp.Dispose()
Write-Host "Screenshot saved to $outPath"

# Inspect pixel colors (e.g. center)
$bmp2 = New-Object System.Drawing.Bitmap $outPath
$centerX = [int]($bounds.Width / 2)
$centerY = [int]($bounds.Height / 2)
$centerPixel = $bmp2.GetPixel($centerX, $centerY)
Write-Host "Center pixel: R=$($centerPixel.R), G=$($centerPixel.G), B=$($centerPixel.B)"

# Also sample multiple points across the screen to see if anything is non-black
$nonBlackCount = 0
for ($x = 100; $x -lt $bounds.Width; $x += 50) {
    for ($y = 100; $y -lt $bounds.Height; $y += 50) {
        $c = $bmp2.GetPixel($x, $y)
        if ($c.R -gt 15 -or $c.G -gt 15 -or $c.B -gt 15) {
            $nonBlackCount++
        }
    }
}
$bmp2.Dispose()
Write-Host "Non-black sample count: $nonBlackCount"

if (-not $p.HasExited) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
