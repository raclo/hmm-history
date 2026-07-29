#!/usr/bin/env bash
set -uo pipefail

if [[ $- != *i* || ! -t 0 ]]; then
    command -v script >/dev/null 2>&1 || {
        printf 'test_bindings.sh requires util-linux script(1)\n' >&2
        exit 1
    }
    printf -v self_path '%q' "${BASH_SOURCE[0]}"
    # The child interactive shell, not this wrapper, expands the status values.
    # shellcheck disable=SC2016
    printf 'source %s; test_status=$?; exit $test_status\r' "$self_path" |
        script -qefc "env PS1='HMM_BINDING_TEST> ' bash --noprofile --norc -i" /dev/null
    exit $?
fi

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$test_dir/../.." && pwd)
HMM_NO_AUTO_ENABLE=1
# shellcheck disable=SC1090
source "$repo_dir/hmm.bash"

failures=0
assert_contains() {
    local haystack=$1 needle=$2 message=$3
    if [[ $haystack != *"$needle"* ]]; then
        printf 'FAIL: %s\n  expected to contain: %s\n  actual: %s\n' "$message" "$needle" "$haystack" >&2
        ((failures++))
    fi
}

bind -x '"\C-m":printf enter-probe >/dev/null'
bind -x '"\C-x\C-]":printf dispatch-probe >/dev/null'
bind '"\C-x\C-^":"accept-probe"'

if hmm_enable 2>/dev/null; then
    printf 'FAIL: custom Enter bind -x handler was replaced without opt-in\n' >&2
    ((failures++))
fi

HMM_FORCE_BINDING=1
hmm_enable
hmm_disable

enter_binding=$(bind -X 2>/dev/null | grep -F '"\C-m":' || :)
dispatch_binding=$(bind -X 2>/dev/null | grep -F '"\C-x\C-]":' || :)
accept_binding=$(bind -s 2>/dev/null | grep -F '"\C-x\C-^":' || :)
assert_contains "$enter_binding" 'enter-probe' 'Enter bind -x restoration'
assert_contains "$dispatch_binding" 'dispatch-probe' 'private bind -x restoration'
assert_contains "$accept_binding" 'accept-probe' 'private macro restoration'

if ((failures)); then
    printf '%d Bash binding test(s) failed\n' "$failures" >&2
    exit 1
fi
printf 'All Bash binding tests passed\n'
