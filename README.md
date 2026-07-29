# hmm-history

`hmm-history` is a local, numbered history search and editable recall tool for PowerShell and Bash. It has two native implementations:

- `hmm.ps1` uses PowerShell 7, PSReadLine, and the PSReadLine editing buffer.
- `hmm.bash` uses Bash, GNU Readline, `bind -x`, `READLINE_LINE`, and `READLINE_POINT`.

Selecting a command places it in the current prompt without executing it. Review or edit it, then press Enter a second time to run it.

## Features

| Feature | PowerShell | Bash |
|---|---:|---:|
| Literal, case-insensitive substring search | Yes | Yes |
| Newest-first results and default deduplication | Yes | Yes |
| Numbered pagination and direct recall | Yes | Yes |
| Multiline preview without changing recalled text | Yes | Yes¹ |
| Editable recall without execution | PSReadLine buffer | GNU Readline buffer |
| Runtime add-ons | PSReadLine only | Standard distribution utilities only |

¹ Timestamp-delimited Bash history preserves multiline entries. An old history file with `lithist` content but no timestamp records is inherently ambiguous and is treated as one entry per physical line.

## Requirements and platform status

PowerShell requires PowerShell 7 or later, PSReadLine, and an interactive console host. It is intended for Windows, Linux, and macOS.

Bash requires Bash 4.4 or later built with GNU Readline, an interactive TTY session, and standard utilities normally present on supported distributions (`mktemp` and `rm`; the installer also uses `awk` and `cp`). The Bash 3.2 shipped by default on many macOS releases is unsupported; install a current Bash before using `hmm.bash` there.

“Tested” means the automated job or a documented manual test actually completed. “Expected” means the implementation is designed for the platform but has not yet produced test evidence in this checkout. The CI results below refer to GitHub Actions run `30455806726`.

| Platform | Implementation | Status in this checkout |
|---|---|---|
| Windows, PowerShell 7.6.4 / PSReadLine 2.4.5 | PowerShell | Deterministic tests and manual editable recall without execution passed locally |
| Debian 13 under WSL2, Bash 5.2.37 | Bash | ShellCheck 0.10.0, syntax, logic, installer, binding restoration, and real `script`/Expect PTY tests passed locally |
| Windows, Git for Windows Bash 5.2.37 | Bash | Syntax, logic, and installer checks passed locally; this is not a supported Linux/TTY result |
| `windows-latest`, `ubuntu-latest`, `macos-latest` | PowerShell | CI parser and deterministic tests passed |
| Debian 12, Debian 13 | Bash | CI ShellCheck, deterministic tests, binding restoration, recall PTY, and Expect Ctrl+C tests passed |
| Ubuntu 22.04, 24.04, 26.04 | Bash | CI ShellCheck, deterministic tests, binding restoration, recall PTY, and Expect Ctrl+C tests passed |
| Fedora 42, 43, 44 | Bash | CI ShellCheck, deterministic tests, binding restoration, recall PTY, and Expect Ctrl+C tests passed |
| AlmaLinux 9 | Bash | CI ShellCheck, deterministic tests, binding restoration, recall PTY, and Expect Ctrl+C tests passed |
| AlmaLinux 8 | Bash | CI ShellCheck, deterministic tests, binding restoration, and recall PTY passed; the Expect Ctrl+C subtest was explicitly skipped because its older PTY stack does not forward the control byte reliably |
| macOS system Bash 3.2 | Bash | Unsupported |
| Non-interactive shells or hosts without an editing TTY | Both | Unsupported for selection/recall |

Update this table only after checking the corresponding CI run. Container tags remain explicit in `.github/workflows/ci.yml`; an unavailable image must fail visibly rather than being silently substituted.

## PowerShell installation

From a PowerShell 7 prompt in the repository:

```powershell
./install.ps1
. $PROFILE
```

The installer copies `hmm.ps1` to `$HOME/.hmm-history/hmm.ps1` and adds a guarded, managed block to `$PROFILE.CurrentUserCurrentHost`. It creates missing directories and is safe to rerun as an update. A different per-user directory may be selected:

```powershell
./install.ps1 -InstallDirectory (Join-Path $HOME 'Tools/hmm-history')
```

Uninstall the default location and managed profile block with:

```powershell
./install.ps1 -Uninstall
```

Restart PowerShell afterward. In the current session, `Disable-Hmm` restores Enter to PSReadLine's `AcceptLine` behavior.

For manual installation, dot-source `hmm.ps1` from the active profile. Do not copy examples containing machine-specific absolute paths into documentation or issue reports.

## Bash installation

From the repository in Bash:

```bash
sh ./install.sh
```

The installer copies `hmm.bash` to `${XDG_DATA_HOME:-$HOME/.local/share}/hmm-history/hmm.bash`, backs up an existing `~/.bashrc` as `~/.bashrc.hmm-history.bak`, and adds a guarded source block. It never edits system-wide startup files and is safe to rerun.

Start a new Bash session or source the installed file. To uninstall:

```bash
sh ./install.sh --uninstall
```

The uninstaller also backs up `.bashrc`. Run `hmm_disable` first if you want to remove the bindings from the current shell immediately.

Manual installation is simply:

```bash
source /path/to/hmm.bash
```

## Usage

The public syntax is the same in either shell:

```text
hmm pip
hmm 9
```

`hmm pip` searches persistent history for literal `pip` anywhere in each command, ignoring case. Results are newest-first, `hmm` invocations are omitted, and case-insensitive duplicate commands are removed by default. A selection number refers to the complete result set and remains stable until the next search.

```text
hmm: "pip" - 18 results - page 1/2

[ 1] python -m pip list --outdated
[ 2] pip install passlib[bcrypt]
[ 3] printf 'first line'  <line>  printf 'second line'

Number = recall, Enter = next, P = previous, Q = quit:
```

