#!/bin/sh
set -eu

source_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
source_file=$source_dir/hmm.bash
data_home=${XDG_DATA_HOME:-"$HOME/.local/share"}
install_dir=$data_home/hmm-history
target_file=$install_dir/hmm.bash
bashrc=${HMM_BASHRC:-"$HOME/.bashrc"}
start_marker='# >>> hmm-history >>>'
end_marker='# <<< hmm-history <<<'

remove_block() {
    input=$1 output=$2
    awk -v start="$start_marker" -v end="$end_marker" '
        $0 == start { skipping=1; next }
        $0 == end { skipping=0; next }
        !skipping { print }
    ' "$input" > "$output"
}

tmp_file=$(mktemp "${TMPDIR:-/tmp}/hmm-install.XXXXXX")
trap 'rm -f -- "$tmp_file"' EXIT HUP INT TERM

if [ "${1:-}" = '--uninstall' ]; then
    if [ -f "$bashrc" ]; then
        cp -p -- "$bashrc" "$bashrc.hmm-history.bak"
        remove_block "$bashrc" "$tmp_file"
        cp -- "$tmp_file" "$bashrc"
    fi
    rm -f -- "$target_file"
    rmdir -- "$install_dir" 2>/dev/null || :
    printf '%s\n' 'hmm-history removed. Start a new Bash session or run hmm_disable in this one.'
    exit 0
fi

[ -f "$source_file" ] || { printf 'hmm.bash not found: %s\n' "$source_file" >&2; exit 1; }
mkdir -p -- "$install_dir"
cp -- "$source_file" "$target_file"
if [ -f "$bashrc" ]; then
    cp -p -- "$bashrc" "$bashrc.hmm-history.bak"
else
    : > "$bashrc"
fi
remove_block "$bashrc" "$tmp_file"
cp -- "$tmp_file" "$bashrc"
cat >> "$bashrc" <<'EOF'
# >>> hmm-history >>>
if [ -r "${XDG_DATA_HOME:-$HOME/.local/share}/hmm-history/hmm.bash" ]; then
    . "${XDG_DATA_HOME:-$HOME/.local/share}/hmm-history/hmm.bash"
fi
# <<< hmm-history <<<
EOF

printf 'hmm-history installed: %s\n' "$target_file"
printf 'Backup: %s\n' "$bashrc.hmm-history.bak"
printf '%s\n' 'Start a new Bash session, or source the installed file now.'
printf '%s\n' 'Uninstall with: ./install.sh --uninstall'
