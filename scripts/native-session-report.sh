#!/usr/bin/env bash
# native-session-report.sh — cost report for OC sessions NOT orchestra-wrapped.
#
# Usage:
#   native-session-report.sh [--last N] [--since YYYY-MM-DD] [--month YYYY-MM]
#                            [--project PATH] [--min-cost X] [--json]
#                            [--exclude-orchestra]
#
# Invokes the venv-wrapped Python implementation.

set -uo pipefail

# Python venv location differs per platform: Linux keeps it under ~/Gin-AI,
# macOS under ~/.python-3.12. Keep this block identical across all files that use it.
case "$(uname -s)" in
    Darwin) PYVENV="$HOME/.python-3.12" ;;
    *)      PYVENV="$HOME/Gin-AI/.Gin-AI-python-3.12" ;;
esac
VENV="$PYVENV"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_SCRIPT="${SCRIPT_DIR}/native-session-report.py"

if [ ! -d "$VENV" ]; then
    echo "native-session-report.sh: venv not found at $VENV" >&2
    exit 1
fi

if [ ! -f "$PY_SCRIPT" ]; then
    echo "native-session-report.sh: parser not found at $PY_SCRIPT" >&2
    exit 1
fi

"${VENV}/bin/python3" "$PY_SCRIPT" "$@"
