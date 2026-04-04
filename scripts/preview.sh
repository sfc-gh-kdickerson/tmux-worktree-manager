#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/options.sh"
source "$SCRIPT_DIR/diagnostics.sh"

branch="${1:-}"
wtfile="${2:-}"
pr_cache="${3:-}"

[[ -n "$branch" && -n "$wtfile" ]] || exit 0

claude_enabled="$(opt_get '@tmux-worktree-manager-claude-status' 'on')"
nerd_font="$(opt_get '@tmux-worktree-manager-nerd-font' 'on')"

bold=$'\033[1m'
dim=$'\033[2m'
reset=$'\033[0m'
red=$'\033[31m'
green=$'\033[32m'
yellow=$'\033[33m'
blue=$'\033[34m'
magenta=$'\033[35m'
cyan=$'\033[36m'
gray=$'\033[90m'

path="$(awk -F'\t' -v b="$branch" '$1 == b { print $2; exit }' "$wtfile")"
if [[ -z "$path" ]]; then
    echo "${dim}No worktree for this branch${reset}"
    exit 0
fi

last_commit_ts="$(git -C "$path" log -1 --format='%ct' 2>/dev/null || echo '')"
age=''
if [[ -n "$last_commit_ts" ]]; then
    now="$(date +%s)"
    delta=$((now - last_commit_ts))
    if (( delta < 3600 )); then
        age="$((delta / 60))m ago"
    elif (( delta < 86400 )); then
        age="$((delta / 3600))h ago"
    elif (( delta < 604800 )); then
        age="$((delta / 86400))d ago"
    elif (( delta < 2592000 )); then
        age="$((delta / 604800))w ago"
    else
        age="$((delta / 2592000))mo ago"
    fi

    if (( delta >= 1814400 )); then
        age="${red}${age}${reset}"
    elif (( delta >= 604800 )); then
        age="${yellow}${age}${reset}"
    else
        age="${gray}${age}${reset}"
    fi
fi

cols="${FZF_PREVIEW_COLUMNS:-80}"
branch_display="${bold}${branch}${reset}"
printf '  %s%*s\n' "$branch_display" $((cols - ${#branch} - 4)) "$age"
printf '  %s\n' "${gray}$(printf '%*s' $((cols - 4)) '' | tr ' ' '─')${reset}"

if [[ "$claude_enabled" == 'on' || "$claude_enabled" == 'true' || "$claude_enabled" == '1' || "$claude_enabled" == 'yes' ]]; then
    status_file="$path/.claude/status.json"
    if [[ -f "$status_file" ]] && has_cmd jq; then
        IFS=$'\t' read -r claude_status claude_ts < <(jq -r '[(.status // ""), (.timestamp // "")] | @tsv' "$status_file" 2>/dev/null) || true
        status_age=''
        if [[ -n "$claude_ts" ]]; then
            now="$(date +%s)"
            sa=$((now - claude_ts))
            if (( sa < 60 )); then
                status_age="${sa}s"
            elif (( sa < 3600 )); then
                status_age="$((sa / 60))m"
            elif (( sa < 86400 )); then
                status_age="$((sa / 3600))h"
            else
                status_age="$((sa / 86400))d"
            fi
        fi

        if [[ "$nerd_font" == 'on' || "$nerd_font" == 'true' || "$nerd_font" == '1' || "$nerd_font" == 'yes' ]]; then
            case "$claude_status" in
                working)    echo "  ${blue}"$'\uf021'"${reset} ${bold}Claude working${reset} ${gray}${status_age}${reset}" ;;
                completed)  echo "  ${green}"$'\uf00c'"${reset} ${bold}Claude done${reset} ${gray}${status_age}${reset}" ;;
                question)   echo "  ${yellow}"$'\uf059'"${reset} ${bold}${yellow}Needs input${reset} ${gray}${status_age}${reset}" ;;
                permission) echo "  ${magenta}"$'\uf023'"${reset} ${bold}${magenta}Permission needed${reset} ${gray}${status_age}${reset}" ;;
                attention)  echo "  ${yellow}"$'\uf06a'"${reset} ${bold}${yellow}Needs attention${reset} ${gray}${status_age}${reset}" ;;
            esac
        else
            case "$claude_status" in
                working)    echo "  ${blue}~${reset} ${bold}Claude working${reset} ${gray}${status_age}${reset}" ;;
                completed)  echo "  ${green}*${reset} ${bold}Claude done${reset} ${gray}${status_age}${reset}" ;;
                question|permission|attention) echo "  ${yellow}!${reset} ${bold}${yellow}Needs attention${reset} ${gray}${status_age}${reset}" ;;
            esac
        fi
    fi
