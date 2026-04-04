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
- `wt` (worktrunk CLI) for backend actions

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

set -g @tmux-worktree-manager-wt-command 'wt'
set -g @tmux-worktree-manager-fzf-command 'fzf'

set -g @tmux-worktree-manager-gh-prs 'on'
set -g @tmux-worktree-manager-claude-status 'on'
set -g @tmux-worktree-manager-nerd-font 'on'
```

## Worktrunk hook integration (optional)

If you want tmux windows created/selected automatically after `wt switch` and removed after `wt remove`, wire hooks in your worktrunk config.

See: `examples/worktrunk-config.toml`

## Notes

- The plugin does not modify your worktrunk config.
- PR cache is stored in `/tmp` and refreshed in the background.
