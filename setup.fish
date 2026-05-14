#!/usr/bin/env fish

# Dotfiles setup script
# Run this on a new machine to create symlinks

set -l DOTFILES_DIR (realpath (dirname (status --current-filename)))
set -l CONFIG_DIR ~/.config

echo "Setting up dotfiles from $DOTFILES_DIR"

# Create ~/.config if it doesn't exist
mkdir -p $CONFIG_DIR

# Function to safely create symlink
function safe_link
    set -l source $argv[1]
    set -l target $argv[2]

    if test -L $target
        echo "✓ $target is already a symlink"
    else if test -e $target
        echo "⚠ $target exists, backing up to $target.backup"
        mv $target $target.backup
        ln -s $source $target
        echo "✓ Created symlink: $target -> $source"
    else
        ln -s $source $target
        echo "✓ Created symlink: $target -> $source"
    end
end

# Create symlinks
safe_link $DOTFILES_DIR/fish $CONFIG_DIR/fish
safe_link $DOTFILES_DIR/tmux $CONFIG_DIR/tmux
safe_link $DOTFILES_DIR/nvim $CONFIG_DIR/nvim

# Function to set statusLine entry in ~/.claude/settings.json.
# Always overrides — dotfiles is source of truth. Other settings preserved.
function ensure_statusline
    set -l settings ~/.claude/settings.json
    set -l entry '{type: "command", command: "bash '$HOME'/.claude/statusline-command.sh"}'

    if not type -q jq
        echo "⚠ jq not installed; skipping settings.json patch (install jq and re-run)"
        return
    end

    if not test -e $settings
        echo '{}' > $settings
    end

    set -l before (jq -r '.statusLine.command // "none"' $settings)
    set -l tmp (mktemp)
    if jq ".statusLine = $entry" $settings > $tmp
        mv $tmp $settings
    else
        rm -f $tmp
        echo "⚠ Failed to patch $settings"
        return
    end
    set -l after (jq -r '.statusLine.command' $settings)

    if test "$before" = "$after"
        echo "✓ statusLine already configured ($after)"
    else
        echo "✓ Updated statusLine in $settings ($before → $after)"
    end
end

# Symlink individual files into existing directories
mkdir -p ~/.claude
safe_link $DOTFILES_DIR/claude/CLAUDE.md ~/.claude/CLAUDE.md
safe_link $DOTFILES_DIR/claude/statusline-command.sh ~/.claude/statusline-command.sh
ensure_statusline

echo ""
echo "Setup complete! Restart your shell or run 'exec fish' to apply changes."
