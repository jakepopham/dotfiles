#!/usr/bin/env bash
# Vim/airline-style statusline for Claude Code.
# Three chunks separated by stretchy whitespace:
#   left   = cwd · git
#   middle = model · context · quotas
#   right  = GPU info · util · memory
# Each segment is a colored block with a powerline arrow () transitioning
# to the next segment's background. Each chunk's outer edges fade into the
# default bg via and . Requires a Powerline-patched terminal font
# (Nerd Font, MesloLGS NF, etc) for the arrow glyphs to render.

input=$(cat)

# --- parse Claude Code stdin payload via python3 ---
parsed=$(printf '%s' "$input" | python3 -c '
import json, sys, time

def fmt_dur(s):
    s = max(0, int(s))
    if s < 60: return f"{s}s"
    m, s = divmod(s, 60)
    if m < 60: return f"{m}m"
    h, m = divmod(m, 60)
    if h < 24: return f"{h}h{m:02d}m"
    d, h = divmod(h, 24)
    return f"{d}d{h}h"

d = json.load(sys.stdin)
ws = d.get("workspace") or {}
cwd = ws.get("current_dir") or d.get("cwd") or ""
model = (d.get("model") or {}).get("display_name") or ""
ctx = (d.get("context_window") or {}).get("remaining_percentage")
ctx_str = "" if ctx is None else f"{int(round(float(ctx)))}"
rl = d.get("rate_limits") or {}
fh = rl.get("five_hour") or {}
sd = rl.get("seven_day") or {}
now = time.time()
def emit(qd):
    used = qd.get("used_percentage")
    rst = qd.get("resets_at")
    used_s = "" if used is None else f"{int(round(float(used)))}"
    rst_s  = "" if rst  is None else fmt_dur(int(rst) - now)
    print(used_s); print(rst_s)
print(cwd); print(model); print(ctx_str)
emit(fh)  # lines 4,5: fh_used, fh_reset
emit(sd)  # lines 6,7: sd_used, sd_reset
' 2>/dev/null)
cwd_abs=$(printf '%s\n' "$parsed" | sed -n '1p')
cwd=$cwd_abs
model=$(printf '%s\n' "$parsed" | sed -n '2p')
# Strip trailing annotations like " (1M context)" from display_name to save
# width — it duplicates info the user already chose at session start.
model=$(printf '%s' "$model" | sed -E 's/[[:space:]]*\([^)]*context\)$//')
remaining=$(printf '%s\n' "$parsed" | sed -n '3p')
fh_used=$(printf '%s\n' "$parsed" | sed -n '4p')
fh_reset=$(printf '%s\n' "$parsed" | sed -n '5p')
sd_used=$(printf '%s\n' "$parsed" | sed -n '6p')
sd_reset=$(printf '%s\n' "$parsed" | sed -n '7p')

# Shorten cwd: replace $HOME with ~
home=$(printf '%s' "$HOME" | sed 's|/$||')
case "$cwd" in
    "$home"*) cwd="~${cwd#$home}" ;;
esac

