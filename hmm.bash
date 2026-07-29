#!/usr/bin/env bash
# hmm-history for Bash 4.4+ and GNU Readline. Source this file from an
# interactive Bash session; do not execute it as a program.

if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4))); then
    printf 'hmm: Bash 4.4 or later is required\n' >&2
    if [[ ${BASH_SOURCE[0]} != "$0" ]]; then
        return 1
    fi
    exit 1
fi

: "${HMM_PAGE_SIZE:=15}"
: "${HMM_KEEP_DUPLICATES:=0}"
: "${HMM_SHOW_FULL_COMMANDS:=0}"
if [[ ! $HMM_PAGE_SIZE =~ ^[0-9]+$ ]] || ((HMM_PAGE_SIZE < 1)); then
    printf 'hmm: invalid HMM_PAGE_SIZE; using 15\n' >&2
    HMM_PAGE_SIZE=15
fi
declare -ag HMM_LAST_RESULTS=()
# Public state retained for diagnostics and future UI extensions.
# shellcheck disable=SC2034
declare -g HMM_LAST_SEARCH=''
declare -g _HMM_BINDING_ENABLED=0
declare -g _HMM_SAVED_ENTER_BINDING=''
declare -g _HMM_SAVED_ENTER_KIND='none'
declare -g _HMM_SAVED_DISPATCH_BINDING=''
declare -g _HMM_SAVED_DISPATCH_KIND='none'
declare -g _HMM_SAVED_ACCEPT_BINDING=''
declare -g _HMM_SAVED_ACCEPT_KIND='none'

