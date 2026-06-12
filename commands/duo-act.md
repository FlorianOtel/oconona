---
description: Commit the active /duo plan and execute — the /duo-act invocation itself is the approval signal. Dispatches Actor immediately; any text after /duo-act is treated as a last-minute plan amendment. Refuses if no active /duo session.
---

# /duo-act — commit the active /duo plan and execute

You are running the **duo** pipeline's commit-and-execute step. `/duo-act` finalises the active /duo planning session: the invocation itself is the approval signal. Read `PLAN.md`, apply any inline amendments (text after `/duo-act`), dispatch the Actor subagent, then run cleanup + telemetry.

If no /duo session is active (no `.duo-inflight` in any session subdir), refuse and tell the operator to run `/duo-plan` first.

## Prerequisites

1. **Permission mode.** octmux's permission mode (Shift-TAB cycles `ask` / `allow` / `deny`) determines how Actor's tool calls (`filesystem` edit/write, `bash`) will surface: `ask` (yellow) — modal per call; `allow` (green) — auto-allow; `deny` (red) — auto-reject. `deny` is incompatible with `/duo-act` (Actor's `Task` dispatch would be rejected). Switch with Shift-TAB before approving, or anytime during execution.
2. **An active /duo session exists.** Verified below.

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
  done < <(find "$SESSIONS_ROOT" -mindepth 2 -maxdepth 2 -name '.duo-inflight' 2>/dev/null)
fi
if [ -z "$ACTIVE_INFLIGHT" ]; then
  echo "NO_SESSION: no active /duo session — run /duo-plan first."
  exit 0
fi
if [ "$ACTIVE_COUNT" -gt 1 ]; then
  echo "WARN: multiple active /duo sessions found; using the first encountered."
fi
SESSION_DIR="$(dirname "$ACTIVE_INFLIGHT")"
echo "session_dir=${SESSION_DIR}"
```

If the output starts with `NO_SESSION:`, **stop now** — print the message to the operator and end. Do not dispatch Actor.

Capture the `session_dir=...` value; use it as the literal path for the rest of this command.

## Read PLAN.md

Read `<SESSION_DIR>/PLAN.md`. If it does not exist (e.g. `/duo-plan` was interrupted), stop and tell the operator the session is malformed; suggest `/duo-abandon`.

## Last-minute amendments

The operator's `/duo-act` message is the approval signal — **no separate confirmation prompt is needed**. Dispatch Actor immediately after reading the plan.

**Exception — inline amendments:** if the operator wrote anything after `/duo-act` (e.g. `/duo-act also make sure X` or `/duo-act skip step 3`), treat that text as a last-minute amendment to the plan before dispatching:

1. Re-read `PLAN.md`.
2. Integrate the amendment. If the intent is clear, apply it silently and proceed. If ambiguous or potentially destructive, stop and ask one targeted clarifying question before continuing.
3. Rewrite `PLAN.md` via atomic-rename with the amended content.
4. Then dispatch Actor with the updated plan.

Do **not** ask for approval when no amendment text is present — the invocation itself is sufficient.

---

## Phase 3 — Execute (Task → Actor subagent)

After operator approval, dispatch Actor via the `Task` tool with `subagent_type: actor`. Prompt includes:

- The literal session directory path (`<SESSION_DIR>`).
- The full plan text from `PLAN.md`.
- An instruction to update `TASKS.json` in the session dir as steps complete.
- An instruction to return one of `ready_for_review | blocked | partial`.
- An instruction to include a diff summary in the final message.

Actor returns when:

- All steps complete: status `ready_for_review`, with diff summary. Show the diff to the operator.
- Blocked on a step: status `blocked: <reason>`. Surface to operator. Do not auto-retry. Decide whether to revise the plan and re-run, or abandon.
- Partial: status `partial: <details>`. Usually means dispatch Actor again for the remainder, possibly after operator clarification.

Map Actor's return to a cleanup `outcome`:

| Actor return | outcome |
|---|---|
| `ready_for_review` | `pass` |
| `blocked: …` | `block` |
| `partial: …` | `partial` |

---

## Phase 4 — Cleanup + telemetry

Run the cleanup script — it owns the full sequence in the correct order:
`.outcome` → end-snapshot → inflight removal → telemetry-summarise → post-verify.

```bash
~/.config/opencode/scripts/orchestra-cleanup.sh "<SESSION_DIR>" duo "<outcome: pass | block | partial>"
```

---

## Final summary

Print to the operator:

- Session dir path.
- Files changed (from Actor's diff summary).
- Tests run (if Actor chose to run any).
- Anything to verify manually.

Do **not** commit, push, or open a PR unless explicitly asked.

---

## What this command does NOT do

- ❌ Open a new /duo session (that's `/duo-plan`).
- ❌ Cancel without executing (that's `/duo-abandon`).
- ❌ Spawn `claude -p` subprocesses or use `run-tier.sh`.
- ❌ Have a Reviewer (use `/brain` for that).
- ❌ Auto-commit or auto-push.
- ❌ Run multiple parallel Actor invocations (single Actor handles the whole plan).
