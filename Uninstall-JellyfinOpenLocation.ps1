$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'JellyfinOpenLocation'

foreach ($Protocol in @(
    'jellyopen',
    'jellyopen-vbs',
    'jellyopen-ps',
    'jellyopen-psdebug'
)) {
    $Root = "HKCU:\Software\Classes\$Protocol"

    if (Test-Path $Root) {
        Remove-Item -Path $Root -Recurse -Force
    }
}

if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
}

Write-Host ''
Write-Host 'Removed the Jellyfin Open File Location Windows helper.' -ForegroundColor Green
Write-Host 'Disable/delete the Tampermonkey userscript separately if desired.'
