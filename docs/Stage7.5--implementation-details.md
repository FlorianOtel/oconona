---
title: "v7.5 — oconona harness contract: per-session sidecars, badge format, attribution mechanics"
created_at: 2026-06-03--14-30
created_by: Claude Code (Claude Opus 4.7 1M context)
updated_by: Actor (Claude Haiku 4.5) via /brain pipeline
updated_at: 2026-06-04--10-04
context: >
  Authoritative reference for the v7.5 oconona contract exposed to OpenCode
  harnesses (octmux and future TUIs). Documents logical-part markers, all
  per-session sidecar files, invocations.log schema, post-v7.5 telemetry.json
  shape, the .oc-session-id match key, the symmetric badge format, write-order
  invariants, crash-recovery behaviour, and deprecation notices. Self-contained
  for two audiences: (a) a brand-new harness implementing orchestra-aware
  badge + attribution from scratch, and (b) the future octmux refactor /brain
  session that will revise octmux's docs/Stage8.md against this contract.
  Supersedes octmux Stage8.md §C-α contract and §Stage indicator. Companion
  to oconona v7.5 code commit eb540aa.
---

# v7.5 — oconona harness contract: per-session sidecars, badge format, attribution mechanics

## Status and scope

This document is the **authoritative v7.5 contract reference** for any OC harness consuming oconona's orchestration sidecars and telemetry output. It supersedes octmux `docs/Stage8.md` §C-α contract and §Stage indicator as the current definition of the sidecar filesystem layout, badge semantics, and telemetry.json shape.

The following does **not** happen in this `/brain`:
- No octmux-repo files (`StatusLine.tsx`, `orchestra-watch.ts`, `app.tsx`, `docs/Stage8.md`) are modified.
- octmux integration itself is deferred to a **future, unnumbered, separate `/brain` cycle** that will consume this document to revise/replace/refactor octmux's stale `docs/Stage8.md`.

This `/brain` writes the oconona-side contract, not the octmux consumer.

---

## Logical-part markers (`.brain-inflight` and `.duo-inflight`)

### Overview

Two inflight marker files signal the presence of an active orchestration session to harness consumers (status-line badges, watches, reporters). They are the **primary discovery signals** for the badge and polling logic.

### `.brain-inflight`

- **Path:** `${SESSION_DIR}/.brain-inflight` where `SESSION_DIR = ~/.config/opencode/orchestra/sessions/<UTC-ts>-<PID>/`
- **Writer:** `/brain` setup bash (atomic rename of `.brain-inflight.tmp`)
- **Removal:** `/brain` cleanup block, `/brain-abandon`, or stop-hook orphan finalizer (crash recovery)
- **Content:** Freeform title string (e.g., "refactor SoHoAI routing", max 30 printable chars, single-quotes stripped)
- **Presence semantic:** A `/brain` session is in-flight for this orchestra session_dir; harness consumers should render an active badge

### `.duo-inflight`

- **Path:** `${SESSION_DIR}/.duo-inflight`
- **Writer:** `/duo-plan` setup bash
- **Removal:** `/duo-act` or `/duo-abandon` cleanup block
- **Content:** Freeform title string (same formatting as `/brain`)
- **Presence semantic:** A `/duo` session is in-flight; badge should show "duo" mode

### Stale-marker guard

Marker files with `mtime > 24 hours` are treated as **crash orphans** by harness consumers (e.g., octmux). The stop-hook finalizer (fire on every OC session Stop event) walks session_dirs, identifies crashed sessions (inflight marker present but no `telemetry.json`), writes `.outcome=abandoned`, runs telemetry-summarize, and removes the stale marker. Harnesses must implement the same 24h mtime guard when deciding whether to render an inflight badge or skip it as stale.

---

## Per-session sidecar files

All sidecar files live in `${SESSION_DIR}/` alongside `PLAN.md`, `TASKS.json`, `telemetry.json`, etc.

