#!/usr/bin/env bash
set -euo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$test_dir/../.." && pwd)
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hmm-install-tests.XXXXXX")
trap 'rm -rf -- "$tmp_dir"' EXIT
export HOME="$tmp_dir/home"
export XDG_DATA_HOME="$tmp_dir/data"
export HMM_BASHRC="$HOME/.bashrc"
mkdir -p "$HOME"
printf '# existing configuration\n' > "$HMM_BASHRC"

sh "$repo_dir/install.sh" >/dev/null
sh "$repo_dir/install.sh" >/dev/null
[[ -f "$XDG_DATA_HOME/hmm-history/hmm.bash" ]]
[[ -f "$HMM_BASHRC.hmm-history.bak" ]]
[[ $(grep -c '^# >>> hmm-history >>>$' "$HMM_BASHRC") == 1 ]]
grep -q '^# existing configuration$' "$HMM_BASHRC"

sh "$repo_dir/install.sh" --uninstall >/dev/null
[[ ! -e "$XDG_DATA_HOME/hmm-history/hmm.bash" ]]
[[ $(grep -c '^# >>> hmm-history >>>$' "$HMM_BASHRC" || :) == 0 ]]
grep -q '^# existing configuration$' "$HMM_BASHRC"
printf 'Bash installer tests passed\n'
