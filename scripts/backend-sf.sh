#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/options.sh"

SF_CMD="$(opt_get '@tmux-worktree-manager-sf-command' 'sf')"

action="${1:-}"

case "$action" in
    list)
        # Emit one "name<TAB>path" row per sf workspace. Path is the repo that
        # matches the current repo (or the first repo), falling back to the root.
        #
        # Scope (@tmux-worktree-manager-sf-scope):
        #   repo (default) — only workspaces that contain the current repo
        #   all            — every sf workspace, regardless of cwd
        # Unlike `git worktree list`, `sf worktree list` is global, so we filter
        # by the current repo (basename of the git toplevel at the popup's cwd).
        scope="$(opt_get '@tmux-worktree-manager-sf-scope' 'repo')"
        repo=""
        if [[ "$scope" == "repo" ]]; then
            top="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
            [[ -n "$top" ]] && repo="$(basename "$top")"
        fi
        command "$SF_CMD" worktree list --json 2>/dev/null \
            | jq -r --arg repo "$repo" '
                .[]
                | . as $w
                | ([ $w.Repos[]?
                     | select(.Name == $repo or ((.Path | split("/") | last) == $repo))
                     | .Path ] | first) as $mp
                | select($repo == "" or $mp != null)
                | [ $w.Name, ($mp // ($w.Repos[0].Path) // $w.Root) ]
                | @tsv
              '
        ;;
    path)
        name="${2:-}"
        [[ -n "$name" ]] || exit 1
        command "$SF_CMD" worktree list --json 2>/dev/null \
            | jq -r --arg n "$name" '.[] | select(.Name == $n) | ((.Repos // [])[0].Path // .Root)' \
            | head -n1
        ;;
    switch)
        # sf has no switch verb; popup.sh drives tmux-window.sh via the resolved path.
        exit 0
        ;;
    create)
        name="${2:-}"
        [[ -n "$name" ]] || exit 1
        # arg 3 (base) is intentionally ignored — sf has no base-branch concept.
        # Overlay the current repo (Linux --path; repo root, else basename fallback).
        path_arg="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || true)"
        [[ -n "$path_arg" ]] || path_arg="$(basename "$PWD")"
        command "$SF_CMD" worktree create "$name" --path "$path_arg"
        ;;
    remove)
        name="${2:-}"
        [[ -n "$name" ]] || exit 1
        # arg 3 (force) is ignored — sf destroy has no --force/--yes. The plugin
        # already confirmed via fzf; feed EOF so an unexpected prompt can't hang the popup.
        command "$SF_CMD" worktree destroy "$name" </dev/null
        ;;
    *)
        exit 1
        ;;
esac
