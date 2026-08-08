param(
    [Parameter(Position = 0)]
    [string]$Uri,

    [switch]$DebugConsole,

    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

if ($SelfTest) {
    exit 0
}

function Write-DebugLine {
    param([string]$Text)

    if ($DebugConsole) {
        Write-Host $Text
    }
}

function Show-HandlerError {
    param([string]$Message)

    if ($DebugConsole) {
        Write-Host ''
        Write-Host 'ERROR:' -ForegroundColor Red
        Write-Host $Message -ForegroundColor Red
        Write-Host ''
        Write-Host 'This PowerShell window is intentionally left open by the'
        Write-Host "'powershell-debug' helper mode."
        return
    }

    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            'Jellyfin - Open file location',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    }
    catch {
        # Hidden mode has no useful console; return a non-zero exit code below.
    }
}

function Get-QueryParameter {
    param(
        [string]$Url,
        [string]$Name
    )

    $question = $Url.IndexOf('?')
    if ($question -lt 0) {
        return $null
    }

    foreach ($part in $Url.Substring($question + 1).Split('&')) {
        $eq = $part.IndexOf('=')
        if ($eq -lt 1) {
            continue
        }

        $key = $part.Substring(0, $eq)
        if ($key -ieq $Name) {
            return $part.Substring($eq + 1)
        }
    }

    return $null
}

function ConvertFrom-Base64UrlUtf8 {
    param([string]$Value)

    $base64 = $Value.Replace('-', '+').Replace('_', '/')

    switch ($base64.Length % 4) {
        2 { $base64 += '==' }
        3 { $base64 += '=' }
        0 { }
        default { throw 'Invalid base64url payload length.' }
    }

    $bytes = [Convert]::FromBase64String($base64)
    return [Text.Encoding]::UTF8.GetString($bytes)
}

function Get-DOpusRT {
    $candidates = New-Object System.Collections.Generic.List[string]

    try {
        $command = Get-Command 'DOpusRT.exe' -ErrorAction SilentlyContinue
        if ($command -and $command.Source) {
            $candidates.Add($command.Source)
        }
    }
    catch {}

    if ($env:ProgramFiles) {
        $candidates.Add(
            (Join-Path $env:ProgramFiles 'GPSoftware\Directory Opus\DOpusRT.exe')
        )
    }

    if (${env:ProgramFiles(x86)}) {
        $candidates.Add(
            (Join-Path ${env:ProgramFiles(x86)} 'GPSoftware\Directory Opus\DOpusRT.exe')
        )
    }

    foreach ($key in @(
        'Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\App Paths\dopus.exe',
        'Registry::HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\App Paths\dopus.exe',
        'Registry::HKEY_LOCAL_MACHINE\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\dopus.exe'
    )) {
        try {
            if (Test-Path $key) {
                $dopusExe = (Get-Item $key).GetValue('')
                if ($dopusExe) {
                    $candidates.Add(
                        (Join-Path (Split-Path -Parent $dopusExe) 'DOpusRT.exe')
                    )
                }
            }
        }
        catch {}
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    return $null
}

function Open-InDirectoryOpus {
    param(
        [string]$DOpusRT,
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Write-DebugLine "Directory Opus folder: $Path"
        & $DOpusRT '/acmd' 'Go' $Path
        return
    }

    $parent = Split-Path -Parent $Path
    $name = Split-Path -Leaf $Path

    if (-not $parent -or -not $name) {
        throw "Could not split the media path into parent folder and filename: $Path"
    }

    Write-DebugLine "Directory Opus parent: $parent"
    Write-DebugLine "Directory Opus select: $name"

    & $DOpusRT '/acmd' 'Go' $parent

    Start-Sleep -Milliseconds 250

    for ($attempt = 1; $attempt -le 4; $attempt++) {
        & $DOpusRT '/acmd' 'Select' $name 'EXACT' 'DESELECTNOMATCH' 'MAKEVISIBLE'

        if ($attempt -lt 4) {
            Start-Sleep -Milliseconds 250
        }
    }
}

function Open-InExplorer {
    param([string]$Path)

    Write-DebugLine "Explorer target: $Path"

    if (Test-Path -LiteralPath $Path -PathType Container) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('"{0}"' -f $Path)
    }
    else {
        Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $Path)
    }
}

try {
    if (-not $Uri) {
        throw 'No jellyopen URL was supplied.'
    }

    $Uri = $Uri.Trim().Trim('"')

    Write-DebugLine "URL: $Uri"

    if ($Uri -notmatch '^jellyopen-(?:vbs|ps|psdebug)://') {
        throw 'Invalid jellyopen protocol URL.'
    }

    $data = Get-QueryParameter -Url $Uri -Name 'data'
    if (-not $data) {
        throw 'No encoded media path was supplied.'
    }

    $fileManager = Get-QueryParameter -Url $Uri -Name 'fm'
    if (-not $fileManager) {
        $fileManager = 'auto'
    }

    $fileManager = $fileManager.ToLowerInvariant()
    if ($fileManager -notin @('auto', 'dopus', 'explorer')) {
        $fileManager = 'auto'
    }

    $Path = ConvertFrom-Base64UrlUtf8 $data
    $Path = $Path.Trim().Trim('"')

    Write-DebugLine "Decoded path: $Path"
    Write-DebugLine "File manager mode: $fileManager"

    if ($Path -notmatch '^(?:[A-Za-z]:\\|\\\\)') {
        throw "Refusing a non-Windows path:`n$Path"
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "The path reported by Jellyfin does not exist on this PC:`n`n$Path"
    }

    $dopusRT = $null

    if ($fileManager -ne 'explorer') {
        $dopusRT = Get-DOpusRT
    }

    if ($fileManager -eq 'dopus' -and -not $dopusRT) {
        throw 'Directory Opus was requested in the userscript, but DOpusRT.exe could not be found.'
    }

    if ($dopusRT -and $fileManager -ne 'explorer') {
        Write-DebugLine "DOpusRT: $dopusRT"
        Open-InDirectoryOpus -DOpusRT $dopusRT -Path $Path
    }
    else {
        Open-InExplorer -Path $Path
    }

    Write-DebugLine 'Done.'
    exit 0
}
catch {
    Show-HandlerError $_.Exception.Message
    exit 1
}
