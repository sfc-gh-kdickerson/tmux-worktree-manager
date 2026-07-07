#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/options.sh"

WT_CMD="$(opt_get '@tmux-worktree-manager-wt-command' 'wt')"

action="${1:-}"

case "$action" in
    list)
        cur_path=""
        while IFS= read -r line; do
            case "$line" in
                "worktree "*)          cur_path="${line#worktree }" ;;
                "branch refs/heads/"*) echo "${line#branch refs/heads/}"$'\t'"$cur_path" ;;
                "")                    cur_path="" ;;
            esac
        done < <(git worktree list --porcelain 2>/dev/null)
        ;;
    switch)
        branch="${2:-}"
        [[ -n "$branch" ]] || exit 1
        command "$WT_CMD" switch --no-cd --yes "$branch"
        ;;
    create)
        branch="${2:-}"
        base="${3:-}"
        [[ -n "$branch" && -n "$base" ]] || exit 1
        command "$WT_CMD" switch --create --base "$base" --no-cd --yes "$branch"
        ;;
    remove)
        branch="${2:-}"
        force="${3:-}"
        [[ -n "$branch" ]] || exit 1
        if [[ "$force" == "--force" ]]; then
            command "$WT_CMD" remove --force --yes "$branch"
        else
            command "$WT_CMD" remove --yes "$branch"
        fi
        ;;
    *)
        exit 1
        ;;
esac
