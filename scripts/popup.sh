#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/options.sh"
source "$SCRIPT_DIR/diagnostics.sh"

FZF_CMD="$(opt_get '@tmux-worktree-manager-fzf-command' 'fzf')"
GH_ENABLED="$(opt_get '@tmux-worktree-manager-gh-prs' 'on')"
CLAUDE_ENABLED="$(opt_get '@tmux-worktree-manager-claude-status' 'on')"
PREVIEW_WIDTH="$(opt_get '@tmux-worktree-manager-preview-width' '60%')"
NERD_FONT="$(opt_get '@tmux-worktree-manager-nerd-font' 'on')"

ensure_cmd git 'required to read worktrees' || exit 0
ensure_cmd "$FZF_CMD" 'required for picker UI' || exit 0

WT_CMD="$(opt_get '@tmux-worktree-manager-wt-command' 'wt')"
ensure_cmd "$WT_CMD" 'required for worktrunk backend' || exit 0

parse_worktrees() {
    local cur_path=""
    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                cur_path="${line#worktree }"
                ;;
            "branch refs/heads/"*)
                echo "${line#branch refs/heads/}	$cur_path"
                ;;
            "")
                cur_path=""
                ;;
        esac
    done < <(git worktree list --porcelain 2>/dev/null)
}

pr_cache_file() {
    local origin hash
    origin="$(git remote get-url origin 2>/dev/null)" || return 1
    hash="$(printf '%s' "$origin" | md5 2>/dev/null || printf '%s' "$origin" | md5sum 2>/dev/null | awk '{print $1}')"
    echo "/tmp/tmux-worktree-manager-pr-${hash}"
}

