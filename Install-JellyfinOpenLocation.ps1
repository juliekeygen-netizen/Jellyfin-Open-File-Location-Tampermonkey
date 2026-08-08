$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:LOCALAPPDATA 'JellyfinOpenLocation'
$VbsHandlerPath = Join-Path $InstallDir 'JellyOpenHandler.vbs'
$PsHandlerPath = Join-Path $InstallDir 'JellyOpenHandler.ps1'

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

$VbsSourcePath = Join-Path $PSScriptRoot 'JellyOpenHandler.vbs'
$PsSourcePath = Join-Path $PSScriptRoot 'JellyOpenHandler.ps1'

if (-not (Test-Path -LiteralPath $VbsSourcePath)) {
    throw "Missing installer file: $VbsSourcePath"
}

if (-not (Test-Path -LiteralPath $PsSourcePath)) {
    throw "Missing installer file: $PsSourcePath"
}

Copy-Item -LiteralPath $VbsSourcePath -Destination $VbsHandlerPath -Force
Copy-Item -LiteralPath $PsSourcePath -Destination $PsHandlerPath -Force

# Validate the PowerShell helper before registering it.
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $PsHandlerPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join "`n"
    throw "The installed PowerShell helper failed syntax validation:`n$messages"
}

# Both helpers contain a self-test path so setup catches broken files early.
& "$env:SystemRoot\System32\cscript.exe" //nologo $VbsHandlerPath --selftest
if ($LASTEXITCODE -ne 0) {
    throw "The VBS helper self-test failed with exit code $LASTEXITCODE."
}

& "$PSHOME\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PsHandlerPath -SelfTest
if ($LASTEXITCODE -ne 0) {
    throw "The PowerShell helper self-test failed with exit code $LASTEXITCODE."
}

function Register-Protocol {
    param(
        [string]$Name,
        [string]$Description,
        [string]$Command
    )

    $Root = "HKCU:\Software\Classes\$Name"

    if (Test-Path $Root) {
        Remove-Item -Path $Root -Recurse -Force
    }

    New-Item -Path $Root -Force | Out-Null
    Set-Item -Path $Root -Value "URL:$Description"

    New-ItemProperty `
        -Path $Root `
        -Name 'URL Protocol' `
        -Value '' `
        -PropertyType String `
        -Force | Out-Null

    $IconKey = Join-Path $Root 'DefaultIcon'
    New-Item -Path $IconKey -Force | Out-Null
    Set-Item -Path $IconKey -Value 'shell32.dll,3'

    $CommandKey = Join-Path $Root 'shell\open\command'
    New-Item -Path $CommandKey -Force | Out-Null
    Set-Item -Path $CommandKey -Value $Command
}

$WScriptExe = Join-Path $env:SystemRoot 'System32\wscript.exe'
$PowerShellExe = Join-Path $PSHOME 'powershell.exe'

$VbsCommand = "`"$WScriptExe`" //nologo `"$VbsHandlerPath`" `"%1`""

$PsCommand = `
    "`"$PowerShellExe`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
    "-File `"$PsHandlerPath`" -Uri `"%1`""

$PsDebugCommand = `
    "`"$PowerShellExe`" -NoProfile -ExecutionPolicy Bypass -NoExit " +
    "-File `"$PsHandlerPath`" -Uri `"%1`" -DebugConsole"

Register-Protocol `
    -Name 'jellyopen-vbs' `
    -Description 'Jellyfin Open File Location (VBS)' `
    -Command $VbsCommand

Register-Protocol `
    -Name 'jellyopen-ps' `
    -Description 'Jellyfin Open File Location (PowerShell Hidden)' `
    -Command $PsCommand

Register-Protocol `
    -Name 'jellyopen-psdebug' `
    -Description 'Jellyfin Open File Location (PowerShell Debug)' `
    -Command $PsDebugCommand

# Remove protocol names used by older development versions.
$OldProtocol = 'HKCU:\Software\Classes\jellyopen'
if (Test-Path $OldProtocol) {
    Remove-Item -Path $OldProtocol -Recurse -Force
}

Write-Host ''
Write-Host 'Installed Jellyfin Open File Location helper.' -ForegroundColor Green
Write-Host ''
Write-Host 'Registered helper modes:'
Write-Host '  vbs              -> invisible, default'
Write-Host '  powershell       -> hidden PowerShell'
Write-Host '  powershell-debug -> visible PowerShell that stays open'
Write-Host ''
Write-Host "Installed files: $InstallDir"

$StandardDOpus = Join-Path $env:ProgramFiles 'GPSoftware\Directory Opus\DOpusRT.exe'
if (Test-Path -LiteralPath $StandardDOpus) {
    Write-Host ''
    Write-Host 'Directory Opus detected:' -ForegroundColor Cyan
    Write-Host "  $StandardDOpus"
}
else {
    Write-Host ''
    Write-Host 'Directory Opus was not found in its standard Program Files location.' -ForegroundColor Yellow
    Write-Host 'The helper also checks Windows App Paths at launch; otherwise auto mode falls back to Explorer.'
}

Write-Host ''
Write-Host 'Next: install Jellyfin-Open-File-Location.user.js in Tampermonkey.'
