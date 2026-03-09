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
safe_link $DOTFILES_DIR/jj $CONFIG_DIR/jj
safe_link $DOTFILES_DIR/tmux $CONFIG_DIR/tmux

# Symlink individual files into existing directories
mkdir -p ~/.claude
safe_link $DOTFILES_DIR/claude/CLAUDE.md ~/.claude/CLAUDE.md

echo ""
echo "Setup complete! Restart your shell or run 'exec fish' to apply changes."
