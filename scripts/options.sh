#!/usr/bin/env bash

set -euo pipefail

opt_get() {
    local key="$1"
    local fallback="$2"
    local val
    val="$(tmux show-option -gqv "$key" 2>/dev/null || true)"
    if [[ -z "$val" ]]; then
        printf '%s\n' "$fallback"
    else
        printf '%s\n' "$val"
    fi
}

opt_on() {
    local key="$1"
    local fallback="$2"
    local val
    val="$(opt_get "$key" "$fallback")"
    [[ "$val" == "on" || "$val" == "true" || "$val" == "1" || "$val" == "yes" ]]
}
