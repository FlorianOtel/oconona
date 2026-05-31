#!/usr/bin/env bash
# Telemetry smoke test verifier for /duo and /brain sessions (v7.3+).
# Run after a /duo or /brain invocation to verify OC-native pipeline.
#
# Usage: ./scripts/smoke-test.sh [session_dir]
#   If session_dir is omitted, uses the most recent session under
#   ~/.config/opencode/orchestra/sessions/.

set -euo pipefail

OPENCODE_PROJECT_DIR="${OPENCODE_PROJECT_DIR:-$(pwd)}"
SESSIONS_ROOT="${HOME}/.config/opencode/orchestra/sessions"
PYTHON3="${HOME}/Gin-AI/.Gin-AI-python-3.12/bin/python3"

if [ -n "${1:-}" ]; then
    SESSION_DIR="$1"
else
    SESSION_DIR=$(ls -td "${SESSIONS_ROOT}"/*/  2>/dev/null | head -1)
    SESSION_DIR="${SESSION_DIR%/}"
fi

if [ -z "${SESSION_DIR:-}" ] || [ ! -d "${SESSION_DIR}" ]; then
    echo "ERROR: No session dir found under ${SESSIONS_ROOT}"
    echo "  Run /duo-plan (then /duo-act) or /brain first, or pass the session dir as an argument."
    exit 1
fi

SESSION_ID="${SESSION_DIR##*/}"
echo "=== Smoke test (v7.4+): ${SESSION_ID} ==="

PASS=0
TOTAL_CHECKS=5

# --- Check A: .oc-session-id sidecar ---
echo ""
echo "--- Check A (.oc-session-id sidecar) ---"
SIDECAR_FILE="${SESSION_DIR}/.oc-session-id"
if [ -f "${SIDECAR_FILE}" ] && [ -s "${SIDECAR_FILE}" ]; then
    OC_ID=$(cat "${SIDECAR_FILE}" | tr -d ' \n')
    echo "✓ .oc-session-id found: ${OC_ID}"
    PASS=$((PASS + 1))
else
    echo "✗ .oc-session-id missing or empty"
    echo "  Session setup did not write .oc-session-id (pre-v7.2 session dir?)"
fi

# --- Check B: OC DB row + child count ---
echo ""
echo "--- Check B (OC DB row + child count) ---"
if [ -n "${OC_ID:-}" ]; then
    "${PYTHON3}" - <<PYEOF
import importlib.util
import sys
from pathlib import Path

# oc-db.py uses a hyphen (project naming convention); Python's import
# statement can't load it. Use importlib.util.spec_from_file_location
# like scripts/telemetry-summarize.py does.
_db_path = Path.home() / ".config/opencode/scripts/oc-db.py"
if not _db_path.exists():
    print(f"✗ oc-db.py not found at {_db_path}")
    sys.exit(1)
spec = importlib.util.spec_from_file_location("oc_db", _db_path)
oc_db = importlib.util.module_from_spec(spec)
spec.loader.exec_module(oc_db)

oc_id = "${OC_ID}"
try:
    row = oc_db.get_session(oc_id)
    if row is None:
        print(f"✗ OC DB row not found for {oc_id}")
        sys.exit(1)
    children = oc_db.get_child_sessions(oc_id)
    print(f"✓ parent row found; {len(children)} child session(s)")
    sys.exit(0)
except Exception as e:
    print(f"✗ Error querying OC DB: {e}")
    sys.exit(1)
PYEOF
    if [ $? -eq 0 ]; then
        PASS=$((PASS + 1))
    fi
else
    echo "✗ OC_ID not set (Check A failed)"
fi

# --- Check C: telemetry.json with cost ---
echo ""
echo "--- Check C (telemetry.json with cost) ---"
T_FILE="${SESSION_DIR}/telemetry.json"
if [ -f "${T_FILE}" ]; then
    echo "✓ telemetry.json found"
    "${PYTHON3}" - <<PYEOF
import json, sys
try:
    with open("${T_FILE}") as f:
        d = json.load(f)
    cost_usd = d.get("totals", {}).get("cost_usd_estimate", 0)
    cost_source = d.get("cost_source", "")
    _t = d.get("totals", {})
    total_tokens = (_t.get("tokens_input", 0) + _t.get("tokens_output", 0)
                    + _t.get("tokens_cache_read", 0) + _t.get("tokens_cache_write", 0))

    print(f"  cost_usd_estimate: \${cost_usd:.4f}")
    print(f"  cost_source:       {cost_source}")
    print(f"  total_tokens:      {total_tokens}")

    # Accept cost == 0 if cost_source == "oc_sqlite" (flat-rate models)
    if cost_source != "oc_sqlite":
        print("✗ cost_source should be 'oc_sqlite' (v7.3+)")
        sys.exit(1)

    print("✓ telemetry.json valid (v7.3+ format)")
    sys.exit(0)
except Exception as e:
    print(f"✗ Error reading telemetry.json: {e}")
    sys.exit(1)
PYEOF
    if [ $? -eq 0 ]; then
        PASS=$((PASS + 1))
    fi
