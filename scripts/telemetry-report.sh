#!/usr/bin/env bash
# telemetry-report.sh — on-demand summary of recent telemetry sessions (v7.1+).
#
# Usage:
#   telemetry-report.sh [--last N] [--tier]
#
#   --last N   Show the last N sessions (default 20).
#   --tier     Show per-tier cost breakdown (Brain / Planner / Actor / Reviewer).
#              Reads per-session telemetry.json directly from sessions/ dir.
#
# chmod +x me after deploy

set -uo pipefail

# --- arg parsing ---
LAST_N=20
SHOW_TIER=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --last)    LAST_N="${2:-20}"; shift 2 ;;
        --tier)    SHOW_TIER=true;    shift   ;;
        [0-9]*)    LAST_N="$1";       shift   ;;
        *)         shift ;;
    esac
done

SESSIONS_ROOT="${HOME}/.config/opencode/orchestra/sessions"
PYTHON3="${HOME}/Gin-AI/.Gin-AI-python-3.12/bin/python3"

if [ ! -d "$SESSIONS_ROOT" ] || [ -z "$(find "$SESSIONS_ROOT" -maxdepth 2 -name "telemetry.json" 2>/dev/null | head -1)" ]; then
    echo "(no telemetry yet — run /duo-plan (then /duo-act) or /brain first)"
    exit 0
fi

if ! command -v jq &> /dev/null; then
    echo "jq required — install it first"
    exit 1
fi

# =============================================================================
# --tier mode: per-tier cost breakdown from individual telemetry.json files
# =============================================================================
if $SHOW_TIER; then
    echo "Per-tier cost breakdown"
    echo ""

    # Write Python script to temp file
    TIER_PY=$(mktemp /tmp/telemetry-tier-XXXXXX.py)
    CUMUL_PY=$(mktemp /tmp/telemetry-cumul-XXXXXX.py)
    trap 'rm -f "$TIER_PY" "$CUMUL_PY"' EXIT

    cat > "$TIER_PY" << 'PYEOF'
import json, re, sys
from pathlib import Path

tf = Path(sys.argv[1])

t = json.load(tf.open())

def norm(m): return re.sub(r"-\d{8}$", "", m or "")

# Extract cost from totals (cost pre-computed in v7.1+)
ORDER = {"brain": 0, "planner": 1, "actor": 2, "reviewer": 3}
tiers = [("brain", t["parent"]["model"], t["parent"]["tokens"], t["parent"].get("cost", 0))]
for s in t.get("subagents", []):
    tiers.append((s["type"], s.get("model", "?"), s["tokens"], s.get("cost", 0)))
tiers.sort(key=lambda x: ORDER.get(x[0], 4))

grand_tok  = sum(sum(tok.values()) for _, _, tok, _ in tiers)
grand_cost = sum(c for _, _, _, c in tiers)

date = t["started_at"][:16].replace("T", "--")
dur  = t.get("duration_s", 0)
print(f"  {date}  {t['command']:<6}  {dur}s  outcome={t['outcome']:<10}  total=${grand_cost:.4f}")
print(f"    {'Tier':<12} {'Model':<22} {'Tokens':>10}  {'%tok':>5}  {'Cost':>8}  {'%cost':>6}")
print(f"    {'-'*64}")
for tier, model, tok, cost_val in tiers:
    t_ = sum(tok.values())
    pct_tok  = t_ / grand_tok  * 100 if grand_tok  else 0
    pct_cost = cost_val / grand_cost * 100 if grand_cost else 0
    print(f"    {tier:<12} {norm(model):<22} {t_:>10,}  {pct_tok:>4.1f}%  ${cost_val:>7.4f}  {pct_cost:>5.1f}%")
print(f"    {'-'*64}")
print(f"    {'TOTAL':<12} {'':<22} {grand_tok:>10,}         ${grand_cost:>7.4f}")

reported = t.get("totals", {}).get("cost_usd_estimate", 0)
if abs(grand_cost - reported) > 0.001:
    print(f"    (totals reported: ${reported:.4f} — delta ${grand_cost - reported:+.4f})")
print()
PYEOF

    # Cumulative analysis: aggregate tokens+cost by (tier, model) across all sessions.
    cat > "$CUMUL_PY" << 'PYEOF'
import json, re, sys
from pathlib import Path
from collections import defaultdict

tf_paths = sys.argv[1:]

def norm(m): return re.sub(r"-\d{8}$", "", m or "")

accum = defaultdict(lambda: {"tokens": defaultdict(int), "cost": 0.0})
n = 0
for tf_path in tf_paths:
    try:
        t = json.load(open(tf_path))
    except Exception:
        continue
    n += 1
    key = ("brain", norm(t["parent"]["model"]))
    for k, v in t["parent"]["tokens"].items():
        accum[key]["tokens"][k] += v
    accum[key]["cost"] += t["parent"].get("cost", 0)
    for s in t.get("subagents", []):
        key = (s["type"], norm(s.get("model", "?")))
        for k, v in s["tokens"].items():
            accum[key]["tokens"][k] += v
        accum[key]["cost"] += s.get("cost", 0)

