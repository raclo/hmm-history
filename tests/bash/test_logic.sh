#!/usr/bin/env bash
set -uo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$test_dir/../.." && pwd)
HMM_NO_AUTO_ENABLE=1
# The path is calculated at runtime so the test also works outside the repo root.
# shellcheck disable=SC1090
source "$repo_dir/hmm.bash"

failures=0
assert_eq() {
    local expected=$1 actual=$2 message=$3
    if [[ $actual != "$expected" ]]; then
        printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' "$message" "$expected" "$actual" >&2
        ((failures++))
    fi
}

entries=(
    'pip old'
    'echo "quoted pip" | cat > output.txt'
    'hmm pip'
    'PIP install new'
    'pip old'
    'printf "Grüße"'
    'printf "literal [bracket"'
    $'printf first\\\nprintf second'
    '  pip old  '
)
results=()
_hmm_search_entries 'pip' 0 entries results
assert_eq '3' "${#results[@]}" 'literal search, exclusion, newest-first deduplication'
assert_eq '  pip old  ' "${results[0]}" 'newest duplicate wins without changing recalled text'
assert_eq 'PIP install new' "${results[1]}" 'case-insensitive matching'
assert_eq 'echo "quoted pip" | cat > output.txt' "${results[2]}" 'middle match with quotes, pipe, and redirect'

_hmm_search_entries 'PIP' 1 entries results
assert_eq '5' "${#results[@]}" 'optional duplicate preservation'
_hmm_search_entries 'not present' 0 entries results
assert_eq '0' "${#results[@]}" 'empty result'
_hmm_search_entries 'Grüße' 0 entries results
assert_eq 'printf "Grüße"' "${results[0]}" 'Unicode'
_hmm_search_entries '[bracket' 0 entries results
assert_eq 'printf "literal [bracket"' "${results[0]}" 'regular-expression characters are literal'
_hmm_search_entries $'first\\\nprintf' 0 entries results
assert_eq $'printf first\\\nprintf second' "${results[0]}" 'multiline literal'

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hmm-tests.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
printf '#1700000000\nprintf first\nprintf second\n#1700000001\necho newest' > "$tmp_dir/timestamped"
parsed=()
_hmm_parse_history_file "$tmp_dir/timestamped" parsed
assert_eq '2' "${#parsed[@]}" 'timestamp records delimit multiline entries'
assert_eq $'printf first\nprintf second' "${parsed[0]}" 'multiline content preserved'
assert_eq 'echo newest' "${parsed[1]}" 'file without final newline'
_hmm_parse_history_file "$tmp_dir/missing" parsed
assert_eq '0' "${#parsed[@]}" 'missing history file'
: > "$tmp_dir/empty"
_hmm_parse_history_file "$tmp_dir/empty" parsed
assert_eq '0' "${#parsed[@]}" 'empty history file'
printf '#1700000000\necho final newline\n' > "$tmp_dir/final-newline"
_hmm_parse_history_file "$tmp_dir/final-newline" parsed
assert_eq 'echo final newline' "${parsed[0]}" 'history file with final newline'

set -o history
history -c
unset HISTFILE
history -s 'printf CURRENT_SESSION_ONLY'
# Used through a nameref in _hmm_history_snapshot.
# shellcheck disable=SC2034
snapshot=()
_hmm_history_snapshot snapshot
_hmm_search_entries CURRENT_SESSION_ONLY 0 snapshot results
assert_eq 'printf CURRENT_SESSION_ONLY' "${results[0]}" 'current session works with HISTFILE unset'
set +o history

HMM_LAST_RESULTS=('one' 'two')
recalled=''
_hmm_recall_number 2 recalled; assert_eq 'two' "$recalled" 'valid direct recall'
if _hmm_recall_number 0 recalled || _hmm_recall_number 3 recalled || _hmm_recall_number x recalled || _hmm_recall_number 9999999999 recalled; then
    printf 'FAIL: invalid direct recall accepted\n' >&2; ((failures++))
fi
assert_eq 'pip install' "$(_hmm_trim_argument '  "pip install"  ')" 'quoted argument trimming'
start=0 end=0 pages=0
_hmm_page_range 16 15 0 start end pages
assert_eq '0' "$start" 'first page start'; assert_eq '15' "$end" 'first page end'; assert_eq '2' "$pages" 'page count'
_hmm_page_range 16 15 1 start end pages
assert_eq '15' "$start" 'last page start'; assert_eq '16' "$end" 'last page boundary'

long=$(printf '%150s' x)
# Used through a nameref in _hmm_search_entries.
# shellcheck disable=SC2034
entries=("prefix $long suffix")
_hmm_search_entries suffix 0 entries results
assert_eq "prefix $long suffix" "${results[0]}" 'long command is not altered in storage'

if ((failures)); then printf '%d Bash logic test(s) failed\n' "$failures" >&2; exit 1; fi
printf 'All Bash logic tests passed\n'
