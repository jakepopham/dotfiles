# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Fish shell configuration directory located at `~/.config/fish/`. It contains minimal customization with standard Fish shell structure.

## Directory Structure

- `config.fish` - Main configuration file that runs for interactive sessions
- `conf.d/` - Auto-loaded configuration files
  - `uv.env.fish` - Sources UV environment from `~/.local/bin/env.fish`
- `functions/` - Custom Fish functions (currently empty)
- `completions/` - Custom tab completions (currently empty)
- `fish_variables` - Universal variables (managed by Fish, don't edit directly)

## Fish Shell Basics

Fish automatically loads files in this order:
1. Files in `conf.d/*.fish` (alphabetically)
2. `config.fish`

Functions placed in `functions/` are auto-loaded when called. Each function should be in a file named `functionname.fish`.

Completions in `completions/` follow the pattern `command.fish` and are auto-loaded.

## Testing Changes

```bash
# Reload configuration
source ~/.config/fish/config.fish

# Test a specific function
fish -c "your_function_name args"

# Start a new Fish session to test full config
fish
```

## File Syntax

Use Fish shell syntax, not bash. Key differences:
- Variables: `set var_name value` (not `var_name=value`)
- Conditionals: `if condition; ...; end` (not `if [ condition ]; then...; fi`)
- Command substitution: `(command)` (not `$(command)`)
- Status checks: `status is-interactive` (not `[[ -n "$PS1" ]]`)
