#Requires -Version 7.0

[CmdletBinding()]
param (
    [string]$InstallDirectory = (Join-Path $HOME '.hmm-history'),
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$sourceScript = Join-Path $PSScriptRoot 'hmm.ps1'
$targetScript = Join-Path $InstallDirectory 'hmm.ps1'
$profilePath = $PROFILE.CurrentUserCurrentHost
$profileDirectory = Split-Path -Parent $profilePath
$dotSourceLine = '. "{0}"' -f $targetScript

if (-not (Test-Path -LiteralPath $sourceScript)) {
    throw "hmm.ps1 was not found next to install.ps1: $sourceScript"
}

if (-not (Test-Path -LiteralPath $InstallDirectory)) {
    New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
}

if ((Test-Path -LiteralPath $targetScript) -and -not $Force) {
    throw "The target file already exists: $targetScript. Run again with -Force to replace it."
}

Copy-Item -LiteralPath $sourceScript -Destination $targetScript -Force

if (-not (Test-Path -LiteralPath $profileDirectory)) {
    New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
}

$profileCreated = -not (Test-Path -LiteralPath $profilePath)

if ($profileCreated) {
    New-Item -ItemType File -Path $profilePath -Force | Out-Null
}

$profileContent = Get-Content -LiteralPath $profilePath -Raw

if ($null -eq $profileContent -or $profileContent -notmatch [regex]::Escape($dotSourceLine)) {
    $block = @"

# hmm-history
$dotSourceLine
"@

    Add-Content -LiteralPath $profilePath -Value $block
    $profileChanged = $true
}
else {
    $profileChanged = $false
}

Write-Host ''
Write-Host 'hmm-history installed.' -ForegroundColor Green
Write-Host "Script:  $targetScript"
Write-Host "Profile: $profilePath"

if ($profileChanged) {
    if ($profileCreated) {
        Write-Host 'The PowerShell profile was created and configured.' -ForegroundColor Cyan
    }
    else {
        Write-Host 'The PowerShell profile was updated.' -ForegroundColor Cyan
    }
}
else {
    Write-Host 'The profile already contained the required dot-source line.' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Reload the profile with:'
Write-Host '. $PROFILE' -ForegroundColor Yellow