| File | Writer | Consumer(s) | Stability | Semantics |
|---|---|---|---|---|
| `.oc-session-id` | setup bash via OC HTTP API resolution (NOT env var; OC 1.15.11 does not export `OC_SESSION_ID` to bash subprocesses) | `telemetry-summarize.py`, session-report.py, harnesses (for session filtering) | stable since v7.2 | **Authoritative match key.** OpenCode session ID (UUID format, `ses_...`). Obtained via HTTP API: `curl ... '[.[] \| select(.parentID == null and .directory == $dir)] \| sort_by(.time.updated) \| last \| .id'`. Single line, no trailing newline. Missing = setup failure; telemetry.json will have `cost_source: "none"` on cleanup. |
| `.project-dir` | setup bash from `$PWD` | forensic logs, legacy harness patterns | stable since v7.2 | **Deprecated for discovery / matching.** Preserved for back-compat with octmux Stage 8.0 watcher. Reason: daemon `process.cwd()` may differ from project CWD at `/brain` invocation. NFS cross-machine paths may not resolve consistently. Harnesses MUST use `.oc-session-id` as the match key instead. |
| `.parent-snapshot-start` | setup bash AFTER `.oc-session-id` (NEW v7.5) | `telemetry-summarize.py` for per-segment attribution | stable since v7.5 | JSON dict with fields: `cost`, `tokens_input`, `tokens_output`, `tokens_reasoning`, `tokens_cache_read`, `tokens_cache_write`, `time_updated` (ms since epoch, int). All values coerced to numeric types. Empty `{}` sentinel if DB miss. Atomic write. |
| `.parent-snapshot-end` | all cleanup paths (brain.md, duo-act.md, duo-abandon.md, brain-abandon.md, orchestra-hook.sh stop mode) AFTER `.outcome` and BEFORE `telemetry-summarize.sh` (NEW v7.5) | `telemetry-summarize.py` for segment-delta computation | stable since v7.5 | Same shape as start. Written in every cleanup path; invariant enforced. |
| `.outcome` | cleanup bash BEFORE `telemetry-summarize.sh` | status-line, reporters, harness consumers | stable since v6.1 | Values: `pass`, `block`, `partial`, `abandoned`, `fix-loop`. Written first in cleanup to bound the telemetry window (mtime guards the Stop-hook finalizer). |
| `.last-logfile` | orchestr-hook.sh start event | orchestra-hook.sh end event | stable since v6.1 | Sidecar from start→end link. Contains the logfile path for the session. Auto-cleaned after 120 min at hook startup if not claimed by matching end event. |
| `.transcript-uuid` | none (v7.2+ removed writes; field preserved v7.1 for back-compat) | none (legacy consumers removed v7.3) | deprecated | Forensic only; present on pre-v7.2 sessions. Absence is normal v7.2+. |
| `state.env` | `/brain` setup; reset at cleanup | Brain prompt context injection, badge title sourcing | stable (content appended by each phase) | Global path `~/.config/opencode/orchestra/state.env` (not per-session). Format: `KEY=VALUE` lines, append-only. Reset to `ORCHESTRA_MODE=default\nORCHESTRA_TITLE=\n` at cleanup. Keys: `ORCHESTRA_MODE` (brain\|duo\|default), `ORCHESTRA_TITLE` (title string). |

---

## Subagent role detection (SSE SubtaskPart)

Harness consumers detect live subagents via OpenCode SSE `message.part.updated` events where `part.type === "subtask"`. The `SubtaskPart` carries the fields `id`, `agent`, `description`, `sessionID`, and `messageID`.

**Subagent lifecycle:**
- **Start:** First `message.part.updated` event for a given `SubtaskPart.id` (discriminated by `part.type === "subtask"`).
- **End:** `message.part.removed` event for the same `partID`, OR `session.idle` event (which flushes all in-flight subagents).

**State tracking:** Harnesses maintain a set of active `SubtaskPart` IDs detected to date. On each `message.part.updated` with `part.type === "subtask"`, add the `part.id` to the set if not already present. On `message.part.removed`, remove the ID. On `session.idle`, clear the entire set.

**Reference implementation:** See `octmux/src/events.ts` (module `detectedSubtaskPartIDs: Set<string>`), `octmux/src/orchestra-watch.ts` (notify API methods `notifySubtaskStarted`, `notifySubtaskEnded`, `notifyAllSubtasksEnded`), and `octmux/src/app.tsx` (wiring events into watcher via `applyReplEvents`).

---

## `telemetry.json` shape (post-v7.5)

### Path and atomicity

