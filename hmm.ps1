#Requires -Version 7.0

<#
.SYNOPSIS
    Interactive, numbered search for the persistent PSReadLine history.

.DESCRIPTION
    Searches commands stored in the PSReadLine history file, displays recent
    matching commands in numbered pages, and recalls the selected command into
    the editable PowerShell prompt without executing it.

    Usage:
        hmm route
        hmm "Microsoft PowerShell"
        hmm 9

    Interactive controls:
        Number  Recall a result without executing it
        Enter   Next page, or close on the final page
        P       Previous page
        Q/Esc   Quit
        Ctrl+C  Cancel
#>

Import-Module PSReadLine -ErrorAction Stop

# Prefix-based history navigation using the text already entered.
Set-PSReadLineKeyHandler -Chord UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Chord DownArrow -Function HistorySearchForward
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# User configuration.
$global:HmmPageSize = 15
$global:HmmKeepDuplicates = $false
$global:HmmShowFullCommands = $false

# State for direct recall through: hmm <number>
$global:HmmLastSearch = $null
$global:HmmLastResults = @()

function global:Get-HmmHistoryEntries {
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $entries = [System.Collections.Generic.List[string]]::new()
    $current = [System.Collections.Generic.List[string]]::new()

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        $current.Add($line)

        # PSReadLine normally stores intermediate lines of a multiline command
        # with a trailing backtick.
        if (-not $line.EndsWith('`')) {
            $entries.Add(($current -join [Environment]::NewLine))
            $current.Clear()
        }
    }

    if ($current.Count -gt 0) {
        $entries.Add(($current -join [Environment]::NewLine))
    }

    return $entries.ToArray()
}

function global:Find-HmmHistory {
    param (
        [Parameter(Mandatory)]
        [string]$Query
    )

    $historyPath = (Get-PSReadLineOption).HistorySavePath

    if (-not (Test-Path -LiteralPath $historyPath)) {
        Write-Host ''
        Write-Host 'PSReadLine history file not found:' -ForegroundColor Yellow
        Write-Host $historyPath -ForegroundColor DarkGray
        return @()
    }

    $historyEntries = @(Get-HmmHistoryEntries -Path $historyPath)
    $results = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )

    # Newest commands first.
    for ($i = $historyEntries.Count - 1; $i -ge 0; $i--) {
        $command = $historyEntries[$i].TrimEnd()

        if ([string]::IsNullOrWhiteSpace($command)) {
            continue
        }

        # Exclude searches performed with hmm itself.
        if ($command -match '^\s*hmm(?:\s|$)') {
            continue
        }

        if (
            $command.IndexOf(
                $Query,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -lt 0
        ) {
            continue
        }

        if ($global:HmmKeepDuplicates -or $seen.Add($command)) {
            $results.Add($command)
        }
    }

    return $results.ToArray()
}

