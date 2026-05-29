#!/usr/bin/env bash
# orchestra-block.sh — status-line additions for OpenCode Orchestra (subagents)
#
# USAGE: deploy.sh injects this block into ~/.config/opencode/scripts/status-line.sh
# just before the final `echo -e "$status_line"` line.
#
# Prerequisites — the host script must already have:
#   - $cwd          (from: cwd=$(echo "$input" | jq -r '.workspace.current_dir'))
#   - $tokens_used  (from your existing token-usage calculation)
#   - $status_line  (the running status string to append to)
#   - $RESET        (ANSI reset code)
#   - $input        (JSON for model_id extraction via jq)
#   - $used_percentage (Ctx segment: fill percentage 0-100)
#   - $context_window_size (Ctx segment: model's context window in tokens)

# ORCHESTRA_BLOCK_START — do not remove; deploy.sh uses this as presence sentinel

if [ -n "$cwd" ] && [ -f "$HOME/.config/opencode/orchestra/config.yaml" ]; then
    # Gruvbox Dark palette additions
    ORCHESTRA_COLOR="\033[38;2;211;134;155m"  # bright_purple #D3869B
    ACTIVE_COLOR="\033[38;2;215;153;33m"      # dark yellow   #D79921
    WARNING_COLOR="\033[38;2;254;128;25m"     # bright_orange #FE8019

    # Strip OC-native fields 2 (20-seg bar+%) and 3 (↯ token count) — replaced by ctx+cost below.
    # Field 2: $bar is passed via %s arg to printf so BRACKET_COLOR stays as literal \033 (4 chars),
    # NOT a raw ESC byte. Use \\\\033 so bash→\\033, sed sees \\033 and matches literal \033.
    # PERCENTAGE_COLOR and RESET are in the format string → raw ESC → ${_ESC} anchor for the end.
    # Field 3: TOKEN_COLOR is in the format string → raw ESC → ${_ESC} anchor works directly.
    _ESC=$'\033'
    status_line=$(printf '%s' "$status_line" \
        | sed "s/ | \\\\033\[38;2;102;92;84m\[.*${_ESC}\[38;2;251;241;199m[0-9]*%${_ESC}\[0m//")
    status_line=$(printf '%s' "$status_line" \
        | sed "s/ | ${_ESC}\[38;2;224;175;104m[^${_ESC}]*${_ESC}\[0m//")

    # --- /brain badge: read mode+title from state.env ---
    state_env="$HOME/.config/opencode/orchestra/state.env"
    orch_mode="orchestra"
    orch_title=""
    if [ -f "$state_env" ]; then
        _om=$(grep '^ORCHESTRA_MODE=' "$state_env" 2>/dev/null | tail -n 1 | cut -d= -f2-)
        _ot=$(grep '^ORCHESTRA_TITLE=' "$state_env" 2>/dev/null | tail -n 1 | cut -d= -f2-)
        [ -n "$_om" ] && [ "$_om" != "default" ] && orch_mode="$_om"
        orch_title="$_ot"
    fi

    # --- /duo badge: count .duo-inflight markers across session dirs ---
    duo_count=0
    duo_title=""
    sessions_root="$HOME/.config/opencode/orchestra/sessions"
    if [ -d "$sessions_root" ]; then
        duo_count=$(find "$sessions_root" -maxdepth 2 -name ".duo-inflight" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$duo_count" -eq 1 ]; then
            duo_title=$(find "$sessions_root" -maxdepth 2 -name ".duo-inflight" 2>/dev/null \
                        -exec cat {} \; 2>/dev/null | head -c 30)
        fi
    fi

    # --- active-subagent indicator ---
    invlog="$HOME/.config/opencode/orchestra/invocations.log"
    active_indicator=""
    if [ -f "$invlog" ]; then
        last_start_line=$(grep '"event":"start"' "$invlog" 2>/dev/null | tail -n 1)
        last_end_line=$(grep   '"event":"end"'   "$invlog" 2>/dev/null | tail -n 1)
        if [ -n "$last_start_line" ]; then
            IFS=$'\t' read -r last_start_ts active_stage active_subagent < <(
                echo "$last_start_line" | jq -r '[.ts // "", .stage // "", .subagent // ""] | @tsv'
            )
            last_end_ts=$(echo "$last_end_line" | jq -r '.ts // ""')
            if [ -n "$last_start_ts" ] && [ "$last_start_ts" \> "${last_end_ts:-}" ]; then
                active_indicator=$(printf "${ACTIVE_COLOR}▶ %s${RESET}" "$active_stage")
            fi
        fi
    fi

    # --- ctx segment (model context window + token usage bar) ---
    # Self-fix: host status-line.sh may set tokens_used=0 when used_percentage=0
    # (OC reports 0% usage for non-Anthropic models even when tokens were consumed).
    # Fallback: derive tokens_used from total_input + total_output; then derive
    # used_percentage from tokens / context_window.
    _total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
    _total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
    _total=$((_total_input + _total_output))
    if { [ "$used_percentage" = "0" ] || [ "$used_percentage" = "null" ]; } && [ "$_total" -gt 0 ]; then
        tokens_used="$_total"
        if [ "$context_window_size" -gt 0 ]; then
            used_percentage=$(echo "scale=2; 100 * $_total / $context_window_size" | bc)
        fi
    fi
    # Round to integer — ctx-segment.sh validates used_percentage with ^[0-9]+$ (integers only)
    used_percentage=$(printf "%.0f" "$used_percentage")
    model_id=$(echo "$input" | jq -r '.model.id // .model.display_name // ""' 2>/dev/null)

    ctx_seg=$(~/.config/opencode/scripts/ctx-segment.sh "${used_percentage:-0}" "${tokens_used:-0}" "${context_window_size:-200000}" "${model_id:-}" 2>/dev/null || true)

    # --- live cost (v7.3: OC SQLite direct via oc-db.py) ---
    live_cost=""
    _json_sid=$(echo "$input" | jq -r '.session_id // ""' 2>/dev/null)
    if [ -n "$_json_sid" ]; then
        _cost=$(OC_SID="$_json_sid" "${HOME}/Gin-AI/.Gin-AI-python-3.12/bin/python3" - <<'PYEOF' 2>/dev/null || echo ""
import os, sys
from pathlib import Path
sys.path.insert(0, str(Path.home() / ".config/opencode/scripts"))
import oc_db
try:
    t = oc_db.get_session_telemetry(os.environ["OC_SID"])
    print(f"{t['totals']['cost_usd_estimate']:.4f}")
except Exception:
    print("")
PYEOF
)
        if printf '%s' "$_cost" | grep -qE '^[0-9]+\.?[0-9]*$'; then
            live_cost=$(LC_ALL=C printf 'Σ$%.2f' "$_cost" 2>/dev/null || true)
        fi
    fi

    # Insert ctx+cost at position 2: right after model field, before project/branch.
    # ${var/ | / | INSERT | } replaces only the FIRST ' | ' separator in $status_line.
    _insert=""
    [ -n "$ctx_seg"   ] && _insert="${ctx_seg}"
    [ -n "$live_cost" ] && { [ -n "$_insert" ] && _insert+=" | ${live_cost}" || _insert="${live_cost}"; }
    [ -n "$_insert"   ] && status_line="${status_line/ | / | ${_insert} | }"

    # --- badge rendering (priority: duo > brain > plain subagent) ---
    if [ "$duo_count" -gt 0 ]; then
        if [ "$duo_count" -eq 1 ]; then
            duo_badge="orchestra -> plan ${duo_title}"
        else
            duo_badge="orchestra -> plan #${duo_count}"
        fi
        if [ -n "$active_indicator" ]; then
            status_line+=$(printf " | ${ORCHESTRA_COLOR}♪ %s${RESET} %s" "$duo_badge" "$active_indicator")
        else
            status_line+=$(printf " | ${ORCHESTRA_COLOR}♪ %s${RESET}" "$duo_badge")
        fi
    elif [ -n "$orch_title" ]; then
        badge="orchestra -> brain ${orch_title}"
        if [ -n "$active_indicator" ]; then
            status_line+=$(printf " | ${ORCHESTRA_COLOR}♪ %s${RESET} %s" "$badge" "$active_indicator")
        else
            status_line+=$(printf " | ${ORCHESTRA_COLOR}♪ %s${RESET}" "$badge")
        fi
    elif [ -n "$active_indicator" ]; then
        status_line+=$(printf " | ${ORCHESTRA_COLOR}♪ orchestra${RESET} %s" "$active_indicator")
    fi
fi

# ORCHESTRA_BLOCK_END
