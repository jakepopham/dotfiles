# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a personal dotfiles repository that manages shell and version control configurations using symlinks.

## Repository Structure

- `fish/` - Fish shell configuration (symlinked to `~/.config/fish/`)
  - `config.fish` - Main configuration for interactive sessions
  - `conf.d/` - Auto-loaded configuration files
  - `functions/` - Custom Fish functions (auto-loaded by name)
- `tmux/` - Tmux terminal multiplexer configuration (symlinked to `~/.config/tmux/`)
  - `tmux.conf` - Tmux settings and keybindings
- `setup.fish` - Installation script that creates symlinks

## Setup and Installation

```fish
# Run this on a new machine to set up all dotfiles
./setup.fish
```

The setup script creates symlinks from `~/.config/` to this repository's directories. If existing configurations exist, they are backed up with a `.backup` suffix.

## Fish Shell Configuration

Fish automatically loads configuration in this order:
1. Files in `conf.d/*.fish` (alphabetically)
2. `config.fish`

### Custom Functions

Functions in `fish/functions/` are auto-loaded when called:
- `push.fish` - Shorthand for `git push`
- `pull.fish` - Shorthand for `git pull`

Each function file should be named `functionname.fish` and contain `function functionname; ...; end`.

### Testing Fish Changes

```fish
# Reload configuration in current session
source ~/.config/fish/config.fish

# Test a specific function without reloading everything
fish -c "push"

# Start fresh Fish session to test full config load
fish
```

### Fish Syntax Notes

Use Fish syntax (not Bash):
- Variables: `set var_name value`
- Conditionals: `if condition; ...; end`
- Command substitution: `(command)`
- Status checks: `status is-interactive`

## Tmux Configuration

The tmux config uses Fish shell as the default shell and includes:
- `Ctrl-a` as prefix (instead of `Ctrl-b`)
- Vim-like pane navigation (`prefix + h/j/k/l`)
- Intuitive split commands (`prefix + |` for vertical, `prefix + -` for horizontal)

### Key Bindings

- `Ctrl-a` - Prefix key
- `prefix + |` - Split window vertically
- `prefix + -` - Split window horizontally
- `prefix + h/j/k/l` - Navigate panes (vim-style)
- `prefix + r` - Reload tmux config

### Testing Tmux Changes

```fish
# Reload config from within tmux
tmux source-file ~/.config/tmux/tmux.conf

# Or use the keybinding: prefix + r

# Start new tmux session
tmux

# Attach to existing session
tmux attach
```