fi

if [[ -n "$pr_cache" && -f "$pr_cache" ]]; then
    pr_line="$(awk -F'\t' -v b="$branch" '$1 == b { print; exit }' "$pr_cache")"
    if [[ -n "$pr_line" ]]; then
        IFS=$'\t' read -r _branch pr_num pr_state pr_draft pr_title pr_review pr_ci <<< "$pr_line"
        state_text=''
        case "$pr_state" in
            OPEN)
                if [[ "$pr_draft" == 'true' ]]; then
                    state_text="${gray}Draft${reset}"
                else
                    state_text="${green}Open${reset}"
                fi
                ;;
            MERGED) state_text="${magenta}Merged${reset}" ;;
            CLOSED) state_text="${red}Closed${reset}" ;;
        esac

        echo ''
        echo "  ${bold}PR #${pr_num}${reset} — ${state_text}"

        if [[ "$pr_state" == 'OPEN' ]]; then
            [[ -n "$pr_title" ]] && echo "  ${dim}${pr_title}${reset}"

            review_badge=''
            ci_badge=''
            case "$pr_review" in
                APPROVED) review_badge="${green}✔ Approved${reset}" ;;
                CHANGES_REQUESTED) review_badge="${red}✘ Changes requested${reset}" ;;
                REVIEW_REQUIRED) review_badge="${yellow}○ Review needed${reset}" ;;
                '') review_badge="${gray}○ No reviews${reset}" ;;
            esac
            case "$pr_ci" in
                SUCCESS) ci_badge="${green}✔ CI pass${reset}" ;;
                FAILURE) ci_badge="${red}✘ CI fail${reset}" ;;
                RUNNING) ci_badge="${blue}⟳ CI running${reset}" ;;
                *) ci_badge="${gray}○ CI pending${reset}" ;;
            esac
            echo "  ${review_badge}    ${ci_badge}"
        fi
    fi
fi

commit_msg="$(git -C "$path" log -1 --format='%s' 2>/dev/null || echo '')"
if [[ -n "$commit_msg" ]]; then
    echo ''
    echo "  ${commit_msg}"
fi

echo ''
printf '  %s\n' "${gray}$(printf '%*s' $((cols - 4)) '' | tr ' ' '╌')${reset}"
echo ''

staged="$(git -C "$path" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')"
modified="$(git -C "$path" diff --numstat 2>/dev/null | wc -l | tr -d ' ')"
untracked="$(git -C "$path" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"

dirty_parts=()
(( staged > 0 )) && dirty_parts+=("${staged} staged")
(( modified > 0 )) && dirty_parts+=("${modified} modified")
(( untracked > 0 )) && dirty_parts+=("${untracked} untracked")

if (( ${#dirty_parts[@]} > 0 )); then
    dirty="${yellow}●${reset} $(IFS=', '; echo "${dirty_parts[*]}")"
else
    dirty="${green}✔${reset} ${dim}Clean${reset}"
fi

if git -C "$path" rev-parse --verify --quiet refs/heads/main >/dev/null 2>&1; then
    main_branch='main'
else
    main_branch='master'
fi

ahead=0
behind=0
if git -C "$path" rev-parse --verify --quiet "refs/heads/${main_branch}" >/dev/null 2>&1; then
    read -r behind ahead < <(git -C "$path" rev-list --left-right --count "${main_branch}...HEAD" 2>/dev/null || echo '0 0')
fi

divergence=''
if (( ahead > 0 && behind > 0 )); then
    divergence="${cyan}↑${ahead}${reset} ${red}↓${behind} ${main_branch}${reset}"
    (( behind > 20 )) && divergence="${divergence} ${red}⚠${reset}"
elif (( ahead > 0 )); then
    divergence="${cyan}↑${ahead} ahead of ${main_branch}${reset}"
elif (( behind > 0 )); then
    divergence="${red}↓${behind} behind ${main_branch}${reset}"
    (( behind > 20 )) && divergence="${divergence} ${red}⚠${reset}"
fi

if [[ -n "$divergence" ]]; then
    echo "  ${dirty}    ${divergence}"
else
    echo "  ${dirty}"
fi

echo ''
printf '  %s\n' "${gray}$(printf '%*s' $((cols - 4)) '' | tr ' ' '╌')${reset}"
echo ''
echo "  ${gray}Recent commits${reset}"

git -C "$path" log --oneline --no-decorate -15 2>/dev/null | while IFS= read -r line; do
    echo "  ${line}"
done

echo ''
short_path="${path/#$HOME/~}"
echo "  ${gray}${short_path}${reset}"
