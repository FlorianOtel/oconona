#!/usr/bin/env bash
# telemetry-summarize.sh — wrapper that activates the project venv and runs the Python parser.
# Usage: telemetry-summarize.sh <session_dir> <command> <outcome> [transcript_session_id]
#
# Designed to be invoked from /duo-act and /duo-abandon cleanup, /brain Phase 3
# cleanup, and orchestra-hook.sh stop mode.
#
# chmod +x me after deploy

set -uo pipefail

VENV="${HOME}/Gin-AI/.Gin-AI-python-3.12"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="${SCRIPT_DIR}/telemetry-summarize.py"

if [ ! -d "$VENV" ]; then
    echo "telemetry-summarize.sh: venv not found at $VENV — skipping" >&2
    exit 0
fi

if [ ! -f "$PY_SCRIPT" ]; then
    echo "telemetry-summarize.sh: parser not found at $PY_SCRIPT — skipping" >&2
    exit 0
fi

if [ $# -lt 3 ]; then
    echo "Usage: telemetry-summarize.sh <session_dir> <command> <outcome> [transcript_id]" >&2
    exit 1
fi

"${VENV}/bin/python3" "$PY_SCRIPT" "$1" "$2" "$3" "${4:-}" "${@:5}"
