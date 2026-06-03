---
description: Cancel the active /brain session. Writes .outcome=abandoned, removes the inflight marker, runs T2 telemetry so the bill is bounded, and clears the status-line badge. Refuses if no active /brain session.
---

# /brain-abandon — cancel the active /brain session

You are running the **brain** pipeline's abandonment step. `/brain-abandon` cleanly closes the active /brain session without further execution: it writes `.outcome=abandoned`, removes the `.brain-inflight` marker, runs the T2 telemetry summariser, and clears the status-line badge in `state.env`.

If no /brain session is active (no `.brain-inflight` in any session subdir), refuse and tell the operator there's nothing to abandon.

## Prerequisites

None beyond an active /brain session. Permission mode (`ask`/`allow`/`deny`) is irrelevant — this command runs cleanup only and dispatches no subagent.

## Locate the active session

Run via `Bash`:

```bash
OPENCODE_PROJECT_DIR="$(realpath "${OPENCODE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || echo "${OPENCODE_PROJECT_DIR:-$(pwd)}")"
SESSIONS_ROOT="${HOME}/.config/opencode/orchestra/sessions"
ACTIVE_INFLIGHT=""
ACTIVE_COUNT=0
if [ -d "$SESSIONS_ROOT" ]; then
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    ACTIVE_INFLIGHT="$path"
    ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
  done < <(find "$SESSIONS_ROOT" -mindepth 2 -maxdepth 2 -name '.brain-inflight' 2>/dev/null)
fi
if [ -z "$ACTIVE_INFLIGHT" ]; then
  echo "NO_SESSION: no active /brain session to abandon."
  exit 0
fi
if [ "$ACTIVE_COUNT" -gt 1 ]; then
  echo "WARN: multiple active /brain sessions found; abandoning the first encountered."
fi
SESSION_DIR="$(dirname "$ACTIVE_INFLIGHT")"
echo "session_dir=${SESSION_DIR}"
```

If the output starts with `NO_SESSION:`, **stop now** — print the message and end.

Capture the `session_dir=...` value; use it as the literal path for the cleanup step.

## Cleanup + telemetry

Order matters: write `.outcome` **before** removing `.brain-inflight` and **before** invoking the summariser, so its mtime bounds the T2 time window correctly. `RESEARCH.md` and `PLAN.md` (if present) are left in place for forensics; the 30-day session reaper will eventually remove them.

Run via `Bash` (substitute `<SESSION_DIR>` with the literal value captured above):

```bash
printf '%s' "abandoned" > "<SESSION_DIR>/.outcome.tmp"
mv -f "<SESSION_DIR>/.outcome.tmp" "<SESSION_DIR>/.outcome"
# Snapshot OC parent cost+tokens at session end (A1 attribution).
# Runs AFTER .outcome, BEFORE telemetry-summarize.sh.
_OC_SID_FOR_SNAP=""
if [ -f "<SESSION_DIR>/.oc-session-id" ]; then
    _OC_SID_FOR_SNAP=$(cat "<SESSION_DIR>/.oc-session-id" 2>/dev/null | tr -d ' \n')
fi
if [ -n "${_OC_SID_FOR_SNAP:-}" ]; then
    _SNAP_END_JSON=$(OC_SID="$_OC_SID_FOR_SNAP" "${HOME}/Gin-AI/.Gin-AI-python-3.12/bin/python3" - 2>/dev/null <<'SNAPEOF'
import os, json, importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location("oc_db", Path.home()/".config/opencode/scripts/oc-db.py")
oc_db = importlib.util.module_from_spec(spec); spec.loader.exec_module(oc_db)
snap = oc_db.get_session_snapshot(os.environ["OC_SID"])
if snap: print(json.dumps(snap))
SNAPEOF
)
    if [ -n "${_SNAP_END_JSON:-}" ]; then
        printf '%s\n' "$_SNAP_END_JSON" > "<SESSION_DIR>/.parent-snapshot-end.tmp"
        mv -f "<SESSION_DIR>/.parent-snapshot-end.tmp" "<SESSION_DIR>/.parent-snapshot-end"
    else
        printf '{}' > "<SESSION_DIR>/.parent-snapshot-end.tmp"
        mv -f "<SESSION_DIR>/.parent-snapshot-end.tmp" "<SESSION_DIR>/.parent-snapshot-end"
    fi
fi
rm -f "<SESSION_DIR>/.brain-inflight"
~/.config/opencode/scripts/telemetry-summarize.sh \
    "<SESSION_DIR>" brain abandoned "" 2>&1 \
    | tail -n 1
```

Then clear the pipeline badge from state.env:

```bash
printf 'ORCHESTRA_MODE=default\nORCHESTRA_TITLE=\n' \
  >> "${HOME}/.config/opencode/orchestra/state.env"
```

## Confirmation

Print to the operator:

> /brain session abandoned. Session dir: `<SESSION_DIR>` (RESEARCH.md/PLAN.md preserved for forensics; auto-removed in 30 days).

---

## What this command does NOT do

- ❌ Dispatch Planner, Actor, or Reviewer.
- ❌ Delete `RESEARCH.md`, `PLAN.md`, or any session artefacts (only `.brain-inflight` is removed).
- ❌ Auto-commit or auto-push.
