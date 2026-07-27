# hmm-history

A lightweight, dependency-free PowerShell history search and recall tool built on top of PSReadLine.

`hmm` searches the persistent PowerShell command history, shows recent matching commands in a numbered and paginated list, and lets you recall a selected command into the current prompt without executing it.

## Features

- Searches anywhere inside saved PowerShell commands
- Case-insensitive literal matching
- Shows the most recent matches first
- Removes duplicate commands by default
- Reconstructs multiline commands saved by PSReadLine
- Displays numbered, paginated results
- Recalls a command without executing it, so it can be reviewed or edited
- Supports both interactive selection and direct recall from the last result set
- Requires no external tools or modules beyond PSReadLine

## Requirements

- PowerShell 7 or later
- PSReadLine
- An interactive console host such as Windows Terminal

## Installation

Clone or download this repository, open PowerShell 7 in the repository directory, and run the installer:

```powershell
.\install.ps1
```

The installer:

- copies `hmm.ps1` to `$HOME\.hmm-history\hmm.ps1`;
- creates the current PowerShell host profile if it does not exist;
- adds the required dot-source line without replacing existing profile content.

Reload the profile to make `hmm` available in the current session:

```powershell
. $PROFILE
```

To update an existing installation, allow the installer to replace the installed copy:

```powershell
.\install.ps1 -Force
```

You can also select a different installation directory:

```powershell
.\install.ps1 -InstallDirectory 'C:\Tools\hmm-history'
```

### Manual installation

As an alternative to the installer, add a dot-source line for `hmm.ps1` to your PowerShell profile:

```powershell
. "$HOME\path\to\hmm-history\hmm.ps1"
```

A typical Windows profile path is:

```text
C:\Users\<username>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
```

To open the active profile:

```powershell
notepad $PROFILE
```

After editing the profile manually, reload it:

```powershell
. $PROFILE
```

## Usage

Search the saved history:

```powershell
hmm pip
```

Example output:

```text
hmm: "pip" — 18 results — page 1/2

[ 1] python -m pip list --outdated
[ 2] pip install passlib[bcrypt] --trusted-host pypi.org --trusted-host files.pythonhosted.org
[ 3] pip install matplotlib --trusted-host pypi.org --trusted-host files.pythonhosted.org --disable-pip-versi…
[ 4] python -m pip install --upgrade pip setuptools wheel
[ 5] pip install fastapi uvicorn[standard] python-multipart
[ 6] python -m pip install -r requirements.txt
[ 7] pip freeze > requirements.txt
[ 8] Get-ChildItem -Recurse -Filter requirements.txt | ForEach-Object { python -m pip install -r $_.FullName }

Number = recall, Enter = next, P = previous, Q = quit: 2
PS C:\> pip install passlib[bcrypt] --trusted-host pypi.org --trusted-host files.pythonhosted.org
```

The selected command is inserted into the prompt but is **not executed**. Edit it as needed, then press Enter when ready.

### Interactive controls

| Input | Action |
|---|---|
| `1`, `2`, `15`, ... | Recall that result into the prompt |
| `Enter` | Go to the next page, or close on the last page |
| `P` | Go to the previous page |
| `Q` | Quit and return to an empty prompt |
| `Esc` | Quit |
| `Ctrl+C` | Cancel |

### Recall from the last search

After running a search, recall a result directly:

```powershell
hmm 9
```

This inserts result 9 from the most recent `hmm` search into the prompt without executing it.

## Prefix search with the arrow keys

The script also configures PSReadLine so that Up and Down Arrow search command history using the text already entered at the beginning of the prompt.

For example, type:

```text
winget
```

then press Up Arrow to cycle through commands that begin with `winget`.

## Configuration

The following variables are defined near the top of `hmm.ps1`:

```powershell
$global:HmmPageSize = 15
$global:HmmKeepDuplicates = $false
$global:HmmShowFullCommands = $false
```

- `HmmPageSize` controls how many results are shown per page.
- `HmmKeepDuplicates` keeps repeated commands when set to `$true`.
- `HmmShowFullCommands` disables line truncation when set to `$true`.

## How it works

`hmm` reads the persistent history file configured by PSReadLine:

```powershell
(Get-PSReadLineOption).HistorySavePath
```

It reconstructs multiline commands, filters them using a case-insensitive literal search, stores the last result set, and uses a custom PSReadLine Enter handler to place the selected command back into the editable input buffer.

The standard Enter behavior remains unchanged for commands that do not match the `hmm` syntax.

## Known limitations

- Intended for interactive PowerShell sessions; it is not designed for non-interactive scripts.
- The custom Enter handler may conflict with another profile script that also replaces the Enter key binding.
- Console rendering can vary between hosts. Windows Terminal with a recent PowerShell and PSReadLine version is recommended.
- `hmm <number>` refers to the most recent result set only.

## Acknowledgements

The original idea and the memorable `hmm` function name were inspired by Den Delimarsky's article, [Find a command in PowerShell history](https://den.dev/blog/find-command-history-powershell/).

Thank you to Den Delimarsky for publishing the concise original function that searches the PSReadLine history file and for the `hmm` naming idea. This project expands that concept with deduplication, multiline command reconstruction, pagination, interactive numbered selection, and editable command recall.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).