Controls:

| Input | Action |
|---|---|
| A result number + Enter | Recall that result without executing it |
| Enter | Next page; close on the final page |
| `P` | Previous page |
| `Q` or Escape | Quit to an empty prompt |
| Ctrl+C | Cancel cleanly |
| Backspace | Edit a partially typed number |

After a search, `hmm 9` recalls result 9 directly. Invalid numbers leave a clean, empty prompt and display the valid range.

## Configuration

Set configuration before sourcing the implementation, or change it afterward.

| Behavior | PowerShell | Bash | Default |
|---|---|---|---:|
| Results per page | `$global:HmmPageSize` | `HMM_PAGE_SIZE` | 15 |
| Preserve duplicates | `$global:HmmKeepDuplicates` | `HMM_KEEP_DUPLICATES` | false / 0 |
| Disable preview truncation | `$global:HmmShowFullCommands` | `HMM_SHOW_FULL_COMMANDS` | false / 0 |

For Bash, set `HMM_NO_AUTO_ENABLE=1` before sourcing to load the functions without changing Enter. Run `hmm_enable` later. If Enter already has a `bind -x` handler, `hmm_enable` warns and declines to replace it; explicitly set `HMM_FORCE_BINDING=1` before enabling if replacement is intentional.

For PowerShell, `Enable-Hmm` declines to replace a nonstandard Enter binding because PSReadLine does not expose enough information to restore an arbitrary custom script block safely. Disable the competing handler explicitly before enabling `hmm`. `Disable-Hmm` returns Enter to `AcceptLine`.

## History behavior

PowerShell reads the path reported by `(Get-PSReadLineOption).HistorySavePath` and reconstructs PSReadLine continuation records.

Bash safely runs `history -a` and `history -n` when `HISTFILE` is set, then asks the Bash `history` builtin to write a private temporary snapshot. This includes current-session entries that have not yet been persisted and newly appended entries from concurrent shells. The original history file is not rewritten by `hmm`. `HISTCONTROL` and `HISTIGNORE` remain Bash's responsibility; commands Bash chose not to retain cannot be searched. An unset, disabled, missing, empty, or unreadable `HISTFILE` does not prevent searching the current in-memory session.

History entries are never passed to `eval`, printed as a substitute for recall, or executed during selection.

## Key bindings and known conflicts

Both implementations intercept Enter only when the complete editable line is an `hmm` invocation with optional surrounding whitespace. Other lines follow normal `accept-line` behavior.

The Bash implementation changes `Ctrl+M` (the sequence normally sent by Enter) and uses private helper chords `Ctrl+X Ctrl+]` and `Ctrl+X Ctrl+^`. It does not replace `Ctrl+J`. Existing `bind -x` Enter handlers are detected. Tools such as fzf, Atuin, HSTR, McFly, custom `.inputrc` rules, or profile scripts may install competing Enter/history bindings; load only one handler, adjust load order deliberately, or leave auto-enable off. `hmm_disable` restores captured shell-command, macro, and named Readline-function bindings; `HMM_FORCE_BINDING=1` is therefore an explicit Bash-only opt-in.

PowerShell profile tools that replace the PSReadLine Enter handler have the same conflict. Load order determines the active binding.

Prompt redraw varies between terminal hosts. PowerShell keeps the explicit `PSConsoleReadLine.InvokePrompt` row anchor and falls back when cursor APIs are unavailable. Bash emits a fresh line from its Readline handler before selection. If output appears above the list or overwrites it, verify a real interactive TTY, disable competing Enter handlers, and try a current terminal plus current PSReadLine/Bash. Report the OS, terminal, shell version, Readline/PSReadLine version, and relevant bindings.

## Tests

Run deterministic tests:

```bash
bash tests/bash/test_logic.sh
bash tests/bash/test_install.sh
bash tests/bash/test_bindings.sh
shellcheck hmm.bash install.sh tests/bash/test_logic.sh tests/bash/test_install.sh tests/bash/test_bindings.sh tests/interactive/test_bash.sh
bash tests/interactive/test_bash.sh
```

```powershell
./tests/powershell/Test-Hmm.ps1
./tests/powershell/Test-Install.ps1
```

The interactive test uses util-linux `script(1)` and Expect to start Bash under real pseudo-terminals. The `script(1)` session recalls a command that creates a marker file, proves the file does not exist while the command is only in the editing buffer, edits the buffer, then executes it. Its transcript also verifies that the recalled prompt is below the selector and exercises `Q`, Escape, and ordinary Enter behavior. Expect separately sends Ctrl+C and proves that a clean command executes afterward. Missing development tools exit with status 77 and are never reported as a pass. The Expect Ctrl+C subtest is explicitly skipped on AlmaLinux 8; its full recall PTY test still runs and passes.

The CI workflow defines all distribution and OS jobs listed in the status table, prints Bash versions, asserts Bash 4.4+, runs ShellCheck and deterministic tests, and runs the Bash PTY test. PowerShell jobs perform parser and deterministic tests on all three practical GitHub-hosted operating systems.

## Privacy and security

All processing is local. Shell history can contain passwords or tokens; `hmm` does not redact matches, so review output before sharing screenshots or logs. Recall never executes a selection, but pressing Enter afterward uses the shell's ordinary execution behavior.

## Acknowledgements

`hmm-history` is an independent implementation inspired by the original idea and memorable `hmm` function name in Den Delimarsky's article, [Find a command in PowerShell history](https://den.dev/blog/find-command-history-powershell/). It expands the concept with deduplication, multiline handling, pagination, native Bash support, interactive numbered selection, and editable recall.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).
