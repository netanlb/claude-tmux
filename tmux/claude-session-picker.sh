#!/usr/bin/env bash
# Claude-aware tmux session picker.
#   --list   emit one fzf row per session (used by reload after d)
# Default: render the popup.

set -uo pipefail

SELF="${BASH_SOURCE[0]}"

color_dot() {
    case "$1" in
        waiting)  printf '\e[31m●\e[0m' ;;
        thinking) printf '\e[33m●\e[0m' ;;
        idle)     printf '\e[32m●\e[0m' ;;
        *)        printf '\e[2m·\e[0m'  ;;
    esac
}

human_duration() {
    local secs=$1
    if   (( secs < 60 ));    then printf '%ds' "$secs"
    elif (( secs < 3600 ));  then printf '%dm' $(( secs / 60 ))
    elif (( secs < 86400 )); then printf '%dh' $(( secs / 3600 ))
    else                          printf '%dd' $(( secs / 86400 ))
    fi
}

session_status() {
    local name=$1 has_waiting=0 has_thinking=0 has_idle=0 s
    while IFS= read -r s; do
        case "$s" in
            waiting)  has_waiting=1  ;;
            thinking) has_thinking=1 ;;
            idle)     has_idle=1     ;;
        esac
    done < <(tmux list-windows -t "$name" -F '#{@claude_status}' 2>/dev/null)

    if   (( has_waiting ));  then echo waiting
    elif (( has_thinking )); then echo thinking
    elif (( has_idle ));     then echo idle
    else                          echo none
    fi
}

list_rows() {
    local current now name attached status priority
    current=$(tmux display-message -p '#{session_name}')
    now=$(date +%s)

    # Pass 1: collect tuples (priority<TAB>ts<TAB>name<TAB>status) and measure name width.
    # Priority: waiting=0 > thinking=1 > idle=2 > none=3 (lower sorts first).
    local rows=() width=0
    while IFS='|' read -r name attached; do
        [[ -z "$name" ]] && continue
        status=$(session_status "$name")
        case "$status" in
            waiting)  priority=0 ;;
            thinking) priority=1 ;;
            idle)     priority=2 ;;
            *)        priority=3 ;;
        esac
        rows+=("${priority}"$'\t'"${attached:-0}"$'\t'"${name}"$'\t'"${status}")
        (( ${#name} > width )) && width=${#name}
    done < <(tmux list-sessions -F '#{session_name}|#{session_last_attached}')

    # Sort by priority asc, then by attach-timestamp desc (most recent first within tier).
    local sorted
    sorted=$(printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1,1n -k2,2nr)

    # Pass 2: render — dot · marker · NAME(left-padded) · gap · age   |   Search: NAME
    local prio att n s dot marker age
    while IFS=$'\t' read -r prio att n s; do
        dot=$(color_dot "$s")
        marker=' '
        [[ "$n" == "$current" ]] && marker=$'\e[1;35m›\e[0m'

        if [[ -n "$att" && "$att" -gt 0 ]]; then
            age=$(human_duration $(( now - att )))
        else
            age='?'
        fi

        printf '%s %s \e[1m%-*s\e[0m      \e[2m%s\e[0m\t%s\n' \
            "$dot" "$marker" "$width" "$n" "$age" "$n"
    done <<< "$sorted"
}

confirm_kill_session() {
    local sess=$1
    [[ -z "$sess" ]] && return
    printf 'kill %s? [y/N] ' "$sess"
    local a
    read -n 1 -r a
    echo
    if [[ "$a" == "y" || "$a" == "Y" ]]; then
        tmux kill-session -t "$sess"
    fi
}

case "${1:-}" in
    --list)
        list_rows
        ;;
    --kill)
        confirm_kill_session "${2:-}"
        ;;
    --maybe-reload)
        # Emit a reload action only if any window in any session is "thinking".
        # When nothing is thinking, no action is emitted → fzf has no pending
        # background work → no spinner activity.
        if tmux list-windows -aF '#{@claude_status}' 2>/dev/null | grep -q '^thinking$'; then
            echo "reload(sleep 1; bash $SELF --list)"
        fi
        ;;
    *)
        list_rows | fzf \
            --ansi \
            --no-sort \
            --track \
            --info=inline-right \
            --delimiter=$'\t' \
            --with-nth=1 \
            --reverse \
            --height=100% \
            --header='enter switch · esc toggles search/nav · in nav: j/k move · x kill · i search · ctrl-r reload' \
            --bind='start:unbind(j,k,x,i)+change-prompt(search> )' \
            --bind='j:down' \
            --bind='k:up' \
            --bind="x:execute(bash $SELF --kill {2})+reload(bash $SELF --list)" \
            --bind='i:enable-search+change-prompt(search> )+unbind(j,k,x,i)' \
            --bind='change:transform-query:[ "$FZF_PROMPT" = "nav> " ] && echo "" || echo {q}' \
            --bind='esc:transform:[ "$FZF_PROMPT" = "search> " ] && echo "disable-search+change-prompt(nav> )+rebind(j,k,x,i)+clear-query" || echo "abort"' \
            --bind="ctrl-r:reload(bash $SELF --list)" \
            --bind="load:transform:bash $SELF --maybe-reload" \
            | cut -f2- \
            | { read -r target; [[ -n "$target" ]] && tmux switch-client -t "$target"; }
        ;;
esac
