#!/usr/bin/env bash
# Rounded-pill statusline for Claude Code, themed to Claude Code's dark theme.
# Three chunks separated by stretchy whitespace:
#   left   = cwd · git
#   middle = model · context · quotas
#   right  = GPU info · util · memory
# Each segment is an independent "pill": a coloured body bracketed by U+E0B6 /
# U+E0B4 half-circle caps drawn in the pill's colour over the terminal bg, so
# the edges read as rounded. Colours are lifted from Claude Code's built-in
# dark theme (claude / success / warning / error / suggestion / ...), so the
# bar sits natively inside the Claude Code UI. Context/quota pills double as
# progress bars: the body bg is the bright tier colour over the filled
# fraction, a neutral grey track over the rest. Requires a Nerd Font for the
# cap glyphs and a truecolor terminal.

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
# Each bar renders as a pill whose body bg is split (bright tier colour over
# the filled portion, a neutral grey track over the rest) — the bar's *width*
# is the text's cell length, so we pad the label to a fixed BAR_W to give each
# bar a uniform, visible track. Label is centered so the fill grows under it
# rather than chasing it across.
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
ctx_used=""
if [ -n "$remaining" ]; then
    ctx_used=$(( 100 - remaining ))
    ctx_text=$(pad_center "ctx ${ctx_used}%")
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

# --- Claude Code dark-theme palette (R;G;B), lifted from the CLI's themes ---
C_INK='0;0;0'          # inverseText       text on bright pills
C_TEXT='255;255;255'   # text              text on dark pills
C_DIM='193;193;193'    # inactiveShimmer   dim text on the bar track
C_SURFACE='80;80;80'   # subtle            neutral dark pill + progress-bar track
C_ORANGE='215;119;87'  # claude            model pill (Claude's signature accent)
C_BLUE='177;185;249'   # suggestion        cwd pill
C_GREEN='78;186;101'   # success           git pill, bar fill < 50%
C_AMBER='255;193;7'    # warning           bar fill 50-80%
C_RED='255;107;128'    # error             bar fill >= 80%
C_TEAL='72;150;140'    # planMode          GPU util pill
C_STEEL='106;155;204'  # professionalBlue  GPU memory pill

# Cap glyphs: generated from their UTF-8 bytes so this file stays pure ASCII.
CAP_L=$(printf '\356\202\266')  # U+E0B6 left half-circle pill cap
CAP_R=$(printf '\356\202\264')  # U+E0B4 right half-circle pill cap

# solid_pill BG FG TEXT  → echoes a rounded pill. The caps are the pill colour
# drawn over the default terminal bg (\033[49m) so the edges read as rounded.
solid_pill() {
    printf '\033[49m\033[38;2;%sm%s' "$1" "$CAP_L"
    printf '\033[48;2;%sm\033[38;2;%sm%s' "$1" "$2" "$3"
    printf '\033[49m\033[38;2;%sm%s\033[0m' "$1" "$CAP_R"
}

