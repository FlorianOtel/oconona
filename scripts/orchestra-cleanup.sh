#!/usr/bin/env bash
# orchestra-cleanup.sh — single-entry cleanup for /brain and /duo sessions.
#
# Usage: orchestra-cleanup.sh <session_dir> <command: brain|duo> <outcome>
#
# Owns the full end-of-session sequence in the correct order:
#   1. write .outcome (atomic)
#   2. capture .parent-snapshot-end via oc-db.py (with {} fallback)
#   3. write .cleanup-in-progress sidecar (atomic; marks cleanup active)
#   4. invoke telemetry-summarize.sh
#   5. post-verify: if telemetry.json absent, log + retry once
#   6. rm -f <session_dir>/.<command>-inflight  (clears badge; last state change)
#   7. rm -f .cleanup-in-progress sidecar (also cleaned by EXIT trap)
#
# EXIT trap removes .cleanup-in-progress sidecar if cleanup crashes before removal.
# Always exits 0 — cleanup is best-effort, never blocks the pipeline.
# Final stdout line: "cleanup ok: outcome=<outcome> telemetry=<exists|MISSING>"
#
# chmod +x me after deploy

# Do not use set -e here — we want best-effort, not abort-on-error.
set -uo pipefail

SESSION_DIR="${1:-}"
COMMAND="${2:-}"
OUTCOME="${3:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${HOME}/Gin-AI/.Gin-AI-python-3.12"

# ── Validate args ─────────────────────────────────────────────────────────────
_fail() { echo "orchestra-cleanup.sh: $*" >&2; exit 0; }

[ -n "${SESSION_DIR}" ] || _fail "session_dir required as \$1"
[ -n "${COMMAND}" ]     || _fail "command (brain|duo) required as \$2"
[ -n "${OUTCOME}" ]     || _fail "outcome required as \$3"
[ -d "${SESSION_DIR}" ] || _fail "session_dir not a directory: ${SESSION_DIR}"
case "${COMMAND}" in brain|duo) ;; *) _fail "command must be brain or duo, got: ${COMMAND}" ;; esac

INFLIGHT_MARKER="${SESSION_DIR}/.${COMMAND}-inflight"
CLEANUP_SIDECAR="${SESSION_DIR}/.cleanup-in-progress"

# ── EXIT trap: remove sidecar on crash (before any state change) ──────────────
trap 'rm -f "${CLEANUP_SIDECAR}"' EXIT

# ── Step 1: write .outcome atomically ────────────────────────────────────────
printf '%s' "${OUTCOME}" > "${SESSION_DIR}/.outcome.tmp"
mv -f "${SESSION_DIR}/.outcome.tmp" "${SESSION_DIR}/.outcome"

# ── Step 2: capture .parent-snapshot-end via oc-db.py ────────────────────────
_OC_SID=""
if [ -f "${SESSION_DIR}/.oc-session-id" ]; then
    _OC_SID="$(cat "${SESSION_DIR}/.oc-session-id" 2>/dev/null | tr -d ' \n')"
fi

if [ -n "${_OC_SID}" ] && [ -d "${VENV}" ]; then
    _SNAP_JSON=$(OC_SID="${_OC_SID}" "${VENV}/bin/python3" - 2>/dev/null <<'SNAPEOF'
import os, json, importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("oc_db", Path.home()/".config/opencode/scripts/oc-db.py")
oc_db = importlib.util.module_from_spec(spec); spec.loader.exec_module(oc_db)
snap = oc_db.get_session_snapshot(os.environ["OC_SID"])
if snap: print(json.dumps(snap))
SNAPEOF
)
    if [ -n "${_SNAP_JSON:-}" ]; then
        printf '%s\n' "${_SNAP_JSON}" > "${SESSION_DIR}/.parent-snapshot-end.tmp"
        mv -f "${SESSION_DIR}/.parent-snapshot-end.tmp" "${SESSION_DIR}/.parent-snapshot-end"
    else
        printf '{}' > "${SESSION_DIR}/.parent-snapshot-end.tmp"
        mv -f "${SESSION_DIR}/.parent-snapshot-end.tmp" "${SESSION_DIR}/.parent-snapshot-end"
    fi
fi

# ── Step 3: write .cleanup-in-progress sidecar (atomic; marks cleanup active) ─
printf 'cleanup_pid=%s\ntimestamp=%s\n' "$$" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "${CLEANUP_SIDECAR}.tmp"
mv -f "${CLEANUP_SIDECAR}.tmp" "${CLEANUP_SIDECAR}"

# ── Step 4: invoke telemetry-summarize.sh ────────────────────────────────────
_SUMMARIZE="${SCRIPT_DIR}/telemetry-summarize.sh"
_run_summarize() {
    if [ -x "${_SUMMARIZE}" ]; then
        "${_SUMMARIZE}" "${SESSION_DIR}" "${COMMAND}" "${OUTCOME}" "" 2>&1
    else
        echo "orchestra-cleanup.sh: telemetry-summarize.sh not found at ${_SUMMARIZE}" >&2
    fi
}
_run_summarize

# ── Step 5: post-verify — telemetry.json must exist ──────────────────────────
_TELEMETRY_STATUS="exists"
if [ ! -f "${SESSION_DIR}/telemetry.json" ]; then
    _TELEMETRY_STATUS="MISSING"
    {
        printf 'cleanup_warn: telemetry.json absent after first summarise attempt\n'
        printf 'timestamp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf 'outcome=%s\n' "${OUTCOME}"
        printf 'command=%s\n' "${COMMAND}"
    } > "${SESSION_DIR}/.cleanup-error"
    echo "WARN: telemetry.json missing — retrying telemetry-summarize.sh" >&2
    _run_summarize
    # Re-check after retry
    if [ -f "${SESSION_DIR}/telemetry.json" ]; then
        _TELEMETRY_STATUS="exists (retry)"
        rm -f "${SESSION_DIR}/.cleanup-error"
    fi
fi

# ── Step 6: remove inflight marker (clears badge; last state change) ──────────
rm -f "${INFLIGHT_MARKER}"

# ── Step 7: remove .cleanup-in-progress sidecar (also cleaned by EXIT trap) ──
rm -f "${CLEANUP_SIDECAR}"

# ── Final status line ─────────────────────────────────────────────────────────
echo "cleanup ok: outcome=${OUTCOME} telemetry=${_TELEMETRY_STATUS}"
