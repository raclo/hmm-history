#!/usr/bin/env bash
set -uo pipefail

command -v expect >/dev/null 2>&1 || {
    printf 'SKIP: Expect is required for the Bash PTY test\n' >&2
    exit 77
}

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$test_dir/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hmm-pty.XXXXXX") || exit 1
marker=$tmp_dir/executed
history_file=$tmp_dir/history
transcript=$tmp_dir/transcript
bash_rc=$tmp_dir/bashrc
trap 'rm -rf -- "$tmp_dir"' EXIT HUP INT TERM

printf '#1700000000\nprintf EXECUTED > %q\n' "$marker" > "$history_file"
printf "PS1='HMM_PROMPT> '\n" > "$bash_rc"
printf -v source_command 'source %q' "$repo_dir/hmm.bash"

export HMM_TEST_HISTORY_FILE=$history_file
export HMM_TEST_MARKER=$marker
export HMM_TEST_SOURCE_COMMAND=$source_command
export HMM_TEST_TRANSCRIPT=$transcript
export HMM_TEST_BASH_RC=$bash_rc

if ! expect "$test_dir/test_bash.exp"; then
    printf '%s\n' '--- PTY transcript ---' >&2
    sed -n l "$transcript" >&2
    exit 1
fi
printf 'Bash PTY recall test passed\n'
