if status is-interactive
    # Commands to run in interactive sessions can go here
    neofetch
end

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :

if test "$TERM_PROGRAM" = ghostty; and not set -q TMUX
    set -gx TERM xterm-256color
end
