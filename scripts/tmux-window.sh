#!/usr/bin/env bash
set -euo pipefail

# tmux-window — tmux window management for worktree hooks.
# Usage:
#   tmux-window switch <path> <branch>
#   tmux-window remove <path>

action="${1:-}"
worktree_path="${2:-}"
branch_name="${3:-$(basename "$worktree_path")}" 

if [[ -z "$action" || -z "$worktree_path" ]]; then
    echo "Usage: tmux-window {switch|remove} <path> [<branch>]" >&2
    exit 1
fi

if [[ -n "${TMUX:-}" ]]; then
    TMUX_MODE="session"
elif command -v tmux &>/dev/null && tmux list-sessions &>/dev/null 2>&1; then
    TMUX_MODE="global"
else
    exit 0
fi

find_window_in_session() {
    local idx wpath
    while read -r idx wpath; do
        if [[ "$wpath" == "$worktree_path" || "$wpath" == "$worktree_path/"* ]]; then
            echo "$idx"
            return 0
        fi
    done < <(tmux list-panes -s -F '#{window_index} #{pane_current_path}' 2>/dev/null)
}

find_window_global() {
    local target wpath
    while read -r target wpath; do
        if [[ "$wpath" == "$worktree_path" || "$wpath" == "$worktree_path/"* ]]; then
            echo "$target"
            return 0
        fi
    done < <(tmux list-panes -a -F '#{session_name}:#{window_index} #{pane_current_path}' 2>/dev/null)
}

find_session_for_repo() {
    local repo_root
    repo_root="$(git -C "$worktree_path" rev-parse --git-common-dir 2>/dev/null)" || return
    repo_root="${repo_root%/.git}"
    repo_root="$(cd "$worktree_path" 2>/dev/null && cd "$repo_root" 2>/dev/null && pwd)" || return
    [[ -d "$repo_root" ]] || return

    local session wpath
    while read -r session wpath; do
        if [[ "$wpath" == "$repo_root" || "$wpath" == "$repo_root/"* ]]; then
            echo "$session"
            return 0
        fi
    done < <(tmux list-panes -a -F '#{session_name} #{pane_current_path}' 2>/dev/null)
}

case "$action" in
    switch)
        if [[ "$TMUX_MODE" == "session" ]]; then
            window_idx="$(find_window_in_session || true)"
            if [[ -n "$window_idx" ]]; then
                tmux select-window -t "$window_idx"
            else
                tmux new-window -n "$branch_name" -c "$worktree_path"
            fi
        else
            target="$(find_window_global || true)"
            if [[ -n "$target" ]]; then
                tmux select-window -t "$target"
            else
                session="$(find_session_for_repo || true)"
                if [[ -n "$session" ]]; then
                    tmux new-window -t "$session" -n "$branch_name" -c "$worktree_path"
                fi
            fi
        fi
        ;;
    remove)
        if [[ "$TMUX_MODE" == "session" ]]; then
            window_idx="$(find_window_in_session || true)"
            [[ -n "$window_idx" ]] && tmux kill-window -t "$window_idx" || true
        else
            target="$(find_window_global || true)"
            [[ -n "$target" ]] && tmux kill-window -t "$target" || true
        fi
        ;;
    *)
        echo "Unknown action: $action" >&2
        exit 1
        ;;
esac