if n == 0:
    sys.exit(0)

ORDER = {"brain": 0, "planner": 1, "actor": 2, "reviewer": 3}
items = sorted(accum.items(), key=lambda x: ORDER.get(x[0][0], 4))
grand_tok  = sum(sum(v["tokens"].values()) for _, v in items)
grand_cost = sum(v["cost"]                 for _, v in items)

print(f"--- Cumulative totals ({n} session(s)) ---")
print(f"  {'Tier':<12} {'Model':<22} {'Tokens':>12}  {'%tok':>5}  {'Cost':>9}  {'%cost':>6}")
print(f"  {'-'*68}")
for (tier, model), v in items:
    t_ = sum(v["tokens"].values()); c = v["cost"]
    print(f"  {tier:<12} {model:<22} {t_:>12,}  {t_/grand_tok*100:>4.1f}%  ${c:>8.4f}  {c/grand_cost*100:>5.1f}%")
print(f"  {'-'*68}")
print(f"  {'TOTAL':<12} {'':<22} {grand_tok:>12,}          ${grand_cost:>8.4f}")
PYEOF

    # Process each session (most recent LAST_N first)
    VALID_TFS=()
    while IFS= read -r TF; do
        if [ -f "$TF" ]; then
            VALID_TFS+=("$TF")
            "${PYTHON3}" "$TIER_PY" "$TF"
        fi
    done < <(find "$SESSIONS_ROOT" -maxdepth 2 -name "telemetry.json" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -rn | head -n "$LAST_N" | awk '{print $NF}')

    # Cumulative summary across all sessions
    if [ ${#VALID_TFS[@]} -gt 0 ]; then
        "${PYTHON3}" "$CUMUL_PY" "${VALID_TFS[@]}"
    fi

# =============================================================================
# default mode: tabular session summary
# =============================================================================
else
    {
        printf "Date\tCommand\tOutcome\tCost\tSource\tTokens\tDuration\tNote\n"
        find "$SESSIONS_ROOT" -maxdepth 2 -name "telemetry.json" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -rn | head -n "$LAST_N" | awk '{print $NF}' | while read TF; do
            [ -f "$TF" ] && cat "$TF"
        done | "${PYTHON3}" - <<'PYEOF'
import json, sys
for line in sys.stdin:
    try:
        t = json.loads(line)
        date = t["started_at"][:16].replace("T", "--")
        cmd = t.get("command", "?")
        outcome = t.get("outcome", "?")
        cost = t.get("totals", {}).get("cost_usd_estimate", 0)
        cost_source = t.get("cost_source", "-")
        total_tokens = t.get("totals", {}).get("tokens_input", 0) + t.get("totals", {}).get("tokens_output", 0)
        duration = t.get("duration_s", 0)
        note = ""
        print(f"{date}\t{cmd}\t{outcome}\t${cost:.4f}\t{cost_source}\t{total_tokens}\t{duration}s\t{note}")
    except Exception:
        pass
PYEOF
    } | column -t -s$'\t' 2>/dev/null || echo "Failed to format output"
fi

# =============================================================================
# aggregates (always shown)
# =============================================================================
echo ""
echo "--- Aggregates (last $LAST_N sessions) ---"
find "$SESSIONS_ROOT" -maxdepth 2 -name "telemetry.json" -type f -exec stat -c "%Y %n" {} \; 2>/dev/null | sort -rn | head -n "$LAST_N" | awk '{print $NF}' | while read TF; do
    [ -f "$TF" ] && cat "$TF"
done | "${PYTHON3}" - <<'PYEOF'
import json, sys
from collections import defaultdict

sessions = []
for line in sys.stdin:
    try:
        t = json.loads(line)
        sessions.append(t)
    except Exception:
        pass

if not sessions:
    sys.exit(0)

total_cost = sum(t.get("totals", {}).get("cost_usd_estimate", 0) for t in sessions)
total_tokens = sum(t.get("totals", {}).get("tokens_input", 0) + t.get("totals", {}).get("tokens_output", 0) for t in sessions)
mean_cost = total_cost / len(sessions) if sessions else 0

by_cmd = defaultdict(lambda: {"count": 0, "cost": 0})
for t in sessions:
    cmd = t.get("command", "?")
    by_cmd[cmd]["count"] += 1
    by_cmd[cmd]["cost"] += t.get("totals", {}).get("cost_usd_estimate", 0)

print(f"Sessions       : {len(sessions)}")
print(f"Total cost     : ${total_cost:.4f}")
print(f"Total tokens   : {total_tokens:,}")
print(f"Mean cost      : ${mean_cost:.4f}")
print(f"By command     :")
for cmd in sorted(by_cmd.keys()):
    v = by_cmd[cmd]
    print(f"  {cmd:<8} : {v['count']:>3} session(s), ${v['cost']:.4f}")
PYEOF