_hmm_parse_history_file() {
    local path=$1 output_name=$2 line entry='' timestamped=0
    local -a lines=() collected=()
    [[ -r $path ]] || { local -n output_ref=$output_name; output_ref=(); return 0; }
    mapfile -t lines < "$path" || return 0
    for line in "${lines[@]}"; do
        if [[ $line =~ ^#[0-9]{10,}$ ]]; then timestamped=1; break; fi
    done
    if ((timestamped)); then
        for line in "${lines[@]}"; do
            if [[ $line =~ ^#[0-9]{10,}$ ]]; then
                [[ -n $entry ]] && collected+=("$entry")
                entry=''
            elif [[ -z $entry ]]; then
                entry=$line
            else
                entry+=$'\n'$line
            fi
        done
        [[ -n $entry ]] && collected+=("$entry")
    else
        # Without timestamp delimiters Bash's file format has no portable way
        # to distinguish lithist continuations, so each physical line is an entry.
        for line in "${lines[@]}"; do [[ -n $line ]] && collected+=("$line"); done
    fi
    # The caller deliberately passes an array name.
    # shellcheck disable=SC2178
    local -n output_ref=$output_name
    output_ref=("${collected[@]}")
}

_hmm_history_snapshot() {
    local output_name=$1 snapshot_path
    # The caller deliberately passes an array name.
    # shellcheck disable=SC2178
    local -n output_ref=$output_name
    output_ref=()
    snapshot_path=$(mktemp "${TMPDIR:-/tmp}/hmm-history.XXXXXX") || {
        printf 'hmm: could not create a history snapshot\n' >&2
        return 1
    }
    # Publish this shell's new entries, then import entries appended by peers.
    # HISTCONTROL/HISTIGNORE have already been applied by Bash itself.
    if [[ -n ${HISTFILE-} ]]; then
        builtin history -a 2>/dev/null || :
        builtin history -n 2>/dev/null || :
    fi
    builtin history -w "$snapshot_path" 2>/dev/null || {
        rm -f -- "$snapshot_path"
        return 0
    }
    _hmm_parse_history_file "$snapshot_path" "$output_name"
    rm -f -- "$snapshot_path"
}

_hmm_search_entries() {
    local query=$1 keep=$2 input_name=$3 output_name=$4 command key
    # The caller deliberately passes array names.
    # shellcheck disable=SC2178
    local -n input_ref=$input_name output_ref=$output_name
    local -A seen=()
    output_ref=()
    local query_fold=${query,,}
    local i
    for ((i=${#input_ref[@]}-1; i>=0; i--)); do
        command=${input_ref[i]}
        [[ -n ${command//[[:space:]]/} ]] || continue
        [[ $command =~ ^[[:space:]]*hmm([[:space:]]|$) ]] && continue
        [[ ${command,,} == *"$query_fold"* ]] || continue
        # Ignore surrounding whitespace for duplicate comparison while
        # preserving the original newest command for recall.
        key=$command
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        key=${key,,}
        if ((keep)) || [[ ! -v 'seen[$key]' ]]; then
            output_ref+=("$command")
            seen["$key"]=1
        fi
    done
}

_hmm_find_history() {
    local query=$1 output_name=$2
    # Used through a nameref in the called functions.
    # shellcheck disable=SC2034
    local -a entries=()
    _hmm_history_snapshot entries || return
    _hmm_search_entries "$query" "$HMM_KEEP_DUPLICATES" entries "$output_name"
}

_hmm_recall_number() {
    local value=$1 output_name=$2
    [[ $value =~ ^[0-9]+$ && ${#value} -le 9 ]] || return 1
    local number=$((10#$value))
    ((number >= 1 && number <= ${#HMM_LAST_RESULTS[@]})) || return 1
    # The caller deliberately passes a scalar name.
    # shellcheck disable=SC2178
    local -n output_ref=$output_name
    # shellcheck disable=SC2178
    output_ref=${HMM_LAST_RESULTS[number-1]}
}

_hmm_page_range() {
    local count=$1 size=$2 page=$3 start_name=$4 end_name=$5 pages_name=$6
    local -n start_ref=$start_name end_ref=$end_name pages_ref=$pages_name
    # All three namerefs are outputs consumed by the caller.
    # shellcheck disable=SC2034
    pages_ref=$(((count + size - 1) / size))
    start_ref=$((page * size)); ((start_ref > count)) && start_ref=$count
    end_ref=$((start_ref + size)); ((end_ref > count)) && end_ref=$count
}

_hmm_terminal_width() {
    local columns=${COLUMNS:-0}
    if ((columns <= 0)) && command -v tput >/dev/null 2>&1; then
        columns=$(tput cols 2>/dev/null) || columns=120
    fi
    ((columns > 0)) || columns=120
    printf '%s' "$columns"
}

_hmm_show_page() {
    local query=$1 page=$2 total=${#HMM_LAST_RESULTS[@]}
    local pages=$(((total + HMM_PAGE_SIZE - 1) / HMM_PAGE_SIZE))
    local start=$((page * HMM_PAGE_SIZE)) end
    end=$((start + HMM_PAGE_SIZE))
    ((end > total)) && end=$total
    local width number_width=${#total} preview_width i preview number
    width=$(_hmm_terminal_width)
    preview_width=$((width - number_width - 5))
    ((preview_width >= 10)) || preview_width=10
    printf '\nhmm: "%s" - %d results - page %d/%d\n\n' "$query" "$total" "$((page + 1))" "$pages"
    for ((i=start; i<end; i++)); do
        number=$((i + 1))
        preview=${HMM_LAST_RESULTS[i]//$'\r\n'/'  <line>  '}
        preview=${preview//$'\n'/'  <line>  '}
        preview=${preview//$'\r'/'  <line>  '}
        if ((HMM_SHOW_FULL_COMMANDS == 0 && ${#preview} > preview_width)); then
            preview=${preview:0:preview_width-1}'…'
        fi
        printf '[%*d] %s\n' "$number_width" "$number" "$preview"
    done
}

_hmm_read_key() {
    IFS= read -rsn1 HMM_KEY </dev/tty || return 1
    [[ -n $HMM_KEY ]] || HMM_KEY=$'\n'
}

_hmm_select() {
    local query=$1 total=${#HMM_LAST_RESULTS[@]} page=0 digits='' key number
    local pages=$(((total + HMM_PAGE_SIZE - 1) / HMM_PAGE_SIZE))
    while :; do
        _hmm_show_page "$query" "$page" >/dev/tty
        printf '\nNumber = recall, Enter = %s, P = previous, Q = quit: ' \
            "$([[ $page -lt $((pages - 1)) ]] && printf next || printf close)" >/dev/tty
        digits=''
        while :; do
            _hmm_read_key || { printf '\n' >/dev/tty; return 1; }
            key=$HMM_KEY
            case $key in
                $'\003') printf '^C\n' >/dev/tty; return 1 ;;
                $'\033') printf '\n' >/dev/tty; return 1 ;;
                $'\177'|$'\b')
                    if [[ -n $digits ]]; then digits=${digits%?}; printf '\b \b' >/dev/tty; fi ;;
                $'\n')
                    printf '\n' >/dev/tty
                    if [[ -n $digits ]]; then
                        if ((${#digits} <= 9)); then number=$((10#$digits)); else number=0; fi
                        if ((number >= 1 && number <= total)); then
                            HMM_SELECTED=${HMM_LAST_RESULTS[number-1]}
                            return 0
                        fi
                        printf 'Invalid number. Choose a value from 1 to %d.\n' "$total" >/dev/tty
                        break
                    fi
                    if ((page < pages - 1)); then ((page++)); break; fi
                    return 1 ;;
                [0-9]) digits+=$key; printf '%s' "$key" >/dev/tty ;;
                [qQ]) if [[ -z $digits ]]; then printf '%s\n' "$key" >/dev/tty; return 1; fi ;;
                [pP])
                    if [[ -z $digits ]]; then
                        printf '%s\n' "$key" >/dev/tty
                        if ((page > 0)); then ((page--)); else printf 'Already on the first page.\n' >/dev/tty; fi
                        break
                    fi ;;
            esac
        done
    done
}

_hmm_trim_argument() {
    local value=$1
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    if ((${#value} >= 2)) && { [[ $value == \"*\" ]] || [[ $value == \'*\' ]]; }; then
        value=${value:1:${#value}-2}
    fi
    printf '%s' "$value"
}

_hmm_skip_accept() {
    # This is the second half of the Enter macro. A handled hmm invocation
    # replaces the private accept chord for exactly one key sequence.
    bind '"\C-x\C-^": accept-line'
}

_hmm_enter_dispatch() {
    local line=$READLINE_LINE argument
    if [[ ! $line =~ ^[[:space:]]*hmm([[:space:]]+(.*))?[[:space:]]*$ ]]; then
        return 0
    fi
    # Prevent the Enter macro's final private accept-line chord from submitting
    # the command placed into READLINE_LINE.
    bind -x '"\C-x\C-^":_hmm_skip_accept'
    argument=$(_hmm_trim_argument "${BASH_REMATCH[2]-}")
    READLINE_LINE=''
    READLINE_POINT=0
    printf '\r\033[K\n' >/dev/tty

    if [[ -z $argument ]]; then
        printf 'Usage: hmm <search text>\n' >/dev/tty
        return 0
    fi
    if [[ $argument =~ ^[0-9]+$ ]]; then
        if _hmm_recall_number "$argument" READLINE_LINE; then
            READLINE_POINT=${#READLINE_LINE}
        elif ((${#HMM_LAST_RESULTS[@]} == 0)); then
            printf 'No hmm search has been run yet.\n' >/dev/tty
        else
            printf 'Invalid number. Available results: 1-%d.\n' "${#HMM_LAST_RESULTS[@]}" >/dev/tty
        fi
        return 0
    fi

    # Public state retained for diagnostics and future UI extensions.
    # shellcheck disable=SC2034
    HMM_LAST_SEARCH=$argument
    _hmm_find_history "$argument" HMM_LAST_RESULTS
    if ((${#HMM_LAST_RESULTS[@]} == 0)); then
        printf 'No results for: "%s"\n' "$argument" >/dev/tty
        return 0
    fi
    local HMM_SELECTED=''
    if _hmm_select "$argument"; then
        READLINE_LINE=$HMM_SELECTED
        READLINE_POINT=${#READLINE_LINE}
    fi
}

_hmm_capture_binding() {
    local sequence=$1 value_name=$2 kind_name=$3 line
    # The caller deliberately passes scalar names.
    # shellcheck disable=SC2178
    local -n value_ref=$value_name kind_ref=$kind_name
    value_ref=''
    kind_ref='none'
    while IFS= read -r line; do
        if [[ $line == "\"${sequence}\":"* || $line == "\"${sequence}\" "* ]]; then
            value_ref=$line
            kind_ref='shell'
            return
        fi
    done < <(bind -X 2>/dev/null)
    while IFS= read -r line; do
        if [[ $line == "\"${sequence}\":"* || $line == "\"${sequence}\" "* ]]; then
            value_ref=$line
            kind_ref='readline'
            return
        fi
    done < <(bind -s 2>/dev/null)
    while IFS= read -r line; do
        if [[ $line == "\"${sequence}\":"* || $line == "\"${sequence}\" "* ]]; then
            # Output is returned through namerefs.
            # shellcheck disable=SC2034
            value_ref=$line
            # shellcheck disable=SC2034
            kind_ref='readline'
            return
        fi
    done < <(bind -p 2>/dev/null)
}

_hmm_restore_binding() {
    local sequence=$1 kind=$2 value=$3
    case $kind in
        shell) bind -x "$value" ;;
        readline) bind "$value" ;;
        *) bind -r "$sequence" 2>/dev/null || : ;;
    esac
}

hmm_enable() {
    [[ $- == *i* ]] || { printf 'hmm: key binding requires an interactive Bash session\n' >&2; return 1; }
    ((_HMM_BINDING_ENABLED)) && return 0
    _hmm_capture_binding '\C-m' _HMM_SAVED_ENTER_BINDING _HMM_SAVED_ENTER_KIND
    if [[ $_HMM_SAVED_ENTER_KIND == shell && ${HMM_FORCE_BINDING:-0} != 1 ]]; then
        printf 'hmm: Enter already has a bind -x handler; set HMM_FORCE_BINDING=1 and run hmm_enable to replace it\n' >&2
        return 1
    fi
    if [[ $_HMM_SAVED_ENTER_KIND == readline && $_HMM_SAVED_ENTER_BINDING != '"\C-m": accept-line' && ${HMM_FORCE_BINDING:-0} != 1 ]]; then
        printf 'hmm: Enter already has a custom Readline binding; set HMM_FORCE_BINDING=1 and run hmm_enable to replace it\n' >&2
        return 1
    fi
    _hmm_capture_binding '\C-x\C-]' _HMM_SAVED_DISPATCH_BINDING _HMM_SAVED_DISPATCH_KIND
    _hmm_capture_binding '\C-x\C-^' _HMM_SAVED_ACCEPT_BINDING _HMM_SAVED_ACCEPT_KIND
    bind -x '"\C-x\C-]":_hmm_enter_dispatch'
    bind '"\C-x\C-^": accept-line'
    # Enter expands to dispatch followed by a private accept-line chord. The
    # dispatcher suppresses that second chord only for exact hmm invocations.
    bind '"\C-m":"\C-x\C-]\C-x\C-^"'
    _HMM_BINDING_ENABLED=1
}

hmm_disable() {
    ((_HMM_BINDING_ENABLED)) || return 0
    _hmm_restore_binding '\C-m' "$_HMM_SAVED_ENTER_KIND" "$_HMM_SAVED_ENTER_BINDING"
    _hmm_restore_binding '\C-x\C-]' "$_HMM_SAVED_DISPATCH_KIND" "$_HMM_SAVED_DISPATCH_BINDING"
    _hmm_restore_binding '\C-x\C-^' "$_HMM_SAVED_ACCEPT_KIND" "$_HMM_SAVED_ACCEPT_BINDING"
    _HMM_BINDING_ENABLED=0
}

hmm() {
    printf 'hmm: type hmm <search text> as the only command on an interactive input line\n' >&2
    return 2
}

if [[ ${HMM_NO_AUTO_ENABLE:-0} != 1 && $- == *i* ]]; then hmm_enable; fi