function global:Show-HmmPage {
    param (
        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [string[]]$Results,

        [Parameter(Mandatory)]
        [int]$CurrentPage,

        [Parameter(Mandatory)]
        [int]$PageSize
    )

    $totalResults = $Results.Count
    $totalPages = [int][Math]::Ceiling($totalResults / [double]$PageSize)
    $startIndex = $CurrentPage * $PageSize
    $endIndex = [Math]::Min($startIndex + $PageSize, $totalResults)
    $numberWidth = $totalResults.ToString().Length

    try {
        $consoleWidth = $Host.UI.RawUI.WindowSize.Width
    }
    catch {
        $consoleWidth = 120
    }

    $previewWidth = [Math]::Max(30, $consoleWidth - $numberWidth - 5)

    Write-Host ''
    $header = 'hmm: "{0}" - {1} results - page {2}/{3}' -f `
        $Query, $totalResults, ($CurrentPage + 1), $totalPages
    Write-Host $header -ForegroundColor Cyan
    Write-Host ''

    for ($i = $startIndex; $i -lt $endIndex; $i++) {
        $number = $i + 1
        $preview = $Results[$i] -replace "(`r`n|`n|`r)", '  <line>  '

        if (
            -not $global:HmmShowFullCommands -and
            $preview.Length -gt $previewWidth
        ) {
            $preview = $preview.Substring(0, $previewWidth - 1) + '...'
        }

        $lineFormat = '[{0,' + $numberWidth + '}] {1}'
        $formattedLine = $lineFormat -f $number, $preview
        Write-Host $formattedLine
    }
}

function global:Read-HmmSelection {
    param (
        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter(Mandatory)]
        [string[]]$Results,

        [Parameter(Mandatory)]
        [int]$PageSize
    )

    $totalResults = $Results.Count
    $totalPages = [int][Math]::Ceiling($totalResults / [double]$PageSize)
    $currentPage = 0

    while ($true) {
        Show-HmmPage `
            -Query $Query `
            -Results $Results `
            -CurrentPage $currentPage `
            -PageSize $PageSize

        Write-Host ''

        if ($currentPage -lt ($totalPages - 1)) {
            $promptText = 'Number = recall, Enter = next, P = previous, Q = quit: '
        }
        else {
            $promptText = 'Number = recall, Enter = close, P = previous, Q = quit: '
        }

        Write-Host -NoNewline $promptText
        $typedNumber = ''

        while ($true) {
            $keyInfo = [Console]::ReadKey($true)
            $ctrlPressed = (
                ($keyInfo.Modifiers -band [ConsoleModifiers]::Control) -ne 0
            )

            if ($ctrlPressed -and $keyInfo.Key -eq [ConsoleKey]::C) {
                Write-Host '^C'
                return $null
            }

            if ($keyInfo.Key -eq [ConsoleKey]::Escape) {
                Write-Host ''
                return $null
            }

            if ($keyInfo.Key -eq [ConsoleKey]::Backspace) {
                if ($typedNumber.Length -gt 0) {
                    $typedNumber = $typedNumber.Substring(0, $typedNumber.Length - 1)
                    [Console]::Write("`b `b")
                }
                continue
            }

            if ($keyInfo.Key -eq [ConsoleKey]::Enter) {
                Write-Host ''

                if ($typedNumber.Length -gt 0) {
                    $selectedNumber = 0
                    $validInteger = [int]::TryParse(
                        $typedNumber,
                        [ref]$selectedNumber
                    )

                    if (
                        $validInteger -and
                        $selectedNumber -ge 1 -and
                        $selectedNumber -le $totalResults
                    ) {
                        return [PSCustomObject]@{
                            Number = $selectedNumber
                            Command = $Results[$selectedNumber - 1]
                        }
                    }

                    Write-Host (
                        'Invalid number. Choose a value from 1 to {0}.' -f
                        $totalResults
                    ) -ForegroundColor Yellow
                    break
                }

                if ($currentPage -lt ($totalPages - 1)) {
                    $currentPage++
                    break
                }

                return $null
            }

            if ([char]::IsDigit($keyInfo.KeyChar)) {
                $typedNumber += $keyInfo.KeyChar
                [Console]::Write($keyInfo.KeyChar)
                continue
            }

            if ($typedNumber.Length -eq 0) {
                $character = [char]::ToLowerInvariant($keyInfo.KeyChar)

                if ($character -eq 'q') {
                    Write-Host $keyInfo.KeyChar
                    return $null
                }

                if ($character -eq 'p') {
                    Write-Host $keyInfo.KeyChar

                    if ($currentPage -gt 0) {
                        $currentPage--
                    }
                    else {
                        Write-Host 'Already on the first page.' `
                            -ForegroundColor DarkGray
                    }

                    break
                }
            }
        }
    }
}

