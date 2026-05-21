#!/usr/bin/env bash
# Progress-bar system-stat pills for the tmux status bar. Called by status-right
# via #(...), once per status-interval. Usage: system-stats.sh {cpu|mem}
#
# Each call emits a complete rounded pill as tmux #[...] style directives (tmux
# re-parses #() output for styles): a U+E0B6/U+E0B4 capped pill whose body bg is
# split — the bright tier colour over the filled fraction (CPU% / RAM-in-use%),
# a dark track over the rest. This mirrors bar_pill in claude/statusline-command
# .sh, but emits tmux directives rather than raw ANSI, and uses the gruvbox
# palette to match the rest of this bar (the Claude bar uses Claude's theme).
#
# CPU% is a rate, so it needs two samples. On Linux we delta /proc/stat against
# a /tmp cache, so a single call never blocks. macOS exposes no cumulative CPU
# ticks to plain shell, so it sums ps(1) per-process %cpu: instant, but a
# decaying average rather than a precise instantaneous read.

metric=$1
os=$(uname -s)

# --- metric probes: each echoes "PCT|LABEL" ---

cpu_stat() {  # → "PCT|CPU NN%"
    local pct
    if [ "$os" = Linux ]; then
        local cache=/tmp/tmux-cpu-stat _ u n s idle iowait irq softirq steal
        read -r _ u n s idle iowait irq softirq steal _ < /proc/stat
        local total=$(( u + n + s + idle + iowait + irq + softirq + steal ))
        local busy=$(( total - idle - iowait ))
        local ptotal=0 pbusy=0
        [ -r "$cache" ] && read -r ptotal pbusy < "$cache"
        printf '%s %s\n' "$total" "$busy" > "$cache"
        local dt=$(( total - ptotal )) db=$(( busy - pbusy ))
        if [ "$dt" -le 0 ]; then pct=0; else pct=$(( (db * 100 + dt / 2) / dt )); fi
    else
        local ncpu
        ncpu=$(sysctl -n hw.ncpu)
        pct=$(ps -A -o %cpu= | awk -v n="$ncpu" \
              '{s += $1} END { printf "%.0f", (n > 0 ? s / n : 0) }')
    fi
    printf '%s|CPU %s%%' "$pct" "$pct"
}

mem_stat() {  # → "PCT|RAM USED/TOTALG"
    if [ "$os" = Linux ]; then
        awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2}
             END { u = t - a
                   printf "%d|RAM %.1f/%.0fG", u*100/t, u/1048576, t/1048576 }' \
            /proc/meminfo
    else
        local total pagesize a w c
        total=$(sysctl -n hw.memsize)
        pagesize=$(sysctl -n hw.pagesize)
        # "in use" = active + wired + compressed pages (reclaimable inactive
        # pages count as free), roughly Activity Monitor's "Memory Used".
        eval "$(vm_stat | awk '
            /Pages active:/                 { gsub(/\./,"",$3); print "a=" $3 }
            /Pages wired down:/             { gsub(/\./,"",$4); print "w=" $4 }
            /Pages occupied by compressor:/ { gsub(/\./,"",$5); print "c=" $5 }
        ')"
        awk -v u=$(( (a + w + c) * pagesize )) -v t="$total" \
            'BEGIN { printf "%d|RAM %.1f/%.0fG", u*100/t,
                     u/1073741824, t/1073741824 }'
    fi
}

# --- pill rendering ---
# Cap glyphs from their UTF-8 bytes so this file stays pure ASCII.
CAP_L=$(printf '\356\202\266')  # U+E0B6 left half-circle
CAP_R=$(printf '\356\202\264')  # U+E0B4 right half-circle
BG0='#282828'      # bar background / cap backdrop
TRACK='#3c3836'    # the empty (unfilled) portion of the bar
FG_FILL='#282828'  # text over the bright fill
FG_TRACK='#a89984' # dim text over the track

tier() {  # $1=pct → gruvbox tier colour: green < 50, amber < 80, else red
    if   [ "$1" -lt 50 ]; then printf '#b8bb26'
    elif [ "$1" -lt 80 ]; then printf '#fabd2f'
    else                       printf '#fb4934'
    fi
}

pad_center() {  # $1=label $2=width → label centered in width cells
    local t=$1 w=$2 len=${#1}
    [ "$len" -ge "$w" ] && { printf '%s' "$t"; return; }
    local total=$(( w - len )) left=$(( (w - len) / 2 ))
    printf '%*s%s%*s' "$left" '' "$t" "$(( total - left ))" ''
}

bar_pill() {  # $1=pct $2=label → emits a tmux-styled split-fill pill
    local pct=$1 label=$2 n=${#2}
    local f=$(( (pct * n + 50) / 100 ))
    [ "$f" -lt 0 ] && f=0
    [ "$f" -gt "$n" ] && f=$n
    local fill; fill=$(tier "$pct")
    local lcap=$TRACK rcap=$TRACK
    [ "$f" -gt 0 ]   && lcap=$fill
    [ "$f" -ge "$n" ] && rcap=$fill
    printf '#[fg=%s,bg=%s]%s'  "$lcap"  "$BG0"      "$CAP_L"
    printf '#[bg=%s,fg=%s]%s'  "$fill"  "$FG_FILL"  "${label:0:$f}"
    printf '#[bg=%s,fg=%s]%s'  "$TRACK" "$FG_TRACK" "${label:$f}"
    printf '#[fg=%s,bg=%s]%s#[default]' "$rcap" "$BG0" "$CAP_R"
}

case "$metric" in
    cpu) IFS='|' read -r pct label <<< "$(cpu_stat)"; bar_pill "${pct:-0}" "$(pad_center "$label" 11)" ;;
    mem) IFS='|' read -r pct label <<< "$(mem_stat)"; bar_pill "${pct:-0}" "$(pad_center "$label" 15)" ;;
    *)   printf '#[default]?' ;;
esac
