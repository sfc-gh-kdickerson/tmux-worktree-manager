#!/usr/bin/env bash

set -euo pipefail

msg() {
    local txt="$1"
    if [[ -n "${TMUX:-}" ]]; then
        tmux display-message "$txt" 2>/dev/null || true
    else
        printf '%s\n' "$txt" >&2
    fi
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

ensure_cmd() {
    local bin="$1"
    local why="$2"
    if ! has_cmd "$bin"; then
        msg "tmux-worktree-manager: missing '$bin' (${why})"
        return 1
    fi
    return 0
}
