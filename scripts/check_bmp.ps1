Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap "out/build/release/captures/021802/final.bmp"
Write-Host "Size: $($bmp.Width) x $($bmp.Height)"
$nonBlack = 0
$samples = @()
for ($y = 0; $y -lt $bmp.Height; $y += 5) {
    for ($x = 0; $x -lt $bmp.Width; $x += 5) {
        $c = $bmp.GetPixel($x, $y)
        if ($c.R -gt 0 -or $c.G -gt 0 -or $c.B -gt 0) {
            $nonBlack++
            if ($samples.Count -lt 10) {
                $samples += "($x, $y): R=$($c.R) G=$($c.G) B=$($c.B) A=$($c.A)"
            }
        }
    }
}
$bmp.Dispose()
Write-Host "Non-black samples: $nonBlack"
$samples | ForEach-Object { Write-Host "  Sample: $_" }
