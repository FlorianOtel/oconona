#!/usr/bin/env bash
# session-report.sh — unified cost report: native + orchestra sessions.
# Usage: session-report.sh [--last N] [--since DATE] [--month YYYY-MM] [--source native|orchestra|all]

set -uo pipefail

# Python venv location differs per platform: Linux keeps it under ~/Gin-AI,
# macOS under ~/.python-3.12. Keep this block identical across all files that use it.
case "$(uname -s)" in
    Darwin) PYVENV="$HOME/.python-3.12" ;;
    *)      PYVENV="$HOME/Gin-AI/.Gin-AI-python-3.12" ;;
esac
VENV="$PYVENV"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="${SCRIPT_DIR}/session-report.py"

if [ ! -d "$VENV" ]; then
    echo "session-report.sh: venv not found at $VENV" >&2
    exit 1
fi

if [ ! -f "$PY_SCRIPT" ]; then
    echo "session-report.sh: script not found at $PY_SCRIPT" >&2
    exit 1
fi

"${VENV}/bin/python3" "$PY_SCRIPT" "$@"