- **Path:** `${SESSION_DIR}/telemetry.json`
- **Atomic write:** `mktemp` in same directory + `mv -f` (POSIX `rename(2)`). Consumers never see partial writes.

### Full schema

```json
{
  "session_id": "<orchestra session-dir basename>",
  "oc_session_id": "<OC UUID, or empty if setup failed>",
  "command": "brain|duo",
  "started_at": "<ISO 8601>",
  "ended_at": "<ISO 8601>",
  "duration_s": 123,
  "outcome": "pass|block|abandoned|partial",
  "parent": {
    "agent": "...",
    "model": "...",
    "provider_model_key": "...",
    "cost": 0.0,
    "tokens_input": 0,
    "tokens_output": 0,
    "tokens_reasoning": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 0
  },
  "parent_delta": {
    "cost": 0.0,
    "tokens_input": 0,
    "tokens_output": 0,
    "tokens_reasoning": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 0
  },
  "parent_total": {
    "agent": "...",
    "model": "...",
    "cost": 0.0,
    "tokens_input": 0,
    "tokens_output": 0,
    "tokens_reasoning": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 0
  },
  "parent_snapshot_start": {
    "cost": 0.0,
    "tokens_input": 0,
    "tokens_output": 0,
    "tokens_reasoning": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 0,
    "time_updated": 1717419045123
  },
  "parent_snapshot_end": {
    "cost": 0.0,
    "tokens_input": 0,
    "tokens_output": 0,
    "tokens_reasoning": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 0,
    "time_updated": 1717419050456
  },
  "started_at_oc_ms": 1717419045123,
  "ended_at_oc_ms": 1717419050456,
  "subagents": [
    {
      "agent": "planner",
      "model": "...",
      "provider_model_key": "...",
      "cost": 0.0,
      "tokens_input": 0,
      "tokens_output": 0,
      "tokens_reasoning": 0,
      "tokens_cache_read": 0,
      "tokens_cache_write": 0
    }
  ],
  "totals": {
    "cost_usd_estimate": 0.0,
    "tokens_input": 0,
    "tokens_output": 0,
    "tokens_reasoning": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 0
  },
  "cost_usd_estimate": 0.0,
  "cost_source": "oc_sqlite|none",
  "project_dir": "<from .project-dir sidecar>",
  "status": "final",
  "hybrid_attribution": {
    "hybrid_applicable": true,
    "subagent_marginal_costs": {
      "planner": 0.00001,
      "actor": 0.00002
    },
    "hidden_hybrid_cost_usd": 0.00003,
    "parent_cache_efficiency_pct": 85.5,
    "ttl_lapse_flag": false
  },
  "parser_warnings": [
    {
      "code": "snapshot_missing",
      "message": "parent snapshot sidecar(s) absent or invalid JSON; parent.cost is cumulative (not segment-delta)"
    }
  ]
}
```

### New fields (v7.5)

- **`parent_delta`**: segment-scoped parent cost+tokens (end snapshot - start snapshot). Only present/meaningful if both snapshots are non-empty `{}`.
- **`parent_total`**: full cumulative OC parent row (for forensics). Mirrors what pre-v7.5 `parent` field contained.
- **`started_at_oc_ms`** / **`ended_at_oc_ms`**: epoch milliseconds extracted from snapshot `time_updated` fields. Bounds the session window in OC's time scale.
- **`parent_snapshot_start`** / **`parent_snapshot_end`**: raw snapshot dicts (six fields each: cost, tokens_*). May be `{}` on DB miss.
- **`parser_warnings`**: list of `{code, message}` dicts. Populated when sidecars are missing/invalid; consumers should check this before trusting segment-delta attribution.

### Semantic changes

- **`parent.cost` (and `parent.tokens_*`):** Pre-v7.5, these held cumulative parent row values. **Post-v7.5, they hold segment-delta values** (end snapshot - start snapshot). Consumers requiring cumulative values must read `parent_total.cost` instead.
- **`cost_usd_estimate`**: Now reflects only the segment cost (`parent_delta.cost + sum(subagent costs)`). Mirrors `totals.cost_usd_estimate`.

### Fallback and degradation

