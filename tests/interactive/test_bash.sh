#!/usr/bin/env bash
set -uo pipefail

command -v script >/dev/null 2>&1 || {
    printf 'SKIP: util-linux script(1) is required for the Bash PTY test\n' >&2
    exit 77
}

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$test_dir/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hmm-pty.XXXXXX") || exit 1
marker=$tmp_dir/executed
early_marker=$tmp_dir/executed-too-early
history_file=$tmp_dir/history
typescript=$tmp_dir/typescript
clean_transcript=$tmp_dir/typescript.clean
trap 'rm -rf -- "$tmp_dir"' EXIT HUP INT TERM

printf '#1700000000\nprintf EXECUTED > %q\n' "$marker" > "$history_file"
printf -v source_command 'source %q' "$repo_dir/hmm.bash"
printf -v history_argument '%q' "$history_file"
shell_command="env HISTFILE=$history_argument PS1='HMM_PROMPT> ' HMM_PAGE_SIZE=5 bash --noprofile --norc -i"

{
    sleep 0.3
    printf '%s\r' "$source_command"
    sleep 0.3
    printf 'hmm EXECUTED\r'
    sleep 0.5
    printf '1\r'
    sleep 0.5
    [[ ! -e $marker ]] || : > "$early_marker"
    printf ' && printf EDITED >> %q\r' "$marker"
    sleep 0.5

    printf 'hmm EXECUTED\r'
    sleep 0.5
    printf 'q'
    sleep 0.5

    printf 'hmm EXECUTED\r'
    sleep 0.5
    printf '\033'
    sleep 0.5

    printf 'hmm EXECUTED\r'
    sleep 0.5
    printf '\003'
    sleep 0.5

    printf 'printf NORMAL_ENTER\r'
    sleep 0.5
    printf 'exit\r'
} | script -qefc "$shell_command" "$typescript"
pipeline_status=$?

((pipeline_status == 0)) || {
    printf 'Bash PTY session exited with status %d\n' "$pipeline_status" >&2
    exit 1
}
[[ ! -e $early_marker ]] || {
    printf 'Selected command executed during recall\n' >&2
    exit 1
}
[[ -e $marker ]] || {
    printf 'Edited recalled command did not execute after the second Enter\n' >&2
    exit 1
}
[[ $(<"$marker") == EXECUTEDEDITED ]] || {
    printf 'Recalled command was not edited in the real Readline buffer\n' >&2
    exit 1
}

# Remove common CSI sequences and carriage returns so ordering assertions are
# independent of terminal cursor-control details.
LC_ALL=C sed -E $'s/\033\\[[0-9;?]*[A-Za-z]//g' "$typescript" | tr -d '\r' > "$clean_transcript"
selector_line=$(grep -n -m1 'Number = recall' "$clean_transcript" | cut -d: -f1)
recall_line=$(grep -n -m1 'HMM_PROMPT> printf EXECUTED >' "$clean_transcript" | cut -d: -f1)
[[ -n $selector_line && -n $recall_line && $recall_line -gt $selector_line ]] || {
    printf 'The recalled prompt was not rendered below the selector\n' >&2
    exit 1
}
grep -q 'Number = recall.*q' "$clean_transcript" || {
    printf 'Q did not close the selector cleanly\n' >&2
    exit 1
}
grep -q 'NORMAL_ENTER' "$clean_transcript" || {
    printf 'Normal Enter behavior was not preserved after Q, Escape, and Ctrl+C\n' >&2
    exit 1
}

printf 'Bash PTY recall test passed\n'
