#Requires -Version 7.0

<#
.SYNOPSIS
    Search PSReadLine history and recall a command without executing it.
#>

Import-Module PSReadLine -ErrorAction Stop

# Set these before dot-sourcing to override the defaults.
if ($null -eq $global:HmmPageSize) { $global:HmmPageSize = 15 }
if ($null -eq $global:HmmKeepDuplicates) { $global:HmmKeepDuplicates = $false }
if ($null -eq $global:HmmShowFullCommands) { $global:HmmShowFullCommands = $false }
$global:HmmLastSearch = $null
$global:HmmLastResults = @()
if ($null -eq $global:HmmBindingEnabled) { $global:HmmBindingEnabled = $false }

function global:Get-HmmHistoryEntries {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $entries = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($line in [System.IO.File]::ReadLines($Path)) {
            $current.Add($line)
            # PSReadLine marks continued physical lines with a trailing backtick.
            if (-not $line.EndsWith('`')) {
                $entries.Add(($current -join [Environment]::NewLine))
                $current.Clear()
            }
        }
    }
    catch {
        Write-Warning "Unable to read PSReadLine history: $($_.Exception.Message)"
        return @()
    }
    if ($current.Count -gt 0) { $entries.Add(($current -join [Environment]::NewLine)) }
    return $entries.ToArray()
}

function global:Find-HmmHistory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Query,
        [string]$Path,
        [switch]$KeepDuplicates
    )

    if (-not $PSBoundParameters.ContainsKey('Path')) {
        $Path = (Get-PSReadLineOption).HistorySavePath
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }

    $entries = @(Get-HmmHistoryEntries -Path $Path)
    $results = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $preserveDuplicates = $KeepDuplicates -or $global:HmmKeepDuplicates

    for ($i = $entries.Count - 1; $i -ge 0; $i--) {
        $command = $entries[$i].TrimEnd("`r", "`n")
        if ([string]::IsNullOrWhiteSpace($command)) { continue }
        if ($command -match '^\s*hmm(?:\s|$)') { continue }
        if ($command.IndexOf($Query, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        # Ignore surrounding whitespace for duplicate comparison while keeping
        # the original newest command unchanged for recall.
        $dedupeKey = $command.Trim()
        if ($preserveDuplicates -or $seen.Add($dedupeKey)) { $results.Add($command) }
    }
    return $results.ToArray()
}

function global:Get-HmmPageRange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateRange(0, [int]::MaxValue)][int]$ResultCount,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$PageSize,
        [Parameter(Mandatory)][ValidateRange(0, [int]::MaxValue)][int]$Page
    )
    $pages = if ($ResultCount) { [int][Math]::Ceiling($ResultCount / [double]$PageSize) } else { 0 }
    [pscustomobject]@{
        TotalPages = $pages
        Start = [Math]::Min($Page * $PageSize, $ResultCount)
        EndExclusive = [Math]::Min(($Page + 1) * $PageSize, $ResultCount)
    }
}

function global:Resolve-HmmResultNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Results
    )
    if ($Value -notmatch '^\d+$') {
        return [pscustomobject]@{ IsNumeric = $false; IsValid = $false; Number = 0; Command = $null }
    }
    $number = 0
    $parsed = [int]::TryParse($Value, [ref]$number)
    $valid = $parsed -and $number -ge 1 -and $number -le $Results.Count
    [pscustomobject]@{
        IsNumeric = $true
        IsValid = $valid
        Number = $number
        Command = if ($valid) { [string]$Results[$number - 1] } else { $null }
    }
}

function global:Get-HmmConsoleWidth {
    try {
        $width = [Console]::WindowWidth
        if ($width -gt 0) { return $width }
    } catch {}
    try {
        $width = $Host.UI.RawUI.WindowSize.Width
        if ($width -gt 0) { return $width }
    } catch {}
    return 120
}

