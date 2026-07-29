#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $HOME '.hmm-history'),
    [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
    [switch]$Force,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$sourceScript = Join-Path $PSScriptRoot 'hmm.ps1'
$targetScript = Join-Path $InstallDirectory 'hmm.ps1'
$profilePath = $ProfilePath
$profileDirectory = Split-Path -Parent $profilePath
$startMarker = '# >>> hmm-history >>>'
$endMarker = '# <<< hmm-history <<<'

function Remove-HmmProfileBlock {
    param([string]$Content)
    $pattern = '(?ms)^' + [regex]::Escape($startMarker) + '.*?^' + [regex]::Escape($endMarker) + '\s*(?:\r?\n)?'
    return [regex]::Replace($Content, $pattern, '')
}

if ($Uninstall) {
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $old = Get-Content -Raw -LiteralPath $profilePath
        $new = Remove-HmmProfileBlock $old
        if ($new -ne $old) { [IO.File]::WriteAllText($profilePath, $new) }
    }
    if (Test-Path -LiteralPath $targetScript -PathType Leaf) {
        Remove-Item -LiteralPath $targetScript -Force
    }
    if ((Test-Path -LiteralPath $InstallDirectory -PathType Container) -and -not (Get-ChildItem -LiteralPath $InstallDirectory -Force)) {
        Remove-Item -LiteralPath $InstallDirectory
    }
    Write-Host 'hmm-history removed. Restart PowerShell to discard the loaded key handler.' -ForegroundColor Green
    return
}

if (-not (Test-Path -LiteralPath $sourceScript -PathType Leaf)) {
    throw "hmm.ps1 was not found next to install.ps1: $sourceScript"
}
New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
# Re-running the installer is an update. -Force remains accepted for backward compatibility.
Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force
New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
if (-not (Test-Path -LiteralPath $profilePath)) { New-Item -ItemType File -Path $profilePath -Force | Out-Null }

$profileContent = Get-Content -Raw -LiteralPath $profilePath
$profileContent = Remove-HmmProfileBlock ([string]$profileContent)
$escaped = $targetScript.Replace("'", "''")
$block = @"
$startMarker
if (Test-Path -LiteralPath '$escaped') { . '$escaped' }
$endMarker
"@
if ($profileContent.Length -and -not $profileContent.EndsWith([Environment]::NewLine)) {
    $profileContent += [Environment]::NewLine
}
[IO.File]::WriteAllText($profilePath, $profileContent + $block + [Environment]::NewLine)

Write-Host 'hmm-history installed.' -ForegroundColor Green
Write-Host "Script:  $targetScript"
Write-Host "Profile: $profilePath"
Write-Host 'Reload with: . $PROFILE' -ForegroundColor Yellow
Write-Host 'Uninstall with: ./install.ps1 -Uninstall' -ForegroundColor DarkGray
