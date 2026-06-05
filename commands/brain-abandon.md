---
description: Cancel the active /brain session. Writes .outcome=abandoned, removes the inflight marker, runs T2 telemetry so the bill is bounded, and clears the status-line badge. Refuses if no active /brain session.
---

# /brain-abandon — cancel the active /brain session

You are running the **brain** pipeline's abandonment step. `/brain-abandon` cleanly closes the active /brain session without further execution: it writes `.outcome=abandoned`, removes the `.brain-inflight` marker, and runs the T2 telemetry summariser. Removing the inflight marker clears the status-line badge automatically.

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

Run the cleanup script — it owns the full sequence in the correct order:
`.outcome` → end-snapshot → inflight removal → telemetry-summarise → post-verify.

```bash
~/.config/opencode/scripts/orchestra-cleanup.sh "<SESSION_DIR>" brain abandoned
```

## Confirmation

Print to the operator:

> /brain session abandoned. Session dir: `<SESSION_DIR>` (RESEARCH.md/PLAN.md preserved for forensics; auto-removed in 30 days).

---

## What this command does NOT do

- ❌ Dispatch Planner, Actor, or Reviewer.
- ❌ Delete `RESEARCH.md`, `PLAN.md`, or any session artefacts (only `.brain-inflight` is removed).
- ❌ Auto-commit or auto-push.