# --- git state for cwd ---
# One porcelain-v2 call, parsed in pure bash. Format: " <branch> [*] [↑N] [↓N]"
# — `*` when any tracked file is modified/staged or any untracked file exists;
# ↑/↓ counts against the configured upstream when one is set. Silently skipped
# when cwd isn't a git work tree.
git_text=""
if [ -n "$cwd_abs" ] && [ -d "$cwd_abs" ] \
   && git_status=$(git -C "$cwd_abs" --no-optional-locks status \
                       --porcelain=v2 --branch 2>/dev/null); then
    branch=""; ahead=0; behind=0; dirty=0
    while IFS= read -r line; do
        case "$line" in
            "# branch.head "*)
                branch=${line#\# branch.head } ;;
            "# branch.ab "*)
                ab=${line#\# branch.ab }
                ahead=${ab%% *}; ahead=${ahead#+}
                behind=${ab##* }; behind=${behind#-} ;;
            [12?!u]\ *)
                dirty=1 ;;
        esac
    done <<< "$git_status"
    # Detached HEAD: porcelain prints "(detached)" — replace with short hash.
    if [ "$branch" = "(detached)" ]; then
        sha=$(git -C "$cwd_abs" rev-parse --short HEAD 2>/dev/null)
        if [ -n "$sha" ]; then branch=":$sha"; else branch=""; fi
    fi
    if [ -n "$branch" ]; then
        git_text=" $branch"
        [ "$dirty"  = "1" ] && git_text="$git_text *"
        [ "$ahead"  != "0" ] && git_text="$git_text ↑$ahead"
        [ "$behind" != "0" ] && git_text="$git_text ↓$behind"
        git_text="$git_text "
    fi
fi

# --- GPU state ---
# 1) static info (name + CUDA version) — cached, populated on first invocation
# 2) dynamic stats: utilization, temp, power, memory, compute-proc count
gpu_info_seg=""
gpu_compute_seg=""; gpu_pct=""
gpu_mem_seg=""
if command -v nvidia-smi >/dev/null 2>&1; then
    info_cache=/tmp/cc-statusline-gpu-info
    if [ ! -s "$info_cache" ]; then
        nm=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
        # Trim NVIDIA prefix and trailing memory tag, e.g. "NVIDIA GH200 480GB" → "GH200".
        nm_short=$(printf '%s' "$nm" | sed -E 's/^NVIDIA //; s/ [0-9]+GB$//' )
        cuda=$(nvidia-smi 2>/dev/null | grep -oP 'CUDA Version:\s*\K[0-9.]+' | head -1)
        printf '%s|%s' "${nm_short:-GPU}" "${cuda:-?}" > "$info_cache"
    fi
    info=$(cat "$info_cache" 2>/dev/null)
    nm_short=${info%%|*}
    cuda=${info##*|}
    gpu_info_seg=" ${nm_short} · CUDA ${cuda} "

    g=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw \
                  --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -n "$g" ]; then
        util=$(printf '%s' "$g"  | awk -F',' '{gsub(/ /,"",$1); print $1}')
        mu=$(printf '%s' "$g"    | awk -F',' '{gsub(/ /,"",$2); printf "%.0f",$2/1024}')
        mt=$(printf '%s' "$g"    | awk -F',' '{gsub(/ /,"",$3); printf "%.0f",$3/1024}')
        temp=$(printf '%s' "$g"  | awk -F',' '{gsub(/ /,"",$4); print $4}')
        power=$(printf '%s' "$g" | awk -F',' '{gsub(/ /,"",$5); printf "%.0f",$5}')
        gpu_pct=$util
        nproc_compute=$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null \
                        | grep -c .)
        gpu_compute_seg=" ${util}% ${temp}°C ${power}W "
        if [ -n "$nproc_compute" ] && [ "$nproc_compute" -gt 0 ]; then
            gpu_mem_seg=" ${mu}/${mt}G · ${nproc_compute}p "
        else
            gpu_mem_seg=" ${mu}/${mt}G "
        fi
    fi
fi


# --- progress-fill bar text (context window + rate-limit quotas) ---
# Each bar renders as a split segment (bright bg over the filled portion, dim
# bg over the empty portion) — the bar's *width* is the text's cell length, so
# we pad the label to a fixed BAR_W to give each bar a uniform, visible track.
# Label is centered so the fill grows under it rather than chasing it across.
BAR_W=18

pad_center() {  # $1=label  → echoes label centered in BAR_W cells (no-op if too long)
    local t=$1 len=${#1}
    if [ "$len" -ge "$BAR_W" ]; then printf ' %s ' "$t"; return; fi
    local total=$(( BAR_W - len ))
    local left=$(( total / 2 ))
    local right=$(( total - left ))
    printf '%*s%s%*s' "$left" '' "$t" "$right" ''
}

ctx_text=""
if [ -n "$remaining" ]; then
    ctx_text=$(pad_center "ctx ${remaining}%")
fi

fh_text=""
if [ -n "$fh_used" ]; then
    if [ -n "$fh_reset" ]; then
        fh_text=$(pad_center "${fh_used}% · ${fh_reset}")
    else
        fh_text=$(pad_center "${fh_used}%")
    fi
fi
sd_text=""
if [ -n "$sd_used" ]; then
    if [ -n "$sd_reset" ]; then
        sd_text=$(pad_center "${sd_used}% · ${sd_reset}")
    else
        sd_text=$(pad_center "${sd_used}%")
    fi
fi

# --- airline-style segments with powerline transitions ---
# 256-color background indices, chosen for readable contrast on dark terms.
BG_CWD=24             # deep blue
BG_GIT=58             # olive: distinct from cwd/model/context palette
BG_MODEL=53           # deep purple
BG_GPU_INFO=237       # static info: mid-dark gray
BG_GPU_COMPUTE=23     # dynamic util/temp/power: teal
BG_GPU_MEM=30         # mem + procs: darker teal/cyan
BG_LOAD=238           # dark gray
FG_LIGHT=255          # near-white
FG_DARK=232           # near-black

if [ -n "$remaining" ]; then
    if   [ "$remaining" -ge 50 ]; then
        BG_CTX_FULL=28 ; BG_CTX_DIM=22 ; FG_CTX=$FG_LIGHT       # bright/dim green
    elif [ "$remaining" -ge 20 ]; then
        BG_CTX_FULL=172; BG_CTX_DIM=94 ; FG_CTX=$FG_LIGHT       # bright/dim amber
    else
        BG_CTX_FULL=160; BG_CTX_DIM=52 ; FG_CTX=$FG_LIGHT       # bright/dim red
    fi
fi

# Quota color tier per segment (high USED is bad).
quota_colors() {  # $1=used_pct  →  echoes "BG_FULL BG_DIM FG"
    pct=$1
    if   [ "$pct" -lt 50 ]; then echo "28 22 $FG_LIGHT"
    elif [ "$pct" -lt 80 ]; then echo "172 94 $FG_LIGHT"
    else                         echo "160 52 $FG_LIGHT"
    fi
}

ARROW=""   # U+E0B0 right-pointing powerline arrow
LARROW=""  # U+E0B2 left-pointing powerline arrow

emit_seg() {  # $1=bg $2=fg $3=text   (caller controls leading/trailing space)
    printf '\033[48;5;%sm\033[38;5;%sm%s' "$1" "$2" "$3"
}
emit_trans() {  # $1=bg_left $2=bg_right
    printf '\033[48;5;%sm\033[38;5;%sm%s' "$2" "$1" "$ARROW"
}
emit_end() {    # $1=bg_left  (right arrow that fades into default bg)
    printf '\033[0m\033[38;5;%sm%s\033[0m' "$1" "$ARROW"
}
emit_lstart() { # $1=bg_right (left arrow into right-aligned segment from default bg)
    printf '\033[0m\033[38;5;%sm%s' "$1" "$LARROW"
}

# Build the line as three chunks separated by stretchy whitespace:
#   left   = dir/git
#   middle = model/usage (model + context bar + quotas)
#   right  = hardware (GPU info / compute / memory)
# Each chunk's outer edges fade into default bg via emit_lstart / emit_end,
# the same mechanism the right chunk has always used. Visible-cell length
# is counted as `${#text}` (ASCII labels) plus 1 per powerline arrow.

# --- left chunk: cwd + git ---
left_text=""
left_w=0
text=" $cwd "
left_text+=$(emit_seg $BG_CWD $FG_LIGHT "$text"); left_w=$(( left_w + ${#text} ))
left_last_bg=$BG_CWD
if [ -n "$git_text" ]; then
    left_text+=$(emit_trans $left_last_bg $BG_GIT);          left_w=$(( left_w + 1 ))
    left_text+=$(emit_seg $BG_GIT $FG_LIGHT "$git_text");    left_w=$(( left_w + ${#git_text} ))
    left_last_bg=$BG_GIT
fi
left_text+=$(emit_end $left_last_bg); left_w=$(( left_w + 1 ))

# --- middle chunk: model + context bar + quotas ---
mid_text=""
mid_w=0
mid_text+=$(emit_lstart $BG_MODEL);                         mid_w=$(( mid_w + 1 ))
text=" $model "
mid_text+=$(emit_seg $BG_MODEL $FG_LIGHT "$text");          mid_w=$(( mid_w + ${#text} ))
mid_last_bg=$BG_MODEL

if [ -n "$remaining" ]; then
    mid_text+=$(emit_trans $mid_last_bg $BG_CTX_FULL); mid_w=$(( mid_w + 1 ))
    seg_n=${#ctx_text}
    fill_n=$(( (remaining * seg_n + 50) / 100 ))
    [ "$fill_n" -lt 0 ] && fill_n=0
    [ "$fill_n" -gt "$seg_n" ] && fill_n=$seg_n
    mid_text+=$(printf '\033[48;5;%sm\033[38;5;%sm%s' "$BG_CTX_FULL" "$FG_CTX" "${ctx_text:0:$fill_n}")
    mid_text+=$(printf '\033[48;5;%sm\033[38;5;%sm%s' "$BG_CTX_DIM"  "$FG_CTX" "${ctx_text:$fill_n}")
    mid_w=$(( mid_w + seg_n ))
    mid_last_bg=$BG_CTX_DIM
fi

add_quota_seg() {  # $1=text $2=used_pct  → appends a split-bg quota segment to mid_text
    seg_text=$1
    pct=$2
    [ -z "$seg_text" ] && return
    read -r bg_full bg_dim fg <<< "$(quota_colors "$pct")"
    mid_text+=$(emit_trans $mid_last_bg $bg_full); mid_w=$(( mid_w + 1 ))
    seg_n=${#seg_text}
    fill_n=$(( (pct * seg_n + 50) / 100 ))
    [ "$fill_n" -lt 0 ] && fill_n=0
    [ "$fill_n" -gt "$seg_n" ] && fill_n=$seg_n
    mid_text+=$(printf '\033[48;5;%sm\033[38;5;%sm%s' "$bg_full" "$fg" "${seg_text:0:$fill_n}")
    mid_text+=$(printf '\033[48;5;%sm\033[38;5;%sm%s' "$bg_dim"  "$fg" "${seg_text:$fill_n}")
    mid_w=$(( mid_w + seg_n ))
    mid_last_bg=$bg_dim
}
add_quota_seg "$fh_text" "${fh_used:-0}"
add_quota_seg "$sd_text" "${sd_used:-0}"

mid_text+=$(emit_end $mid_last_bg); mid_w=$(( mid_w + 1 ))

# --- right chunk: hardware (GPU info / compute / memory) ---
right_text=""; right_w=0
right_segs=()
[ -n "$gpu_info_seg"    ] && right_segs+=("$BG_GPU_INFO"    "$gpu_info_seg")
[ -n "$gpu_compute_seg" ] && right_segs+=("$BG_GPU_COMPUTE" "$gpu_compute_seg")
[ -n "$gpu_mem_seg"     ] && right_segs+=("$BG_GPU_MEM"     "$gpu_mem_seg")

if [ ${#right_segs[@]} -gt 0 ]; then
    first_bg=${right_segs[0]}; first_text=${right_segs[1]}
    right_text+=$(emit_lstart $first_bg);                 right_w=$(( right_w + 1 ))
    right_text+=$(emit_seg $first_bg $FG_LIGHT "$first_text"); right_w=$(( right_w + ${#first_text} ))
    last_bg=$first_bg
    i=2
    while [ $i -lt ${#right_segs[@]} ]; do
        bg=${right_segs[$i]}; text=${right_segs[$((i+1))]}
        right_text+=$(emit_trans $last_bg $bg);            right_w=$(( right_w + 1 ))
        right_text+=$(emit_seg $bg $FG_LIGHT "$text");     right_w=$(( right_w + ${#text} ))
        last_bg=$bg
        i=$(( i + 2 ))
    done
    right_text+=$(emit_end $last_bg); right_w=$(( right_w + 1 ))
fi

# Center the middle chunk on the line; left and right pads absorb the rest.
# When the right chunk is empty (no GPU), the middle still floats around the
# midpoint instead of hugging the right edge.
term_w=${COLUMNS:-100}
mid_start=$(( (term_w - mid_w) / 2 ))
left_pad=$(( mid_start - left_w ))
right_pad=$(( term_w - mid_start - mid_w - right_w ))
[ "$left_pad"  -lt 1 ] && left_pad=1
[ "$right_pad" -lt 1 ] && right_pad=1
spacer_l=$(printf '%*s' "$left_pad"  '')
spacer_r=$(printf '%*s' "$right_pad" '')

printf '%s%s%s%s%s\n' "$left_text" "$spacer_l" "$mid_text" "$spacer_r" "$right_text"