function global:Invoke-HmmSelector {
    param (
        [Parameter(Mandatory)]
        [string]$Query
    )

    $results = @(Find-HmmHistory -Query $Query)
    $global:HmmLastSearch = $Query
    $global:HmmLastResults = @($results)

    if ($results.Count -eq 0) {
        Write-Host ''
        Write-Host ('No results for: "{0}"' -f $Query) -ForegroundColor Yellow
        return $null
    }

    return Read-HmmSelection `
        -Query $Query `
        -Results $results `
        -PageSize $global:HmmPageSize
}

# This function mainly reserves and documents the command name. In an
# interactive session, the custom Enter handler intercepts hmm before normal
# command execution.
function global:hmm {
    [CmdletBinding()]
    param (
        [Parameter(Position = 0, ValueFromRemainingArguments)]
        [string[]]$Text
    )

    Write-Warning 'Use hmm <search text> as the only command on the input line.'
}

Set-PSReadLineKeyHandler `
    -Chord Enter `
    -BriefDescription 'HmmSelectorOrAcceptLine' `
    -LongDescription 'Open hmm or accept the input line normally' `
    -ScriptBlock {

        param($key, $arg)

        $line = $null
        $cursor = 0

        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState(
            [ref]$line,
            [ref]$cursor
        )

        # Preserve the standard Enter behavior for every other command.
        if ($line -notmatch '^\s*hmm(?:\s+(.*?))?\s*$') {
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
            return
        }

        if ($Matches.ContainsKey(1)) {
            $hmmArgument = $Matches[1].Trim()
        }
        else {
            $hmmArgument = ''
        }

        [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
        Write-Host ''

        if ([string]::IsNullOrWhiteSpace($hmmArgument)) {
            Write-Host 'Usage: hmm <search text>' -ForegroundColor Yellow
            Write-Host 'Example: hmm route' -ForegroundColor DarkGray

            $promptRow = [Console]::CursorTop
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt(
                $null,
                $promptRow
            )
            return
        }

        # Remove one matching pair of surrounding quotes.
        if ($hmmArgument.Length -ge 2) {
            $firstCharacter = $hmmArgument[0]
            $lastCharacter = $hmmArgument[$hmmArgument.Length - 1]
            $doubleQuoted = $firstCharacter -eq '"' -and $lastCharacter -eq '"'
            $singleQuoted = $firstCharacter -eq "'" -and $lastCharacter -eq "'"

            if ($doubleQuoted -or $singleQuoted) {
                $hmmArgument = $hmmArgument.Substring(
                    1,
                    $hmmArgument.Length - 2
                )
            }
        }

        # Direct recall from the last result set: hmm <number>
        $requestedNumber = 0
        $isNumber = [int]::TryParse($hmmArgument, [ref]$requestedNumber)

        if ($isNumber) {
            if (
                $global:HmmLastResults -and
                $requestedNumber -ge 1 -and
                $requestedNumber -le $global:HmmLastResults.Count
            ) {
                $selectedCommand = [string]$global:HmmLastResults[
                    $requestedNumber - 1
                ]

                $promptRow = [Console]::CursorTop
                [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt(
                    $null,
                    $promptRow
                )
                [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selectedCommand)
                [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
                return
            }

            if (
                -not $global:HmmLastResults -or
                $global:HmmLastResults.Count -eq 0
            ) {
                Write-Host 'No hmm search has been run yet.' -ForegroundColor Yellow
            }
            else {
                Write-Host (
                    'Invalid number. Available results: 1-{0}.' -f
                    $global:HmmLastResults.Count
                ) -ForegroundColor Yellow
            }

            $promptRow = [Console]::CursorTop
            [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt(
                $null,
                $promptRow
            )
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($line)
            [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
            return
        }

        $selection = Invoke-HmmSelector -Query $hmmArgument

        # Anchor the new prompt to the current console row. Without the row
        # argument, PSReadLine can redraw the prompt above the result list.
        $promptRow = [Console]::CursorTop
        [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt(
            $null,
            $promptRow
        )

        if ($null -ne $selection) {
            $selectedCommand = [string]$selection.Command
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert($selectedCommand)
            [Microsoft.PowerShell.PSConsoleReadLine]::EndOfLine()
        }
    }
