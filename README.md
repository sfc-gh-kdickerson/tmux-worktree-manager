# tmux-worktree-manager

Fast tmux popup picker for Git worktrees with optional worktrunk integration.

## Features

- `display-popup` + `fzf` picker for fast branch/worktree switching
- Create new worktrees from query input
- Remove worktrees from picker (`ctrl-d`)
- Preview panel with commit, dirty state, divergence, recent commits
- Optional PR badges/status using `gh`
- Optional Claude status badges from `.claude/status.json`
- Hook script for tmux window lifecycle (`scripts/tmux-window.sh`)

## Requirements

- tmux **3.2+** (uses `display-popup`)
- `git`
- `fzf`

Backend (pick one, see [Backends](#backends)):

- `wt` (worktrunk CLI) — for the default `worktrunk` backend
- `sf` (Snowflake CLI) + `jq` — for the `sf` backend

Optional:

- `gh` (PR cache/badges)
- `jq` (Claude status parsing)

## Install (TPM)

In `.tmux.conf`:

```tmux
set -g @plugin 'yourname/tmux-worktree-manager'
```

Reload tmux and install via TPM (`prefix + I`).

## Options

```tmux
set -g @tmux-worktree-manager-key 'C-;'
set -g @tmux-worktree-manager-prefixless 'on'
set -g @tmux-worktree-manager-popup-width '80%'
set -g @tmux-worktree-manager-popup-height '80%'
set -g @tmux-worktree-manager-popup-title 'Worktrees'
set -g @tmux-worktree-manager-preview-width '60%'

set -g @tmux-worktree-manager-backend 'worktrunk'
set -g @tmux-worktree-manager-wt-command 'wt'
set -g @tmux-worktree-manager-sf-command 'sf'
set -g @tmux-worktree-manager-fzf-command 'fzf'

set -g @tmux-worktree-manager-gh-prs 'on'
set -g @tmux-worktree-manager-claude-status 'on'
set -g @tmux-worktree-manager-nerd-font 'on'
```

## Backends

Set `@tmux-worktree-manager-backend` to choose how worktrees are enumerated and how
switch/create/remove are performed.

### `worktrunk` (default)

- Per-repo **git worktrees**, listed via `git worktree list --porcelain`.
- switch/create/remove delegate to the `wt` (worktrunk) CLI.
- worktrunk drives tmux windows itself via its own post-switch/post-remove hooks
  (see [Worktrunk hook integration](#worktrunk-hook-integration-optional)).
- Create prompts for a **base branch**.

### `sf` (Snowflake)

```tmux
set -g @tmux-worktree-manager-backend 'sf'
```

- **Global named workspaces** (not per-repo git worktrees), listed via `sf worktree list --json`
  (requires `jq`). Each row is a workspace **name** mapped to its repo path.
- `sf` has no tmux integration, so the plugin drives tmux windows itself via
  `scripts/tmux-window.sh`.
- Create takes **no base branch** — `sf` overlays existing checkouts (`sf worktree create <name>
  --path <current-repo>`); use `sf worktree rebase` to update a workspace.
- Because the row label is the workspace **name** (which may differ from the underlying git
  branch, e.g. `worktree/<name>`), **PR badges may not match** for the `sf` backend.
- Remove maps to `sf worktree destroy`. The plugin does its own confirmation prompt; `destroy` is
  invoked with stdin closed so it can't block the popup.

## Worktrunk hook integration (optional)

If you want tmux windows created/selected automatically after `wt switch` and removed after `wt remove`, wire hooks in your worktrunk config.

See: `examples/worktrunk-config.toml`

## Notes

- The plugin does not modify your worktrunk config.
- PR cache is stored in `/tmp` and refreshed in the background.
