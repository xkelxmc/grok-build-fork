#!/bin/bash
# One-line Grok status. Context bar matches ~/.claude/statusline.sh 1:1.
# Live path: ~/.grok/statusline.sh -> this file.
#
# Grok re-runs this every 300ms during a turn and never cancels a run already
# going, so anything spawned here is the delay of the context number. One jq,
# no bc, cached node -v.
set -f
input=$(cat)

# Copied from claude-code-statusline/statusline.sh — do not restyle.
progress_bar() {
    local pct=$1
    local width=${2:-20}
    local filled=$((pct * width / 100))
    local empty=$((width - filled))

    if [ "$pct" -lt 20 ]; then
        bar_color="\033[90m"  # gray
    elif [ "$pct" -lt 50 ]; then
        bar_color="\033[97m"  # white
    elif [ "$pct" -lt 75 ]; then
        bar_color="\033[33m"  # yellow
    elif [ "$pct" -lt 85 ]; then
        bar_color="\033[38;5;208m"  # orange
    else
        bar_color="\033[31m"  # red
    fi

    local bar="${bar_color}"
    for ((i=0; i<filled; i++)); do bar+="▰"; done
    bar+="\033[90m"
    for ((i=0; i<empty; i++)); do bar+="▱"; done
    bar+="\033[0m"

    echo "$bar"
}

eval "$(printf '%s\n' "$input" | jq -r '
  "cwd=\(.workspace.repo_root // .workspace.current_dir // .cwd // "" | @sh)",
  "ctx_tokens=\((.context_window.context_tokens // "") | @sh)",
  "ctx_size=\((.context_window.context_window_size // "") | @sh)",
  "used_pct_raw=\((.context_window.used_percentage // "") | @sh)"
')"

used_pct=0
if [ -n "$ctx_tokens" ] && [ -n "$ctx_size" ] && [ "$ctx_size" -gt 0 ]; then
    used_pct=$((ctx_tokens * 100 / ctx_size))
    [ "$used_pct" -gt 100 ] && used_pct=100
elif [ -n "$used_pct_raw" ]; then
    used_pct=${used_pct_raw%.*}
    [ -z "$used_pct" ] && used_pct=0
fi

pkg_manager=""
if [ -f "$cwd/bun.lockb" ] || [ -f "$cwd/bun.lock" ]; then
    pkg_manager="bun"
elif [ -f "$cwd/pnpm-lock.yaml" ]; then
    pkg_manager="pnpm"
elif [ -f "$cwd/yarn.lock" ]; then
    pkg_manager="yarn"
elif [ -f "$cwd/package-lock.json" ]; then
    pkg_manager="npm"
fi

node_ver=""
node_cache="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}/grok-statusline-node-ver"
if [ -f "$node_cache" ]; then
    node_ver=$(cat "$node_cache")
elif command -v node >/dev/null 2>&1; then
    node_ver=$(node -v)
    mkdir -p "$(dirname "$node_cache")"
    printf '%s\n' "$node_ver" >"$node_cache"
fi

parts=()
[ -n "$pkg_manager" ] && parts+=("📦 $pkg_manager")
[ -n "$node_ver" ] && parts+=("⬢ \033[90m${node_ver}\033[0m")

if [ "$used_pct" -gt 0 ] || { [ -n "$ctx_tokens" ] && [ "$ctx_tokens" -gt 0 ]; }; then
    if [ -n "$ctx_tokens" ] && [ "$ctx_tokens" -ge 1000 ]; then
        tokens_fmt="$((ctx_tokens / 1000)).$(( (ctx_tokens % 1000) / 100 ))k"
    elif [ -n "$ctx_tokens" ]; then
        tokens_fmt=$ctx_tokens
    else
        tokens_fmt="?"
    fi
    bar=$(progress_bar "$used_pct" 20)
    parts+=("🧠 ${bar_color}${used_pct}%\033[0m $(printf '%b' "$bar") ${bar_color}${tokens_fmt}\033[0m")
fi

out=""
for i in "${!parts[@]}"; do
    if [ "$i" -eq 0 ]; then
        out="${parts[$i]}"
    else
        out="${out} ${parts[$i]}"
    fi
done

printf '%b\n' "$out"
exit 0