function global:Show-HmmPage {
    param(
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][string[]]$Results,
        [Parameter(Mandatory)][int]$CurrentPage,
        [Parameter(Mandatory)][int]$PageSize
    )
    $range = Get-HmmPageRange -ResultCount $Results.Count -PageSize $PageSize -Page $CurrentPage
    $numberWidth = [Math]::Max(1, $Results.Count.ToString().Length)
    $previewWidth = [Math]::Max(10, (Get-HmmConsoleWidth) - $numberWidth - 5)

    Write-Host ''
    Write-Host ('hmm: "{0}" - {1} results - page {2}/{3}' -f $Query, $Results.Count, ($CurrentPage + 1), $range.TotalPages) -ForegroundColor Cyan
    Write-Host ''
    for ($i = $range.Start; $i -lt $range.EndExclusive; $i++) {
        $preview = $Results[$i] -replace "(`r`n|`n|`r)", '  <line>  '
        if (-not $global:HmmShowFullCommands -and $preview.Length -gt $previewWidth) {
            $preview = $preview.Substring(0, [Math]::Max(1, $previewWidth - 1)) + [char]0x2026
        }
        $format = '[{0,' + $numberWidth + '}] {1}'
        Write-Host ($format -f ($i + 1), $preview)
    }
}

function global:Read-HmmSelection {
    param(
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][string[]]$Results,
        [Parameter(Mandatory)][ValidateRange(1, [int]::MaxValue)][int]$PageSize
    )
    if ([Console]::IsInputRedirected) {
        Write-Warning 'hmm selection requires an interactive console.'
        return $null
    }
    $totalPages = [int][Math]::Ceiling($Results.Count / [double]$PageSize)
    $page = 0
    while ($true) {
        Show-HmmPage -Query $Query -Results $Results -CurrentPage $page -PageSize $PageSize
        Write-Host ''
        $action = if ($page -lt $totalPages - 1) { 'next' } else { 'close' }
        Write-Host -NoNewline "Number = recall, Enter = $action, P = previous, Q = quit: "
        $digits = ''
        while ($true) {
            try { $key = [Console]::ReadKey($true) }
            catch {
                Write-Host ''
                Write-Warning 'This host does not expose console key input.'
                return $null
            }
            $ctrl = ($key.Modifiers -band [ConsoleModifiers]::Control) -ne 0
            if ($ctrl -and $key.Key -eq [ConsoleKey]::C) { Write-Host '^C'; return $null }
            if ($key.Key -eq [ConsoleKey]::Escape) { Write-Host ''; return $null }
            if ($key.Key -eq [ConsoleKey]::Backspace) {
                if ($digits.Length) {
                    $digits = $digits.Substring(0, $digits.Length - 1)
                    try { [Console]::Write("`b `b") } catch { Write-Host -NoNewline "`b `b" }
                }
                continue
            }
            if ($key.Key -eq [ConsoleKey]::Enter) {
                Write-Host ''
                if ($digits.Length) {
                    $number = 0
                    if ([int]::TryParse($digits, [ref]$number) -and $number -ge 1 -and $number -le $Results.Count) {
                        return [pscustomobject]@{ Number = $number; Command = $Results[$number - 1] }
                    }
                    Write-Host "Invalid number. Choose a value from 1 to $($Results.Count)." -ForegroundColor Yellow
                    break
                }
                if ($page -lt $totalPages - 1) { $page++; break }
                return $null
            }
            if ([char]::IsDigit($key.KeyChar)) {
                $digits += $key.KeyChar
                try { [Console]::Write($key.KeyChar) } catch { Write-Host -NoNewline $key.KeyChar }
                continue
            }
            if (-not $digits.Length) {
                $character = [char]::ToLowerInvariant($key.KeyChar)
                if ($character -eq 'q') { Write-Host $key.KeyChar; return $null }
                if ($character -eq 'p') {
                    Write-Host $key.KeyChar
                    if ($page -gt 0) { $page-- } else { Write-Host 'Already on the first page.' -ForegroundColor DarkGray }
                    break
                }
            }
        }
    }
}