refresh_pr_cache() {
    [[ "$GH_ENABLED" == "on" || "$GH_ENABLED" == "true" || "$GH_ENABLED" == "1" || "$GH_ENABLED" == "yes" ]] || return 0
    has_cmd gh || return 0

    local cache now mtime
    cache="$(pr_cache_file)" || return 0
    now="$(date +%s)"
    if [[ -f "$cache" ]]; then
        mtime="$(stat -f '%m' "$cache" 2>/dev/null || stat -c '%Y' "$cache" 2>/dev/null || echo 0)"
        if (( now - mtime < 300 )); then
            return 0
        fi
    fi

    (
        gh pr list --state all --limit 100 \
            --json number,headRefName,state,isDraft,title,reviewDecision,statusCheckRollup \
            --jq '.[] | [.headRefName, .number, .state, .isDraft, .title,
                  (.reviewDecision // ""),
                  ((.statusCheckRollup // []) | map(.conclusion) |
                   if length == 0 then "PENDING"
                   elif all(. == "SUCCESS") then "SUCCESS"
                   elif any(. == "FAILURE") then "FAILURE"
                   elif any(. == null) then "RUNNING"
                   else "UNKNOWN" end)] | @tsv' \
            > "${cache}.tmp" 2>/dev/null && mv "${cache}.tmp" "$cache"
    ) &
    disown 2>/dev/null || true
}

lookup_pr() {
    local branch="$1" cache
    cache="$(pr_cache_file)" || return 0
    [[ -f "$cache" ]] || return 0
    awk -F'\t' -v b="$branch" '$1 == b { print $2 "\t" $3 "\t" $4; exit }' "$cache"
}

before="$(parse_worktrees)"
[[ -n "$before" ]] || {
    msg 'tmux-worktree-manager: no worktrees in this repository'
    exit 0
}

refresh_pr_cache

wtdir="$(mktemp -d)"
trap 'rm -rf "$wtdir"' EXIT
echo "$before" > "$wtdir/worktrees"

pr_cache="$(pr_cache_file 2>/dev/null || true)"
if [[ -n "$pr_cache" ]]; then
    ln -sf "$pr_cache" "$wtdir/pr_cache"
fi

build_fzf_input() {
    local target_width=50
    while IFS=$'\t' read -r branch path; do
        [[ -z "$branch" ]] && continue
        local status="" priority=4 prefix="  "

        if [[ "$CLAUDE_ENABLED" == "on" || "$CLAUDE_ENABLED" == "true" || "$CLAUDE_ENABLED" == "1" || "$CLAUDE_ENABLED" == "yes" ]]; then
            local status_file="$path/.claude/status.json"
            if [[ -f "$status_file" ]] && has_cmd jq; then
                status="$(jq -r '.status // empty' "$status_file" 2>/dev/null || true)"
            fi
        fi

        if [[ "$NERD_FONT" == "on" || "$NERD_FONT" == "true" || "$NERD_FONT" == "1" || "$NERD_FONT" == "yes" ]]; then
            case "$status" in
                permission) prefix=$'\033[35m\uf023 '; priority=1 ;;
                question)   prefix=$'\033[33m\uf059 '; priority=1 ;;
                attention)  prefix=$'\033[33m\uf06a '; priority=1 ;;
                completed)  prefix=$'\033[32m\uf00c '; priority=2 ;;
                working)    prefix=$'\033[34m\uf021 '; priority=3 ;;
            esac
        else
            case "$status" in
                permission|question|attention) prefix=$'\033[33m! '; priority=1 ;;
                completed) prefix=$'\033[32m* '; priority=2 ;;
                working)   prefix=$'\033[34m~ '; priority=3 ;;
            esac
        fi

        local pr_info pr_badge="" pr_num=""
        pr_info="$(lookup_pr "$branch")"
        if [[ -n "$pr_info" ]]; then
            local pr_state pr_draft pr_color=""
            IFS=$'\t' read -r pr_num pr_state pr_draft <<< "$pr_info"
            if [[ "$pr_state" == "MERGED" ]]; then
                pr_color=$'\033[35m'
            elif [[ "$pr_state" == "CLOSED" ]]; then
                pr_color=$'\033[31m'
            elif [[ "$pr_draft" == "true" ]]; then
                pr_color=$'\033[90m'
            else
                pr_color=$'\033[32m'
            fi
            pr_badge="${pr_color}#${pr_num}"$'\033[0m'
        fi

        if [[ -n "$pr_badge" ]]; then
            local visible_len badge_visible_len pad_len
            visible_len=$((2 + ${#branch}))
            badge_visible_len=$((1 + ${#pr_num}))
            pad_len=$((target_width - visible_len - badge_visible_len))
            (( pad_len < 2 )) && pad_len=2
            printf -v pad '%*s' "$pad_len" ""
            printf '%d\t%s\t%s%s\033[0m%s%s\n' "$priority" "$branch" "$prefix" "$branch" "$pad" "$pr_badge"
        else
            printf '%d\t%s\t%s%s\033[0m\n' "$priority" "$branch" "$prefix" "$branch"
        fi
    done <<< "$before" | sort -t$'\t' -k1,1n | cut -f2-
}

result="$(build_fzf_input | command "$FZF_CMD" \
    --ansi \
    --delimiter=$'\t' \
    --with-nth=2.. \
    --nth=1 \
    --prompt='worktree> ' \
    --header='enter: switch (or create if no match) │ ctrl-d: remove' \
    --preview="$SCRIPT_DIR/preview.sh {1} $wtdir/worktrees $wtdir/pr_cache" \
    --preview-window="right:${PREVIEW_WIDTH},wrap" \
    --print-query \
    --expect='ctrl-d' \
    --no-multi \
    --exit-0 \
    2>/dev/null || true)"

query="$(echo "$result" | sed -n '1p')"
key="$(echo "$result" | sed -n '2p')"
selection="$(echo "$result" | sed -n '3p' | cut -f1)"

if [[ "$key" == 'ctrl-d' && -n "$selection" ]]; then
    wt_path="$(awk -F'\t' -v b="$selection" '$1 == b { print $2; exit }' <<< "$before")"

    force=""
    if [[ -n "$wt_path" && -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]]; then
        printf 'No\nYes, force remove' | command "$FZF_CMD" --ansi --no-multi \
            --prompt="'$selection' has uncommitted changes. Remove? > " \
            --header='Worktree has uncommitted changes' 2>/dev/null | grep -q '^Yes' || exit 0
        force='--force'
    else
        printf 'No\nYes' | command "$FZF_CMD" --ansi --no-multi \
            --prompt="Remove '$selection'? > " --header='Remove this worktree?' 2>/dev/null | grep -q '^Yes$' || exit 0
    fi

    [[ -n "$wt_path" ]] && "$SCRIPT_DIR/tmux-window.sh" remove "$wt_path" 2>/dev/null || true
    "$SCRIPT_DIR/backend-worktrunk.sh" remove "$selection" "$force" 2>/dev/null || true
    exit 0
fi

branch="$selection"
if [[ -z "$branch" ]]; then
    [[ -n "$query" ]] || exit 0

    printf 'Yes\nNo' | command "$FZF_CMD" --ansi --no-multi \
        --prompt="Create '$query'? > " --header='Create new worktree?' 2>/dev/null | grep -q '^Yes$' || exit 0

    default_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"
    [[ -n "$default_branch" ]] || default_branch='main'
    base="$(git branch --format='%(refname:short)' 2>/dev/null | command "$FZF_CMD" \
        --ansi --prompt='base branch> ' --header="Select base branch for '$query'" \
        --query="$default_branch" --no-multi 2>/dev/null || true)"

    [[ -n "$base" ]] || exit 0
    "$SCRIPT_DIR/backend-worktrunk.sh" create "$query" "$base" 2>/dev/null || exit 0
    exit 0
fi

"$SCRIPT_DIR/backend-worktrunk.sh" switch "$branch" 2>/dev/null || exit 0
