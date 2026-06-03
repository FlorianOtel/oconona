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
echo "=== Smoke test (v7.5+): ${SESSION_ID} ==="

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

# --- Check E: parent snapshot sidecars (v7.5+) ---
echo ""
echo "--- Check E (parent snapshot sidecars) ---"
SNAP_START="${SESSION_DIR}/.parent-snapshot-start"
SNAP_END="${SESSION_DIR}/.parent-snapshot-end"

# Pre-v7.5 sessions may not have snapshots; gracefully skip
if [ ! -f "${SNAP_START}" ] && [ ! -f "${SNAP_END}" ]; then
    echo "⊘ (pre-v7.5 session; snapshot sidecars absent — skipping)"
    PASS=$((PASS + 1))
else
    exit_code=0

    # Check both files exist
    if [ ! -f "${SNAP_START}" ]; then
        echo "✗ .parent-snapshot-start missing"
        exit_code=1
    fi
    if [ ! -f "${SNAP_END}" ]; then
        echo "✗ .parent-snapshot-end missing"
        exit_code=1
    fi

    # Validate both are valid JSON
    if [ $exit_code -eq 0 ]; then
        "${PYTHON3}" - <<PYEOF
import json, sys
snap_start_valid = True
snap_end_valid = True
snap_start_cost = 0
snap_end_cost = 0

try:
    with open("${SNAP_START}") as f:
        snap_start = json.load(f)
        snap_start_cost = snap_start.get("cost", 0)
except Exception as e:
    print(f"✗ .parent-snapshot-start invalid JSON: {e}")
    snap_start_valid = False

try:
    with open("${SNAP_END}") as f:
        snap_end = json.load(f)
        snap_end_cost = snap_end.get("cost", 0)
except Exception as e:
    print(f"✗ .parent-snapshot-end invalid JSON: {e}")
    snap_end_valid = False

if snap_start_valid and snap_end_valid:
    # Both snapshots must have cost field or be {}
    has_start_cost = "cost" in snap_start or snap_start == {}
    has_end_cost = "cost" in snap_end or snap_end == {}

    if not has_start_cost:
        print("✗ .parent-snapshot-start missing 'cost' field")
        sys.exit(1)
    if not has_end_cost:
        print("✗ .parent-snapshot-end missing 'cost' field")
        sys.exit(1)

    # Sanity check: end cost >= start cost (if both non-empty)
    if snap_start and snap_end and snap_end_cost < snap_start_cost:
        print(f"⚠ end cost (\${snap_end_cost:.4f}) < start cost (\${snap_start_cost:.4f}) — unusual but not fatal")

    print("✓ .parent-snapshot-start and .parent-snapshot-end valid JSON")
    sys.exit(0)
else:
    sys.exit(1)
PYEOF
        exit_code=$?
    fi

    if [ $exit_code -eq 0 ]; then
        PASS=$((PASS + 1))
    fi
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