else
    echo "✗ telemetry.json not found"
    echo "  Telemetry pass may not have completed. Check status-line or run manually:"
    echo "  ~/.config/opencode/scripts/telemetry-summarize.sh \"${SESSION_DIR}\" duo pass \"\""
fi

# --- Check D: model rates validation ---
echo ""
echo "--- Check D (model rates within 1% tolerance) ---"
VERIFY_SCRIPT="${HOME}/.config/opencode/scripts/verify-cost-rates.py"
if [ -f "${VERIFY_SCRIPT}" ]; then
    "${PYTHON3}" "${VERIFY_SCRIPT}" "${SESSION_DIR}" 2>&1 | grep -E "^  (OK|WARN|STALE):" | head -10
    if "${PYTHON3}" "${VERIFY_SCRIPT}" "${SESSION_DIR}" >/dev/null 2>&1; then
        echo "✓ All known-model rates within 1% of OC stored cost"
        PASS=$((PASS + 1))
    else
        echo "✗ At least one tier has rate drift > 1%"
    fi
else
    echo "⊘ verify-cost-rates.py not deployed (pre-v7.3.5); skipping"
fi

# --- Check E: tier-mapping drift detector ---
echo ""
echo "--- Check E (tier-mapping matches docs/design.md) ---"
VERIFY_SCRIPT="${HOME}/.config/opencode/scripts/verify-tier-mapping.sh"
if [ ! -f "${VERIFY_SCRIPT}" ]; then
    # Fall back to repo-relative when smoke-test runs from the repo
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VERIFY_SCRIPT="${SCRIPT_DIR}/verify-tier-mapping.sh"
fi
DESIGN_MD=""
for candidate in \
    "${OPENCODE_PROJECT_DIR:-$(pwd)}/docs/design.md" \
    "$(pwd)/docs/design.md" \
    "$(dirname "${VERIFY_SCRIPT}")/../docs/design.md"; do
    if [ -f "${candidate}" ]; then
        DESIGN_MD="${candidate}"
        break
    fi
done

if [ -x "${VERIFY_SCRIPT}" ] && [ -n "${DESIGN_MD}" ]; then
    # Get current mapping from verify-tier-mapping.sh (tab-separated: tier<TAB>model)
    CURRENT=$("${VERIFY_SCRIPT}")

    # Extract expected mapping from docs/design.md `### Agents` table
    # The table has rows like:
    # | **Planner** | `sohoai/glm-5.1` | ... |
    # | **Actor** | `sohoai/qwen3-coder-next` | ... |
    # | **Actor** (heavy) | `sohoai/kimi-k2.6` | ... |
    # | **Reviewer** | `anthropic/claude-sonnet-4-6` (v7.3.5+) | ... |
    EXPECTED=$(awk '
        /^### Agents$/ { in_agents = 1; next }
        in_agents && /^### / { in_agents = 0 }
        in_agents && /^\| \*\*/ {
            # Strip leading | and **, get the tier name and model
            line = $0
            sub(/^\| \*\*/, "", line)
            # Tier name ends at the next **
            tier_end = index(line, "**")
            tier = substr(line, 1, tier_end - 1)
            rest = substr(line, tier_end + 2)
            # Find model in backticks in next column
            if (match(rest, /\| `[^`]+`/)) {
                model = substr(rest, RSTART + 3, RLENGTH - 4)
                # Normalize tier name to lowercase + "actor-heavy" for "Actor (heavy)"
                if (tier == "Actor") {
                    if (match(rest, /\(heavy\)/)) tier_norm = "actor-heavy"
                    else tier_norm = "actor"
                } else {
                    tier_norm = tolower(tier)
                }
                # Skip "Brain" — not in verify-tier-mapping.sh output
                if (tier_norm != "brain") print tier_norm "\t" model
            }
        }
    ' "${DESIGN_MD}")

    # Compare: every CURRENT line must match an EXPECTED line
    MISMATCH=0
    while IFS=$'\t' read -r tier model; do
        [ -z "$tier" ] && continue
        exp_line=$(echo "$EXPECTED" | awk -F'\t' -v t="$tier" '$1 == t { print $2 }')
        if [ -z "$exp_line" ]; then
            echo "✗ tier '${tier}' present in agents/ but missing from docs/design.md"
            MISMATCH=1
        elif [ "$exp_line" != "$model" ]; then
            echo "✗ tier '${tier}' drift: agents/=${model}  vs  design.md=${exp_line}"
            MISMATCH=1
        fi
    done <<< "${CURRENT}"

    if [ "${MISMATCH}" -eq 0 ]; then
        echo "✓ Tier-to-model mapping matches docs/design.md (4 tiers)"
        PASS=$((PASS + 1))
    fi
else
    echo "⊘ verify-tier-mapping.sh or docs/design.md not found; skipping Check E"
fi

# --- Summary ---
echo ""
if [ "${PASS}" -eq "${TOTAL_CHECKS}" ]; then
    echo "✓ All checks passed (${TOTAL_CHECKS}/${TOTAL_CHECKS})"
    exit 0
else
    echo "✗ ${PASS}/${TOTAL_CHECKS} checks passed"
    exit 1
fi
