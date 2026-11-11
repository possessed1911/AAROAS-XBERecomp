Add-Type -AssemblyName System.Drawing
$latestCap = Get-ChildItem -Path "out/build/release/captures" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$bmpPath = Join-Path $latestCap.FullName "final.bmp"
Write-Host "Reading $bmpPath"
$bmp = New-Object System.Drawing.Bitmap $bmpPath
Write-Host "Image width: $($bmp.Width) height: $($bmp.Height)"

# Draw a rough 64x24 ASCII map of brightness
for ($y = 0; $y -lt $bmp.Height; $y += 20) {
    $line = ""
    for ($x = 0; $x -lt $bmp.Width; $x += 10) {
        $c = $bmp.GetPixel($x, $y)
        $bright = [int](($c.R * 0.299) + ($c.G * 0.587) + ($c.B * 0.114))
        if ($bright -gt 150) { $line += "#" }
        elseif ($bright -gt 80) { $line += "+" }
        elseif ($bright -gt 30) { $line += "." }
        else { $line += " " }
    }
    Write-Host $line
}
$bmp.Dispose()
