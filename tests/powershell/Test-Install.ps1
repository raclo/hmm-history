$ErrorActionPreference = 'Stop'
$repo = Resolve-Path (Join-Path $PSScriptRoot '..' '..')
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hmm-install-tests-' + [guid]::NewGuid())
$installDirectory = Join-Path $tempRoot 'install'
$profilePath = Join-Path $tempRoot 'profile.ps1'
New-Item -ItemType Directory -Path $tempRoot | Out-Null
[IO.File]::WriteAllText($profilePath, "# existing configuration$([Environment]::NewLine)")
try {
    & (Join-Path $repo 'install.ps1') -InstallDirectory $installDirectory -ProfilePath $profilePath
    & (Join-Path $repo 'install.ps1') -InstallDirectory $installDirectory -ProfilePath $profilePath
    if (-not (Test-Path -LiteralPath (Join-Path $installDirectory 'hmm.ps1'))) { throw 'Installed script missing' }
    $content = Get-Content -Raw -LiteralPath $profilePath
    if ([regex]::Matches($content, [regex]::Escape('# >>> hmm-history >>>')).Count -ne 1) { throw 'Profile block is not idempotent' }
    if (-not $content.Contains('# existing configuration')) { throw 'Existing profile content was lost' }
    & (Join-Path $repo 'install.ps1') -InstallDirectory $installDirectory -ProfilePath $profilePath -Uninstall
    if (Test-Path -LiteralPath (Join-Path $installDirectory 'hmm.ps1')) { throw 'Installed script remains after uninstall' }
    if ((Get-Content -Raw -LiteralPath $profilePath) -match [regex]::Escape('# >>> hmm-history >>>')) { throw 'Profile block remains after uninstall' }
    Write-Host 'PowerShell installer tests passed'
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