# bar_pill FILL TEXT USED_PCT  → echoes a progress-bar pill: body bg is FILL
# over the first USED_PCT% of the label, the neutral grey track over the rest.
# Each cap takes the colour of the body end it abuts.
bar_pill() {
    local fill=$1 text=$2 pct=$3
    local n=${#text}
    local f=$(( (pct * n + 50) / 100 ))
    [ "$f" -lt 0 ] && f=0
    [ "$f" -gt "$n" ] && f=$n
    local lcap=$C_SURFACE rcap=$C_SURFACE
    [ "$f" -gt 0 ]  && lcap=$fill
    [ "$f" -ge "$n" ] && rcap=$fill
    printf '\033[49m\033[38;2;%sm%s' "$lcap" "$CAP_L"
    printf '\033[48;2;%sm\033[38;2;%sm%s' "$fill"      "$C_INK" "${text:0:$f}"
    printf '\033[48;2;%sm\033[38;2;%sm%s' "$C_SURFACE" "$C_DIM" "${text:$f}"
    printf '\033[49m\033[38;2;%sm%s\033[0m' "$rcap" "$CAP_R"
}

# Tier colour for a fill bar: cool when low, hot when high.
fill_color() {  # $1=pct  → echoes the tier colour
    if   [ "$1" -lt 50 ]; then printf '%s' "$C_GREEN"
    elif [ "$1" -lt 80 ]; then printf '%s' "$C_AMBER"
    else                       printf '%s' "$C_RED"
    fi
}

# Build the line as three chunks separated by stretchy whitespace:
#   left   = cwd / git
#   middle = model / context bar / quota bars
#   right  = GPU info / compute / memory
# Within a chunk, pills are joined by a single space on the default bg. Pill
# width = body cell-length + 2 (the two caps). Visible-cell length is counted
# as `${#text}` (ASCII labels; +1 per ↑/↓ glyph in git_text).

# --- left chunk: cwd + git pills ---
left_text=""; left_w=0
body=" $cwd "
left_text+=$(solid_pill "$C_BLUE" "$C_INK" "$body"); left_w=$(( ${#body} + 2 ))
if [ -n "$git_text" ]; then
    left_text+=" "; left_w=$(( left_w + 1 ))
    left_text+=$(solid_pill "$C_GREEN" "$C_INK" "$git_text")
    left_w=$(( left_w + ${#git_text} + 2 ))
fi

# --- middle chunk: model pill + context bar + quota bars ---
mid_text=""; mid_w=0
body=" $model "
mid_text+=$(solid_pill "$C_ORANGE" "$C_INK" "$body"); mid_w=$(( ${#body} + 2 ))

if [ -n "$ctx_used" ]; then
    mid_text+=" "; mid_w=$(( mid_w + 1 ))
    mid_text+=$(bar_pill "$(fill_color "$ctx_used")" "$ctx_text" "$ctx_used")
    mid_w=$(( mid_w + ${#ctx_text} + 2 ))
fi

add_quota() {  # $1=bar text  $2=used_pct  → appends a quota bar pill to mid_text
    [ -z "$1" ] && return
    mid_text+=" "; mid_w=$(( mid_w + 1 ))
    mid_text+=$(bar_pill "$(fill_color "$2")" "$1" "$2")
    mid_w=$(( mid_w + ${#1} + 2 ))
}
add_quota "$fh_text" "${fh_used:-0}"
add_quota "$sd_text" "${sd_used:-0}"

# --- right chunk: hardware (GPU info / compute / memory) ---
right_text=""; right_w=0
add_gpu() {  # $1=bg  $2=fg  $3=text  → appends a GPU pill to right_text
    [ "$right_w" -gt 0 ] && { right_text+=" "; right_w=$(( right_w + 1 )); }
    right_text+=$(solid_pill "$1" "$2" "$3")
    right_w=$(( right_w + ${#3} + 2 ))
}
[ -n "$gpu_info_seg"    ] && add_gpu "$C_SURFACE" "$C_TEXT" "$gpu_info_seg"
[ -n "$gpu_compute_seg" ] && add_gpu "$C_TEAL"    "$C_INK"  "$gpu_compute_seg"
[ -n "$gpu_mem_seg"     ] && add_gpu "$C_STEEL"   "$C_INK"  "$gpu_mem_seg"

# Center the middle chunk on the line; left and right pads absorb the rest.
# When the right chunk is empty (no GPU), the middle still floats around the
# midpoint instead of hugging the right edge.
term_w=${COLUMNS:-100}
mid_start=$(( (term_w - mid_w) / 2 ))
left_pad=$(( mid_start - left_w ))
right_pad=$(( term_w - mid_start - mid_w - right_w ))
[ "$left_pad"  -lt 1 ] && left_pad=1
[ "$right_pad" -lt 1 ] && right_pad=1

printf '%s%*s%s%*s%s\n' \
    "$left_text" "$left_pad" '' "$mid_text" "$right_pad" '' "$right_text"