function global:Invoke-HmmSelector {
    param([Parameter(Mandatory)][string]$Query)
    $results = @(Find-HmmHistory -Query $Query)
    $global:HmmLastSearch = $Query
    $global:HmmLastResults = @($results)
    if (-not $results.Count) {
        Write-Host ''
        Write-Host "No results for: `"$Query`"" -ForegroundColor Yellow
        return $null
    }
    Read-HmmSelection -Query $Query -Results $results -PageSize $global:HmmPageSize
}

function global:Invoke-HmmPrompt {
    # The explicit row prevents PSReadLine from redrawing above selector output.
    try {
        $row = [Console]::CursorTop
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt($null, $row)
        return
    } catch {}
    try { [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
    catch { Write-Warning 'PSReadLine could not redraw the prompt in this host.' }
}

function global:hmm {
    [CmdletBinding()]
    param([Parameter(Position = 0, ValueFromRemainingArguments)][string[]]$Text)
    Write-Warning 'Type hmm <search text> as the only command on an interactive input line.'
}

$global:HmmEnterHandler = {
    param($key, $arg)
    $line = $null; $cursor = 0
    [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
    if ($line -notmatch '^\s*hmm(?:\s+(.*?))?\s*$') {
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine(); return
    }

    $argument = if ($Matches.ContainsKey(1)) { $Matches[1].Trim() } else { '' }
    [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
    Write-Host ''
    if (-not $argument) {
        Write-Host 'Usage: hmm <search text>' -ForegroundColor Yellow
        Invoke-HmmPrompt
        return
    }
    if ($argument.Length -ge 2 -and (($argument[0] -eq '"' -and $argument[-1] -eq '"') -or ($argument[0] -eq "'" -and $argument[-1] -eq "'"))) {
        $argument = $argument.Substring(1, $argument.Length - 2)
    }

    $recall = Resolve-HmmResultNumber -Value $argument -Results $global:HmmLastResults
    if ($recall.IsNumeric) {
        if ($recall.IsValid) {
            Invoke-HmmPrompt
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($recall.Command)
            [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
            return
        }
        if (-not $global:HmmLastResults.Count) { Write-Host 'No hmm search has been run yet.' -ForegroundColor Yellow }
        else { Write-Host "Invalid number. Available results: 1-$($global:HmmLastResults.Count)." -ForegroundColor Yellow }
        Invoke-HmmPrompt
        return
    }

    $selection = Invoke-HmmSelector -Query $argument
    Invoke-HmmPrompt
    if ($null -ne $selection) {
        [Microsoft.PowerShell.PSConsoleReadLine]::Insert([string]$selection.Command)
        [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
    }
}

function global:Enable-Hmm {
    [CmdletBinding()]
    param()
    if ($global:HmmBindingEnabled) { return }
    $current = Get-PSReadLineKeyHandler -Chord Enter -ErrorAction SilentlyContinue
    if ($current -and $current.Function -eq 'HmmSelectorOrAcceptLine') {
        # Re-sourcing replaces an older hmm handler with this script's current
        # implementation without treating it as a third-party conflict.
        Set-PSReadLineKeyHandler -Chord Enter -BriefDescription HmmSelectorOrAcceptLine -LongDescription 'Open hmm or accept the input line normally' -ScriptBlock $global:HmmEnterHandler
        $global:HmmBindingEnabled = $true
        return
    }
    if ($current -and $current.Function -ne 'AcceptLine') {
        Write-Warning "Enter is already bound to '$($current.Function)'. hmm did not replace it. Disable the conflicting handler explicitly before running Enable-Hmm."
        return
    }
    Set-PSReadLineKeyHandler -Chord Enter -BriefDescription HmmSelectorOrAcceptLine -LongDescription 'Open hmm or accept the input line normally' -ScriptBlock $global:HmmEnterHandler
    $global:HmmBindingEnabled = $true
}

function global:Disable-Hmm {
    Set-PSReadLineKeyHandler -Chord Enter -Function AcceptLine
    $global:HmmBindingEnabled = $false
}

if ($env:HMM_TESTING -ne '1') { Enable-Hmm }
