$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectDirectory = Split-Path $PSScriptRoot -Parent
$brandDirectory = Join-Path $projectDirectory 'assets/branding'
New-Item -ItemType Directory -Force -Path $brandDirectory | Out-Null
$svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" rx="116" fill="#0B1014"/><g fill="none" stroke="#8BE0C0" stroke-width="28" stroke-linecap="round"><path d="M362.1 149.9A150 150 0 1 0 362.1 362.1"/><path d="M216 232v48m40-88v128m40-88v48"/></g><circle cx="406" cy="256" r="18" fill="#8BE0C0"/></svg>'
[IO.File]::WriteAllText((Join-Path $brandDirectory 'aura.svg'), $svg)
function Save-AuraPng([int]$size, [string]$destination) {
    $bitmap = New-Object Drawing.Bitmap($size, $size)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = 'AntiAlias'
    $graphics.ScaleTransform(($size / 512.0), ($size / 512.0))
    $graphics.Clear([Drawing.ColorTranslator]::FromHtml('#0B1014'))
    $mintBrush = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#8BE0C0'))
    $pen = New-Object Drawing.Pen($mintBrush, 28)
    $pen.StartCap = 'Round'; $pen.EndCap = 'Round'
    $graphics.DrawArc($pen, 106, 106, 300, 300, 45, 270)
    $graphics.DrawLine($pen, 216, 232, 216, 280)
    $graphics.DrawLine($pen, 256, 192, 256, 320)
    $graphics.DrawLine($pen, 296, 232, 296, 280)
    $graphics.FillEllipse($mintBrush, 388, 238, 36, 36)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
    $bitmap.Save($destination, [Drawing.Imaging.ImageFormat]::Png)
    $pen.Dispose(); $mintBrush.Dispose(); $graphics.Dispose(); $bitmap.Dispose()
}
Save-AuraPng 512 (Join-Path $brandDirectory 'aura.png')
$androidSizes = @{mdpi=48;hdpi=72;xhdpi=96;xxhdpi=144;xxxhdpi=192}
foreach ($density in $androidSizes.Keys) {
    Save-AuraPng $androidSizes[$density] (Join-Path $projectDirectory "android/app/src/main/res/mipmap-$density/ic_launcher.png")
}
foreach ($size in @(192, 512)) {
    Save-AuraPng $size (Join-Path $projectDirectory "web/icons/Icon-$size.png")
    Save-AuraPng $size (Join-Path $projectDirectory "web/icons/Icon-maskable-$size.png")
}
Save-AuraPng 32 (Join-Path $projectDirectory 'web/favicon.png')
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$images = @($sizes | ForEach-Object {
    $imagePath = Join-Path $brandDirectory "icon-$_.png"
    Save-AuraPng $_ $imagePath
    ,([IO.File]::ReadAllBytes($imagePath))
    Remove-Item -LiteralPath $imagePath
})
$iconPath = Join-Path $projectDirectory 'windows/runner/resources/app_icon.ico'
$writer = New-Object IO.BinaryWriter([IO.File]::Create($iconPath))
try {
    $writer.Write([uint16]0); $writer.Write([uint16]1); $writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16 * $sizes.Count
    for ($index=0; $index -lt $sizes.Count; $index++) {
        $dimension = $sizes[$index] % 256
        $writer.Write([byte]$dimension); $writer.Write([byte]$dimension)
        $writer.Write([byte]0); $writer.Write([byte]0)
        $writer.Write([uint16]1); $writer.Write([uint16]32)
        $writer.Write([uint32]$images[$index].Length); $writer.Write([uint32]$offset)
        $offset += $images[$index].Length
    }
    foreach ($bytes in $images) { $writer.Write([byte[]]$bytes) }
} finally { $writer.Dispose() }
Write-Output 'Aura assets generated.'