If **both snapshots are `{}` or missing**:
- `parser_warnings` includes `{"code": "snapshot_missing", ...}`.
- `parent.cost` and `parent.tokens_*` fall back to whole-parent cumulative values (read from OC's full `get_session_telemetry()` result) — safe but not segment-correct.
- `parent_delta` and `parent_total` are present but `parent_total` carries the cumulative values (same as pre-v7.5).
- Consumers **must check `parser_warnings`** to distinguish segment-correct from fallback records.

### Attribution fallback via `subagents.jsonl` sidecar (v8.1.2+)

**Fix from octmux** (Stage 8.1.2, ref octmux commit `c73e354`)

The `subagents[].agent` and `subagents[].model` fields in `telemetry.json` may be sourced from the `subagents.jsonl` sidecar in the orchestra session directory rather than the OC DB columns when the DB `agent` and `model` columns are empty (NULL) for child sessions. `telemetry-summarize.py` merges `agent` and `model` values from `subagents.jsonl` (if present) into the `subagents[]` array entries by chronological index when DB columns are unpopulated. This ensures that `telemetry.json` output fields are reliably populated regardless of OC's DB column state.

### Write invariant

- Always atomic via `mktemp` + `mv -f` (POSIX `rename(2)`). Consumers never see partial writes.
- Consumers reading `telemetry.json` file-not-found or empty is legitimate (session crashed before cleanup; look for inflight marker instead).

---

## Sidecar match key (`.oc-session-id`)

### Authoritative key

`.oc-session-id` is **the single source of truth** for matching session_dirs to OC sessions. Pre-v7.5 `.project-dir` + `process.cwd()` matching is deprecated and must not be used for live session discovery.

### Recipe for harness consumers

1. Determine the OC session ID the harness is attached to (e.g., via OC HTTP API `GET /session` filtered by directory + `parentID == null`, last by `time.updated`).
2. Glob `~/.config/opencode/orchestra/sessions/*/` to enumerate all session subdirs.
3. For each, read `.oc-session-id` (skip if empty or missing).
4. Filter to directories whose `.oc-session-id` matches the harness's OC session ID.
5. Among matches: filter by inflight marker (`.brain-inflight` or `.duo-inflight`) presence for **live segments**; filter by `telemetry.json` presence for **completed segments**.
6. Proceed with the matched session(s).

### Multi-invocation invariant (octmux feedback, 2026-06-03)

`.oc-session-id` carries the **parent OC session ID**. That ID is constant for the lifetime of the OC session, so all orchestra session dirs created during the same OC session share the same `.oc-session-id` value. Sequential `/brain` or `/duo` runs in the same OC session therefore produce multiple session dirs that ALL pass the `.oc-session-id` match key — including completed runs whose dirs have not yet been cleaned up by the 30-day reaper.

**Implication:** the `.oc-session-id` match key alone is **not sufficient** to identify "live" session dirs — it identifies any dir created during this OC session, whether the orchestra run is in-flight or has completed. Harnesses MUST intersect the `.oc-session-id` match with inflight marker presence (`.brain-inflight` / `.duo-inflight`) for live-segment detection, and with `telemetry.json` presence (and absence of marker) for completed-segment detection.

Concretely, to detect "currently active" sessions, intersect:

- `.oc-session-id` matches harness OC session ID, AND
- inflight marker (`.brain-inflight` or `.duo-inflight`) is present, AND
- marker mtime < 24h (stale-after-crash guard).

Step 5 of the recipe above already prescribes this intersection, but the multi-invocation case is the load-bearing reason — without it, the recipe still works but the rationale isn't obvious. Harness concurrency counts (e.g., a "#N" multi-concurrent badge) must be computed against the inflight-bearing subset only, not the raw `.oc-session-id` match set.

**Origin:** octmux Stage 8.2.1 (commit `e28973e`, 2026-06-03) fixed a latent bug where `matchedSessionCount` was incremented on `.oc-session-id` match alone. Once one `/brain` completed, every subsequent live `/brain` in the same octmux session was mislabeled as multi-concurrent (`♪ orchestra -> #2 -> brain` instead of the actual title). The fix tracks `dirHasInflight` per loop iteration and only increments the count when an inflight marker is found. The contract itself was correct as designed; this section documents the invariant explicitly so future harnesses don't repeat the implementation gap.

**No oconona-side code change required.** Optional deeper mitigations (per-invocation `.orchestra-run-id` UUID sidecar; tiered retention reducing dwell time for completed dirs) were considered and rejected as overkill — the documentation clarification suffices because the intersect-with-marker pattern is straightforward to implement on the harness side.

### Why not `.project-dir`

- Daemon `process.cwd()` may differ from the project CWD at `/brain` invocation time (esp. on NFS cross-machine).
- Symlinks may not resolve consistently across machines.
- Multiple projects may share the same CWD path (e.g., two checkouts of the same repo).
- **Result:** `.project-dir` matches are unreliable. Deprecated for discovery in v7.5.

Pre-v7.5 code using `.project-dir` for discovery must be refactored to use `.oc-session-id` matching before the octmux refactor lands.

---

## Symmetric badge format spec

The badge has **four canonical states**, with mode segment always present.

### Idle state (no active orchestra)

- **Condition:** No session dir has an inflight marker (`.brain-inflight` or `.duo-inflight`) matching the harness's OC session ID.
- **Badge:** *(nothing rendered)*

### Active `/duo` session (one)

- **Condition:** One matched session dir with `.duo-inflight` present.
- **Badge:** `♪ orchestra -> <title> -> duo`
- **Example:** `♪ orchestra -> add docstring -> duo`

### Active `/duo` session with subagent dispatched

- **Condition:** One matched session dir with `.duo-inflight` present, AND an active subagent is detected via OC SSE `SubtaskPart` events.
- **Badge:** `♪ orchestra -> <title> -> duo -> <subagent>`
- **Example:** `♪ orchestra -> add docstring -> duo -> actor`

### Active `/duo` sessions (multiple concurrent, rare)

- **Condition:** Multiple matched session dirs with `.duo-inflight`, same OC session ID (architecturally rare; refusal logic usually prevents).
- **Badge:** `♪ orchestra -> #N -> duo`
- **Example:** `♪ orchestra -> #2 -> duo`

### Active `/brain` session

- **Condition:** One matched session dir with `.brain-inflight` present.
- **Badge:** `♪ orchestra -> <title> -> brain`
- **Example:** `♪ orchestra -> refactor routing -> brain`

### Active `/brain` session with subagent dispatched

- **Condition:** One matched session dir with `.brain-inflight` present, AND an active subagent is detected via OC SSE `SubtaskPart` events.
- **Badge:** `♪ orchestra -> <title> -> brain -> <subagent>`
- **Example:** `♪ orchestra -> refactor routing -> brain -> planner`

### Badge properties

- **Color:** `#d3869b` (gruvbox bright purple; unchanged from Stage 8).
- **Mode segment:** Always shown (symmetry: both brain and duo include it); never omitted even with subagent present.
- **Title truncation:** First 30 printable chars of inflight marker content or `state.env` value.

### Source of fields

- **`<title>`:** 
  - For `/duo`: first 30 chars of `.duo-inflight` content.
  - For `/brain`: `ORCHESTRA_TITLE=` value from `~/.config/opencode/orchestra/state.env` (or first 30 chars of `.brain-inflight` content if state.env is unavailable).
- **`<mode>`:** literal string `brain` or `duo` (inferred from which inflight marker is present).
- **`<subagent>`:** Detected via OC SSE `message.part.updated` with `part.type === "subtask"`; `agent` field carries the role name. Role values (canonical in v7.5+): `planner`, `actor`, `actor-heavy`, `reviewer`.

---

## What each consumer reads

### Standalone `orchestra-block.sh` (oconona's host status-line block)

**Files read:**
- `~/.config/opencode/orchestra/sessions/*/.brain-inflight`
- `~/.config/opencode/orchestra/sessions/*/.duo-inflight`
- `~/.config/opencode/orchestra/state.env`

**Polling strategy:** Invoked by host status-line render tick (no internal loop; external caller polls).

**Match-key behaviour:** Implicit (assumes single active orchestra session per host; no `.oc-session-id` filter needed for standalone OC). Globs all session dirs; finds first active (inflight marker present).

### Harness badge renderer (e.g., octmux `OrchestraWatcher` pattern)

**Files read:**
- `~/.config/opencode/orchestra/sessions/*/.oc-session-id`
- `~/.config/opencode/orchestra/sessions/*/.brain-inflight`
- `~/.config/opencode/orchestra/sessions/*/.duo-inflight`
- `~/.config/opencode/orchestra/state.env`

**Polling strategy:** `fs.watch()` on `~/.config/opencode/orchestra/sessions/` + 5-second `setInterval` fallback poll. Handles NFS attribute cache lag and missed events.

**Match-key behaviour:** **MUST filter by `.oc-session-id` matching the harness's OC session ID.** Recipe:
1. Get harness's OC session ID (via OC HTTP API `GET /session` etc.).
2. Glob `~/.config/opencode/orchestra/sessions/*/` and read `.oc-session-id` from each.
3. Retain only dirs whose `.oc-session-id` matches the OC session ID.
4. Apply 24h mtime stale-marker guard on inflight files (skip if > 24h old).
5. Render badge for matched live and completed segments.

### Telemetry summarizer (`telemetry-summarize.py`)

**Fix from octmux** (Stage 8.1.2, ref octmux commit `c73e354`)

**Files read:**
- `${SESSION_DIR}/.oc-session-id` (OC session ID match key)
- `${SESSION_DIR}/.parent-snapshot-start` (segment-delta start)
- `${SESSION_DIR}/.parent-snapshot-end` (segment-delta end)
- `~/.local/share/opencode/opencode.db` (OC SQLite session table)
- `${SESSION_DIR}/subagents.jsonl` (v8.1.2+, sidecar fallback for DB `agent`/`model` columns)

**Behaviour:** Queries OC's DB to fetch parent session and subagent child sessions. When OC DB `agent` and `model` columns are empty for child sessions, reads `subagents.jsonl` (if present) and merges `agent` and `model` fields into the subagents array by chronological dispatch order. Computes segment-delta costs (end snapshot - start snapshot) if both snapshots are non-empty.

**Sidecar format:** `subagents.jsonl` is NDJSON (one JSON object per line), written by `commands/brain.md` during Task dispatch. Each line contains: `{"agent": "<subagent_type>", "model": "<provider/model>", "dispatched_at_ms": <ms_since_epoch>}`. Stability: stable since v8.1.2 oconona attribution fix.

---

## Write-order invariants

All writers **must preserve these invariants** to ensure crash-safe recovery and consistent sidecar state.

1. **Inflight marker written FIRST in setup.** `.brain-inflight` or `.duo-inflight` is written before any other session side-effects. Atomic rename. This is the primary discovery signal; harnesses must see it immediately.

2. **`.oc-session-id` written AFTER inflight marker, BEFORE any subagent dispatch.** Ensures cleanup can resolve the OC session ID even if subagent dispatches modify the environment. Sourced from OC HTTP API (not env var).

3. **`.parent-snapshot-start` written AFTER `.oc-session-id`, BEFORE first subagent dispatch (NEW v7.5).** Captures the OC parent state before any child session creation. Atomic rename.

4. **`.outcome` written BEFORE `telemetry-summarize.py` invocation (existing invariant).** mtime bounds the cleanup time window; Stop-hook orphan finalizer uses mtime to guard the telemetry window.

5. **`.parent-snapshot-end` written AFTER `.outcome`, BEFORE `telemetry-summarize.sh` (NEW v7.5).** Captures the OC parent state at cleanup. Atomic rename. Invariant: every cleanup path must write this, AFTER outcome.

6. **The inflight marker is removed BEFORE `telemetry-summarize.sh` is invoked.** The brief window where a session_dir has neither an inflight marker nor a `telemetry.json` is handled by the Stop-hook orphan finalizer (see §11 Crash-recovery behaviour).

7. **All snapshot sidecar writes are atomic.** `mktemp` + `mv -f`.

---

## Atomic-rename pattern

The idiom for all sidecar writes:

```bash
# Temporary file in same directory as target
printf '%s\n' "$CONTENT" > "${TARGET}.tmp"

# Atomic rename (POSIX rename(2) is atomic within same filesystem)
mv -f "${TARGET}.tmp" "${TARGET}"
```

**Rationale:** POSIX `rename(2)` is atomic within the same filesystem. Concurrent readers either see the old file or the new file, **never a partial write**. This applies to:
- All sidecar marker files (`.brain-inflight`, `.duo-inflight`, `.oc-session-id`)
- All snapshot files (`.parent-snapshot-start`, `.parent-snapshot-end`)
- `.outcome` and related state
- `telemetry.json` (especially critical — consumers should never encounter truncated JSON)

**Rationale for same directory:** Move within same filesystem (e.g., `mv -f /tmp/X.tmp ~/.config/opencode/orchestra/sessions/ABC/X` may cross filesystems on NFS). Safe strategy: `mktemp` in the target directory itself, not `/tmp`.

---

## Hooks

The hook script `scripts/orchestra-hook.sh` remains in scripts/ for forward-compat with hook-supporting platforms but is currently inert on OC (which does not support OC plugin hooks).

---

## Crash-recovery behaviour

The Stop-hook orphan finalizer is the safety net for crashed sessions.

### When it fires

On **every OC session Stop event** (once per operator turn), `scripts/orchestra-hook.sh stop` mode fires.

### What it does

1. Walks session_dirs in `~/.config/opencode/orchestra/sessions/*/`.
2. **Skip condition:** if `.brain-inflight` or `.duo-inflight` is present, the session is still in-progress — skip (do not remove the marker).
3. **Skip condition:** if `telemetry.json` exists, cleanup already completed — skip.
4. **Candidate condition:** inflight marker is absent AND `telemetry.json` is absent AND session dir contains `PLAN.md` or `RESEARCH.md` (artefacts from an active session).
5. **For candidates:** write `.outcome=abandoned`, write `.parent-snapshot-end`, run `telemetry-summarize.py`, remove any stale inflight marker.

### Stale-marker guard for harnesses

Harness consumers should ignore inflight markers with `mtime > 24 hours` — treat as crash orphans. The finalizer will eventually clean them up, but the 24h guard prevents stale badges from persisting indefinitely.

---

## Deprecation notices

These APIs and patterns have been superseded and must not be used in new code.

### `.project-dir` for session discovery (deprecated in v7.5)

**Old pattern (Stage 8.0):** Filter session dirs by matching `.project-dir` against `process.cwd()`, then read inflight marker content.

**Problem:** daemon `process.cwd()` may differ from `/brain` invocation CWD (esp. on NFS). Symlinks don't resolve consistently. Not reliable.

**Replacement:** Use `.oc-session-id` match key (see §Sidecar match key above).

**Timeline:** Pre-v7.5 code using `.project-dir` for discovery must be refactored before the octmux refactor lands. The sidecar will be preserved for back-compat but no longer documented as a match key.

### `ORCHESTRA_MODE` prefix matching for discovery (deprecated in v7.5)

**Old pattern (Stage 8.2 design):** Use `.project-dir` + `process.cwd()` to find a session, then infer the mode (brain or duo) from the `ORCHESTRA_MODE` prefix in `state.env`.

**Problem:** Same issues as above, plus `state.env` is not a per-session file (it's global and shared across all sessions).

**Replacement:** Use `.oc-session-id` + read the inflight marker filename (`.brain-inflight` vs `.duo-inflight`) to determine mode.

**Timeline:** Same as `.project-dir` — refactor before the octmux refactor lands.

### Z2c (session.title injection via Task tool `title:` parameter, never shipped)

**Status:** Never shipped. Not planned.

**Reason:** Complexity of passing session title through Task dispatch arguments; file-based sidecar (current `.brain-inflight` / `.duo-inflight` content) is simpler and more robust.

### C-γ (OC `session.title` mutation via PATCH /session/{id}, deferred)

**Status:** UX-acceptable per operator (2026-06-03) but deprioritised under simplicity + robustness principle.

**Reason:** Filesystem-based discovery is sufficient for current use cases; would require:
- OC HTTP API endpoint to PATCH session title (may not exist or may be restricted)
- Cross-repo coordination (octmux or harness calling into OC via API; currently only oconona writes files)
- Additional failure modes (API timeout, permission denied, OC version drift)

**Future-revisitable:** If a non-octmux harness later requires an idiomatic OC-API surface for session attribution, C-γ may be reconsidered.

### `stage` field in `invocations.log` (deprecated label, v7.5+)

**Old pattern:** Using `stage` field (values: `plan`, `implement`, `review`) to label subagent roles.

**Problem:** Not all roles map to stages (e.g., Reviewer is not a stage, it's a tier). Stage labels conflate orchestration phases with subagent types. Ambiguous when multiple Actors run per step.

**Replacement:** Use `subagent` field (canonical values: `planner`, `actor`, `actor-heavy`, `reviewer`). This field is role-specific and unambiguous.

**Timeline:** Both fields present in v7.5+ for back-compat. New code must use `subagent` field. Legacy consumers reading `stage` will continue to work.

---

## Harness implementation checklist

Step-by-step recipe for a brand-new OC harness implementing orchestra-aware badge + per-segment cost tracking from scratch.

1. **Determine the harness's OC session ID.** Call OC HTTP API `GET /session` filtered by `directory == process.cwd()` and `parentID == null`, sorted by `time.updated`, take last. Store this as `harnessSessionID`.

2. **Glob session dirs.** Walk `~/.config/opencode/orchestra/sessions/*/` and read `.oc-session-id` from each. Filter to those matching `harnessSessionID`. This gives you the set of matched session_dirs.

3. **Identify live segments.** For each matched session_dir: if `.brain-inflight` or `.duo-inflight` is present (and mtime < 24h), it's a live segment. Store the marker filename and content.

4. **Identify completed segments.** For each matched session_dir: if `telemetry.json` exists (and no inflight marker), it's a completed segment. Read the file.

5. **Extract badge title for live segments.** 
   - For `.duo-inflight`: read marker content (first 30 chars).
   - For `.brain-inflight`: read `ORCHESTRA_TITLE=` line from `~/.config/opencode/orchestra/state.env` (fallback to first 30 chars of `.brain-inflight` if state.env unavailable).

6. **Determine badge mode.** literal string: `duo` (if `.duo-inflight` present) or `brain` (if `.brain-inflight` present).

7. **Determine active subagent role.** Detect live subagents via OC SSE `SubtaskPart` events (`part.type === "subtask"`). Track `partID` set; clear on `message.part.removed` or `session.idle`. Extract `agent` field from detected parts (canonical role: `planner`, `actor`, `actor-heavy`, `reviewer`). See `octmux/src/events.ts` `detectedSubtaskPartIDs` for reference implementation.

8. **Render badge.** Use template: `♪ orchestra -> <title> -> <mode> [-> <subagent>]`. Color `#d3869b`. Subagent segment is optional (only if role is live).

9. **Extract per-segment cost for completed sessions.** Read `telemetry.json` and extract `totals.cost_usd_estimate` (or use `cost_usd_estimate` top-level field for back-compat with pre-v7.5 shape). Check `parser_warnings` — if `snapshot_missing` is present, cost is cumulative (not segment-delta).

10. **Compute live cost (in-flight sessions).** Call OC HTTP API `GET /session/{id}/messages` and sum `AssistantMessage.cost` for the matched parent session. Then call `GET /session/{id}/children` and sum child session costs. This is the live cost for the active session (OC reports it in real time). **Do NOT read `telemetry.json` for active sessions — it doesn't exist yet (written only at cleanup).**

11. **Implement polling.** Use `fs.watch()` on `~/.config/opencode/orchestra/sessions/` + 5-second `setInterval` fallback. Re-run the sidecar read + filter logic on each event.

12. **Implement stale-marker guard.** Ignore inflight markers with `mtime > 24h` (crash orphans).

---

## Cross-references

- **Architecture & design:** `docs/design.md` §Write-order invariants (broader oconona architecture; this document extends it with v7.5 snapshot additions).
- **Roadmap:** `docs/Stage7.md` (v7.5 is this work; commit `eb540aa`).
- **Implementation history:** `docs/Stage7--Changelog.md` (v7.5 entry).
- **Supersedes:** octmux `docs/Stage8.md` §C-α contract (deployment contract for harnesses) and §Stage indicator (inflight marker semantics).
- **Future octmux refactor:** A separate octmux `/brain` session (unnumbered) will consume this document to revise/replace/refactor octmux's `docs/Stage8.md`. That session will update octmux's sidecar reading, badge rendering, and cost-aggregation logic to the v7.5 contract. This `/brain` does NOT touch octmux files.
