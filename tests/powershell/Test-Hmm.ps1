$ErrorActionPreference = 'Stop'
$env:HMM_TESTING = '1'
. (Join-Path $PSScriptRoot '..' '..' 'hmm.ps1')

$script:Failures = 0
function Assert-Equal($Expected, $Actual, [string]$Message) {
    if ($Expected -cne $Actual) {
        Write-Error "FAIL: $Message`n expected: <$Expected>`n actual:   <$Actual>" -ErrorAction Continue
        $script:Failures++
    }
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hmm-tests-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $history = Join-Path $tempRoot 'history.txt'
    $lines = @(
        'pip old',
        'echo "quoted pip" | Set-Content output.txt',
        'hmm pip',
        'PIP install new',
        'pip old',
        'Write-Output Grüße',
        'Write-Output first`',
        'Write-Output second',
        '  pip old  '
    )
    [IO.File]::WriteAllText($history, ($lines -join [Environment]::NewLine))
    $results = @(Find-HmmHistory -Query pip -Path $history)
    Assert-Equal 3 $results.Count 'literal middle search, hmm exclusion, deduplication'
    Assert-Equal '  pip old  ' $results[0] 'newest duplicate wins without changing recalled text'
    Assert-Equal 'PIP install new' $results[1] 'case-insensitive matching'
    Assert-Equal 'echo "quoted pip" | Set-Content output.txt' $results[2] 'quotes and pipe'
    $duplicates = @(Find-HmmHistory -Query pip -Path $history -KeepDuplicates)
    Assert-Equal 5 $duplicates.Count 'optional duplicate preservation'
    Assert-Equal 0 @(Find-HmmHistory -Query absent -Path $history).Count 'empty result'
    Assert-Equal 0 @(Find-HmmHistory -Query x -Path (Join-Path $tempRoot 'missing')).Count 'missing file'
    $unicode = @(Find-HmmHistory -Query grüße -Path $history)
    Assert-Equal 'Write-Output Grüße' $unicode[0] 'Unicode case-insensitive search'
    $multiline = @(Find-HmmHistory -Query second -Path $history)
    Assert-Equal "Write-Output first``$([Environment]::NewLine)Write-Output second" $multiline[0] 'multiline preservation'

    $range = Get-HmmPageRange -ResultCount 16 -PageSize 15 -Page 0
    Assert-Equal 2 $range.TotalPages 'pagination page count'
    Assert-Equal 15 $range.EndExclusive 'first page boundary'
    $range = Get-HmmPageRange -ResultCount 16 -PageSize 15 -Page 1
    Assert-Equal 15 $range.Start 'last page start'
    Assert-Equal 16 $range.EndExclusive 'last page end'

    $recall = Resolve-HmmResultNumber -Value 2 -Results @('one', 'two')
    Assert-Equal $true $recall.IsValid 'valid direct recall number'
    Assert-Equal 'two' $recall.Command 'valid direct recall command'
    foreach ($invalid in @('0', '3', '9999999999')) {
        $recall = Resolve-HmmResultNumber -Value $invalid -Results @('one', 'two')
        Assert-Equal $true $recall.IsNumeric "numeric direct recall classification: $invalid"
        Assert-Equal $false $recall.IsValid "invalid direct recall rejection: $invalid"
    }
    $recall = Resolve-HmmResultNumber -Value pip -Results @('one', 'two')
    Assert-Equal $false $recall.IsNumeric 'search text is not direct recall'

    $long = 'prefix ' + ('x' * 200) + ' suffix'
    [IO.File]::WriteAllText($history, $long)
    Assert-Equal $long @(Find-HmmHistory -Query suffix -Path $history)[0] 'long stored command is unchanged'

    $probe = { param($key, $arg) [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine() }
    Set-PSReadLineKeyHandler -Chord Enter -BriefDescription ExistingProbe -LongDescription ExistingProbe -ScriptBlock $probe
    $global:HmmBindingEnabled = $false
    Enable-Hmm -WarningAction SilentlyContinue
    Assert-Equal 'ExistingProbe' (Get-PSReadLineKeyHandler -Chord Enter).Function 'custom Enter handler is not overwritten'

    Set-PSReadLineKeyHandler -Chord Enter -Function AcceptLine
    Enable-Hmm
    Assert-Equal 'HmmSelectorOrAcceptLine' (Get-PSReadLineKeyHandler -Chord Enter).Function 'hmm Enter handler is installed'
    $global:HmmBindingEnabled = $false
    Enable-Hmm
    Assert-Equal 'HmmSelectorOrAcceptLine' (Get-PSReadLineKeyHandler -Chord Enter).Function 'existing hmm handler is refreshed when re-sourced'
    Disable-Hmm
    Assert-Equal 'AcceptLine' (Get-PSReadLineKeyHandler -Chord Enter).Function 'default Enter handler is restored'
}
finally {
    Set-PSReadLineKeyHandler -Chord Enter -Function AcceptLine
    $global:HmmBindingEnabled = $false
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
    Remove-Item Env:HMM_TESTING -ErrorAction SilentlyContinue
}

if ($script:Failures) { throw "$script:Failures PowerShell test(s) failed" }
Write-Host 'All PowerShell logic tests passed'
