---
title: "Stage 6 — oconona + octmux dual-stream real-time cost telemetry"
created_at: 2026-05-28--17-15
created_by: Planner subagent (claude-sonnet-4-6) via /brain
updated_by: Claude Code (Claude Haiku 4.5)
updated_at: 2026-05-28--14-00
context: >
  Stage 6 adds real-time cumulative cost display to both the claude-orchestra
  status-line block (oconona) and the octmux TUI status bar. Two mutually-exclusive
  real-time streams — native (non-orchestra turns) and orchestra (in-flight /brain
  or /duo sessions) — are both captured in telemetry.json files and summed for
  display. Both streams are real-time, mutually exclusive by inflight-marker
  enforcement, and the display is their direct sum. No .section accumulator state
  file. No shared CLI helper. No subprocess from octmux into oconona. Stage 6 also
  includes model-relaxation work for the /duo pipeline (per-role config.yaml
  models:, brain.md model-check loosening, deploy.sh materialisation, Anthropic
  rate refresh).
---

# Stage 6 — Dual-stream real-time cost telemetry

## One-line intent

After this stage, both the claude-orchestra tmux status-line and the octmux TUI
status bar display the true running session cost as the live sum of a native
telemetry.json (updated on every non-orchestra model turn) and any in-flight
orchestra telemetry.json files (updated at each pipeline phase boundary), with
no double-counting and no separate live-cost helper.

---

## Roles and responsibilities

| Concern | Owner | Notes |
|---|---|---|
| Writer A — native telemetry.json | oconona (claude-orchestra) | Stop-hook tick; paused while orchestra inflight |
| Writer B — orchestra partial telemetry.json | oconona (claude-orchestra) | Per-phase write inside telemetry-summarize.py |
| Status-line display | oconona (claude-orchestra) | orchestra-block.sh glob+sum; replaces section-state model |
| TUI badge (inflight detection) | octmux | fs.watch on inflight markers; 250 ms debounce |
| TUI cost display | octmux | cost-aggregator.ts; 5 s poll; reads both file types |
| Writing to ~/.config/opencode/orchestra/ | FORBIDDEN for octmux | octmux is read-only consumer |

**oconona is primary.** All telemetry writes are oconona's responsibility.
octmux reads files; it never writes to `.opencode/orchestra/`.

---

## Sub-stage overview

| Sub-stage | Project | Title |
|---|---|---|
| 6.1 | oconona | Dual-stream writers — native tick + orchestra partial |
| 6.2 | oconona | Model-relaxation work for /duo pipeline |
| 6.3 | octmux | Orchestra inflight badge (fs.watch on inflight markers) |
| 6.4 | octmux | Cost aggregator reading both telemetry.json streams |

---

## Status-line ownership and contact surface

The claude-orchestra status-line block (`status-line/orchestra-block.sh`) is the
**authoritative display** of cumulative cost for the native CC session. It is
injected into `~/.claude/scripts/status-line.sh` at deploy time.

octmux consumes the same files independently for its own TUI cost badge. octmux
MUST NOT call any oconona script and MUST NOT write to `~/.config/opencode/orchestra/`.

### Files octmux reads (contact surface)

| File | Path | What octmux consumes |
|---|---|---|
| Native telemetry | `~/.config/opencode/orchestra/native-sessions/<oc_session_id>.json` | `cost_usd_estimate` (float) only |
| Orchestra telemetry (per session) | `~/.config/opencode/orchestra/sessions/*/telemetry.json` | `cost_usd_estimate` (float) only |
| Inflight markers (badge only) | `~/.config/opencode/orchestra/sessions/*/.brain-inflight`, `.duo-inflight` | presence/absence only — no content |

All other fields in telemetry.json (status, cost_source, parent, subagents, etc.)
are informational for oconona tooling only. octmux treats them as opaque.

**Display formula (both consumers):**

```
display = native_telemetry.json::cost_usd_estimate
        + sum(~/.config/opencode/orchestra/sessions/*/telemetry.json::cost_usd_estimate)
```

Disjoint by construction (mutual exclusion via inflight markers). No
double-counting. The orchestra glob includes in-flight partial writes (`status:
"in_flight"`) as well as final writes (`status: "final"`) — both are summed.

---

## Crash safety, race conditions, and sanity checks

This section is the primary maintenance reference for the dual-writer model.
Every failure mode is enumerated with its mitigation and debug surface.

### Failure mode table

| Failure mode | Mitigation | Debug surface |
|---|---|---|
| **Stale `.brain-inflight` / `.duo-inflight` after OC process crash** | Status-line liveness check: `orchestra-block.sh` reads `${SESSION_DIR}/.transcript-uuid` and verifies `~/.claude/active-sessions/native-<uuid>.lck` exists. Missing lck → stale marker, excluded from display and writer A gate. The Stop-hook's `stop` mode also removes dead lck files at each response turn. | `invocations.log` — Stop hook logs `{"event":"stop"}` on every turn; if a stale marker survives, a manual `ls ~/.claude/active-sessions/` shows the absent lck. Liveness check is in `orchestra-block.sh` lines 57–70. |
| **Partial telemetry.json write interrupted (oconona killed mid-flush)** | All writes — both native and orchestra partial — use `mktemp` + `mv -f` (POSIX `rename(2)` atomic within same filesystem). Consumers always see a complete prior file or the new complete file; never a half-written file. The `.tmp` file is left behind on crash; next write overwrites it. | Orphan `.tmp` files in `native-sessions/` or `sessions/<id>/` indicate a prior crash. Can be found with `find ~/.config/opencode/orchestra -name '*.tmp'`. |
| **Race between orchestra setup writing `.inflight` and a Stop-hook that fires before the marker is visible (NFS/atomicity)** | The Stop hook's native writer gate uses `find … -name '.brain-inflight' -o -name '.duo-inflight'` which is a directory scan, not a file read. On NFS with attribute caching, a freshly written marker may not be visible for up to `acdirmax` seconds (default 60 s on Linux NFSv3). Mitigation: orchestra setup bash writes `.inflight` as its FIRST action before any other side effects, and the native writer in the Stop hook checks this marker after a short `sleep 0.1` (one stat retry). For the status-line, stale-lck detection already excludes false-live sessions. | If a native tick fires during orchestra setup (rare — the setup bash is fast), the worst case is one spurious native write with partial cost. The next Stop-hook tick will see the marker and skip. Divergence detected by sanity check (monotonic non-decrease). |
| **Race between orchestra cleanup removing `.inflight` and the next Stop-hook update for native** | Write-order invariant: `.inflight` removal happens AFTER `telemetry.json` (final) is written by `telemetry-summarize.py`. The native writer reads the final `telemetry.json` to compute the residual (`OC_session_total - sum(orchestra telemetry)`). If the native writer fires in the tiny window between `.inflight` removal and final `telemetry.json` write, the glob sum will be stale (prior partial). Mitigation: native writer uses the glob sum at the moment it fires; if the result is negative (orchestra cost exceeds OC total), the native write is skipped and retried on the next Stop-hook tick. | Negative residual is logged to `invocations.log` as `{"event":"native_write_skipped","reason":"negative_residual"}`. Check this log after any crash. |
| **OC SDK / SoHoAI query failing mid-update (cost source unavailable)** | Orchestra partial writes fall back from SoHoAI → litellm → pricing.yaml cascade (same as `telemetry-summarize.py` main). If all sources fail, `cost_usd_estimate` is written as 0.0 with `cost_source: "none"`. The partial write still happens (never suppressed on source failure). Consumers treat 0.0 as valid (not an error). | `cost_source: "none"` in the telemetry.json file is the debug signal. Also logged to `invocations.log` as `{"event":"partial_write","cost_source":"none"}`. |
| **Concurrent reads by status-line / octmux while oconona is writing** | Atomic-rename write: readers either see the old complete file or the new complete file. No reader ever sees a partial write. Rename is atomic within the same filesystem (POSIX `rename(2)`). On NFS: rename is atomic on the server; attribute cache on the client may delay visibility by up to `acregmax` seconds (default 60 s NFSv3). Octmux's 5 s poll and the status-line's 8 s TTL cache are both well within typical `acregmax`. | If a consumer displays a stale value, check NFS mount options (`mount | grep nfs`). Mounting with `actimeo=0` disables attribute caching at the cost of performance. |
| **Two orchestra sessions simultaneously active (should be impossible, defend in depth)** | The orchestra glob (`sessions/*/telemetry.json`) sums all files regardless. If two sessions somehow both have `.inflight`, the native writer sees the combined orchestra cost and computes the correct residual. The status-line liveness check uses per-session lck verification, so only truly-live sessions count for the badge. | Two simultaneous lck-live `.duo-inflight` markers appears in `orchestra-block.sh` as `duo_count=2`. Log a `{"event":"concurrent_orchestra_sessions","count":2}` warning to `invocations.log`. |
| **New OC session starts with stale files left from prior crashed session** | Native writer uses `<oc_session_id>` as the filename. A new OC session gets a new session ID, so it writes to a new file; the old file is not overwritten. The glob sum includes both — this is correct if the old session cost is still live cost from this project. If not, the operator should run `oconona cleanup` (future CLI). For now: native writer does NOT delete prior-session files. | Stale files are identifiable by `last_updated_unix` in the file header (to be added in 6.1). Files older than the current OC session start time are stale. `find ~/.config/opencode/orchestra/native-sessions -name '*.json' -mtime +7` shows old files. |
| **native telemetry.json from a prior OC session present when a new one starts** | The native writer filename is keyed by `<oc_session_id>` (the OpenCode session UUID). A new session generates a new UUID → new file. Consumers glob all `native-sessions/*.json` and sum. Operator must periodically prune old files or run `oconona cleanup`. The sum formula treats all files as live. | The `last_updated_unix` field (Stage 6.1) allows consumers to warn when a file has not been updated in more than N hours. octmux shows the sum without warning (no file-age logic in 6.4 — deferred to 6.x). |
| **Empty / malformed / truncated JSON in either telemetry file** | Every consumer uses a try/catch (TypeScript) or `jq -r '… // 0'` (bash) with a fallback of 0. An unparseable file contributes 0 to the sum, not an error. The writer's atomic-rename guarantee means this should never happen in normal operation; if it does, it indicates an OS-level filesystem issue. | octmux logs `[cost-aggregator] warn: unparseable telemetry at <path>` to stderr (visible in the terminal or tmux scrollback). The bash status-line uses `jq … // 0` silently. |

### Write-order invariants

These invariants MUST be preserved by all writers. Violating them can cause
double-counting, missing cost, or negative-residual skips.

1. **`.inflight` written BEFORE any other session side effects.** Orchestra setup
   bash writes `.brain-inflight` or `.duo-inflight` as its first action.
2. **`telemetry.json` (final) written BEFORE `.inflight` is removed.** Guarantees the
   native writer can read the final orchestra cost immediately after the marker disappears.
3. **`.outcome` written BEFORE `telemetry-summarize.py` is invoked.** mtime bounds the
   T2 time window (CO reference: `orchestra-hook.sh` lines 303–308).
4. **All telemetry.json writes are atomic (tmp+rename).** Both Writer A and Writer B
   use `mktemp` + `mv -f`. Consumers always see a complete file.
5. **Native writer computes cost as residual.** `native_cost = OC_session_total -
   sum(orchestra telemetry.json::cost_usd_estimate)`. If residual is negative, write
   is skipped this tick and logged.

### Sanity checks

1. **Monotonic non-decrease** on native cost. Log `{"event":"native_cost_decrease",...}`
   on violation.
2. **cost_divergence cross-check** (5% threshold). Adapted from CO's
   `_validate_cost_display()` in `telemetry-summarize.py` lines 589–645. Append
   `{"event":"cost_divergence","divergence_pct":N}` to `invocations.log`.
3. **Negative residual guard** on native writer.
4. **Malformed JSON guard** in all consumers (jq // 0, TS try/catch).
5. **Status-line liveness check** via `.transcript-uuid` → `native-<uuid>.lck`
   (CO reference: `orchestra-block.sh` lines 57–70).

### Idempotency requirements

- **deploy.sh materialisation** (Stage 6.2): presence sentinels, skip if already
  present. Re-running is safe.
- **Stop-hook native tick**: idempotent. Reads current total, writes residual.
  Double-fire produces the same value (up to sub-second granularity).
- **telemetry-summarize.py partial write**: replaces file, never appends. Double-fire
  is safe — same or higher cost overwrites.

### Cleanup machinery

- **Stop-hook orphan-marker finalisation** (CO reference: `orchestra-hook.sh` lines
  272–355). Fires every response turn. Walks session dirs without `telemetry.json`
  and without inflight markers; writes `.outcome=abandoned`, invokes summariser,
  resets state.env. Safety net for crashed orchestra sessions.
- **Lck liveness check** (CO reference: `bash-session-init.sh` writes lck,
  `orchestra-block.sh` lines 57–70 reads it). `kill -0 $_pid` for dead-process detection.
- **Tmp file cleanup**: orphan `.json.tmp` files are benign — overwritten on next
  successful write. Periodic `find … -name '*.tmp' -mtime +1 -delete` (cron or
  future `oconona cleanup`).

### CO patterns adopted and adapted

| Pattern | CO source | Adaptation for Stage 6 |
|---|---|---|
| Orphan-marker finalisation (`.outcome=abandoned` before summariser) | `orchestra-hook.sh` lines 299–312 (stop mode) | Native writer adopts the same pre-write-outcome discipline |
| Orchestra-parent suppression in native finaliser | `native-session-finalize.py` lines 143–165 | Replaced by residual formula: native cost IS the residual; nothing to suppress |
| Deduplication on re-run (replace existing session_id line) | `telemetry-summarize.py` lines 831–847; `native-session-finalize.py` lines 199–216 | Partial writes use the same replace-or-append pattern |
| Write-order: `.outcome` before summariser | `design.md` §Hooks; `orchestra-hook.sh` lines 303–308 | Directly adopted |
| Cost-source cascade (SoHoAI → litellm → pricing.yaml) | `telemetry-summarize.py` lines 709–753 | Reused as-is for orchestra partial writes; native uses pricing.yaml only |
| cost_divergence cross-check (5% threshold) | `telemetry-summarize.py` lines 589–645 | Adapted: display sum vs OC session total instead of LAST_NONZERO vs telemetry |
| Atomic-rename write (mktemp + mv -f) | `telemetry-summarize.py` lines 788–794; `bash-session-init.sh` lines 34–37 | Directly adopted for both Writer A and Writer B |
| Liveness check via lck | `orchestra-block.sh` lines 57–70; `bash-session-init.sh` line 11 | Directly adopted for stale-inflight-marker detection |
| Always-rewrite cache even on zero | `section-live-cost.sh` lines 124–131 | Adapted: the telemetry.json partial write always happens, even when cost is 0 |
| T1/T2 cross-check | `telemetry-summarize.py` lines 559–586 | Retained in final orchestra write; not performed on partial writes |

**What does NOT apply from CO:**

- `.section` state file (`~/.claude/active-sessions/<UUID>.section`): Stage 6
  replaces the section-accumulator model with direct file summation.
- `section-live-cost.sh`: replaced by the direct glob+sum.
- SoHoAI live-cost helper (`sohoai-live-cost.sh`): explicitly excluded for the
  cumulative display path.

---

## Stage 6.1 — oconona: dual-stream writers

**Writer A — Native Stop-hook tick:**
Fires on every Stop event. If no inflight marker is present (lck-verified), writes a
`native-sessions/<oc_session_id>.json` file with `cost_usd_estimate` equal to:
`OC_session_total - sum(sessions/*/telemetry.json::cost_usd_estimate)`. The residual.

**Writer B — Orchestra in-flight partial telemetry.json updates:**
Modifies `telemetry-summarize.py` to support a `--status in_flight` mode. Triggered
at each phase boundary (Planner-end, Actor-step-end, Reviewer-end) from the existing
SubagentStop hook.

**Status-line block change:**
`orchestra-block.sh` cost section replaces section-accumulator with glob+sum.

### Numbered steps

1. **Add `native-sessions/` directory to CO deploy.** Edit `deploy.sh` to create
   `~/.config/opencode/orchestra/native-sessions/` at deploy time (this is what deploy.sh now does).
2. **Add Writer A logic to `orchestra-hook.sh` stop mode.** After existing
   native-session-finalize.py loop, add residual-write block with negative-guard,
   monotonic check, atomic tmp+rename. Log `{"event":"native_tick","cost":X}`.
3. **Add `--status` argument to `telemetry-summarize.py`.** Default `final` (existing).
   `in_flight` writes status field, skips global jsonl append, skips T1/T2 cross-check.
4. **Trigger Writer B partial writes from `orchestra-hook.sh` end mode.** After
   each SubagentStop, invoke `telemetry-summarize.py ... --status in_flight`
   best-effort (`|| true`). Log `{"event":"partial_write","stage":"$STAGE"}`.
5. **Update `orchestra-block.sh` cost display to use glob+sum.** Remove all
   references to `.section` / SECTION_ID / ACCUMULATED_TOTAL / section-live-cost.sh.
   Add cost_divergence check (5% threshold).
6. **Write deploy.sh sentinel-guarded update for the new orchestra-block.sh.**
   Idempotent via existing sentinels.
7. **Update docs/Stage6.md implementation log** with 6.1 commit hash.

---

## Stage 6.2 — oconona: model-relaxation for /duo pipeline

8. **Add per-role `models:` block to `config/config.yaml`** (planner, actor,
   actor_heavy, reviewer).
9. **Loosen brain.md model-check.** Change "hard block" to advisory warning. Brain
   logs warning to invocations.log but proceeds.
10. **Update `deploy.sh` to materialise per-role model config into agent files.**
    `sed` rewrite of `model:` line in each `agents/*.md` at deploy time, targeting
    `# MODEL_PLACEHOLDER` sentinels.
11. **Verify Anthropic rate-limit config is current.** Update `config.yaml`
    rate_limits: section against current tier limits.
12. **Update docs/Stage6.md implementation log** with 6.2 commit hash.

---

## Stage 6.3 — octmux: orchestra inflight badge

13. **Create `src/orchestra-watch.ts`.** `OrchestraWatcher` class using `fs.watch`,
    debounce 250 ms, finds `.brain-inflight` / `.duo-inflight`, sets badge state.
    Graceful absence if `sessions/` does not exist.
14. **Wire `OrchestraWatcher` into `src/app.tsx`.** useEffect instantiates,
    subscribes, disposes on unmount.
15. **Extend `src/components/StatusLine.tsx`** with `orchestraBadge` prop; render
    inline `| ♪ brain: <label>` or `| ♪ duo: <label>`.
16. **Rebuild binary** (`bun build src/index.tsx --compile ...`) and smoke-test
    badge appears within 500 ms.
17. **Update docs/Stage6.md** (octmux's own) with 6.3 commit hash.

---

## Stage 6.4 — octmux: cost aggregator

18. **Create `src/cost-aggregator.ts`.** Reads native-sessions glob + orchestra
    sessions glob, sums `cost_usd_estimate`. 5 s poll. Graceful absence. Never throws.
19. **Wire `CostAggregator` into `src/app.tsx`.** useEffect instantiates,
    subscribes `onChange`, disposes on unmount.
20. **Update `src/components/StatusLine.tsx`** to accept `runningCost` prop;
    replace hardcoded `Σ$0.00` with `Σ$${runningCost.toFixed(2)}` when > 0.
21. **Rebuild binary** and smoke-test cost updates within ~5 s of turn completion.
22. **Update docs/Stage6.md** (octmux's own) with 6.4 commit hash.
    Update `docs/Implementation-plan.md` Stage 6 status to `✓ shipped`.
    Update memory file at `/home/florian/.claude/projects/-mnt-nfs-Florian-Gin-AI-projects-octmux/memory/project-octmux.md`.

---

## Doc impact

- `docs/Stage6.md` (oconona — this file): implementation log entries at each sub-stage.
- `docs/Implementation-plan.md` (octmux): Stage 6 status to `✓ shipped` after 6.4.
- `design.md` (oconona): update model-check enforcement table (step 9),
  cost-section model (replace section-accumulator with glob+sum), Data sources table.
- octmux memory file: update after final commit.

---

## Risks / unknowns

1. **OC session ID availability in the Stop hook.** Native writer needs OC UUID
   to name the file. May not be in hook env. Confirm: sidecar file at session
   start, or `GET /session/current`.
2. **OC session total cost source.** Residual formula needs `OC_session_total`.
   `cost.total_cost_usd` from CC JSON is documented unreliable for parent
   attribution. Fallback: JSONL walk + pricing.yaml (same as T2). Confirm in code.
3. **NFS atomicity of tmp+rename across hosts.** `rename(2)` atomic on server;
   client dentry stale up to `acdirmax` (60 s NFSv3 default). Status-line 8 s
   TTL and octmux 5 s poll within typical `acregmax`. Workaround: `actimeo=1`
   if needed. Latency, not correctness.
4. **Stop-hook firing latency on long turns.** Native file not updated for the
   duration of a 10-minute Actor step. Display shows last-written value. Known
   limitation; affects native stream only.
5. **`config.yaml` `models:` migration.** New structure; existing deployments fall
   back to hardcoded agent files. Adding `# MODEL_PLACEHOLDER` sentinels must be
   careful to avoid breaking deployed configs.
6. **Schema migration if `status` field added later.** Already present in 6.1.
   Consumers ignore it (just sum cost_usd_estimate). Future stages can filter.
7. **Two OC sessions in same project.** Display sums all `native-sessions/*.json`.
   Technically correct but may surprise. Documented as known limitation.

---

## Out of scope

- No separate live-cost helper (`section-live-cost.sh` / `sohoai-live-cost.sh`)
  for cumulative display.
- No `.section` state file — section-accumulator model fully replaced.
- No `oconona cleanup` CLI command for pruning stale native-sessions files.
- No per-session cost breakdown in octmux TUI (aggregate only).
- No `status: in_flight` vs `final` visual distinction in octmux TUI.
- No file-age warning in octmux for stale native-sessions files.
- octmux implementing any orchestration logic.
- octmux invoking any oconona script as a subprocess.
- octmux writing to `~/.config/opencode/orchestra/`.
- Inline permission prompts in octmux (shipped Stage 5.3).
- v2 features (auto mode, decision gates, Researcher gating, checkpoint commits).

---

## Implementation log

## 2026-05-28 — Stage 6.1: dual-stream writers shipped

**Commit:** `cbfc067`

**Changes:**
- Path audit: all `${OPENCODE_PROJECT_DIR}/.opencode/orchestra/` references migrated to `~/.config/opencode/orchestra/` (global, NFS-shared)
- Path audit: `deploy.sh` fixed `agent/` → `agents/`, `command/` → `commands/` (canonical OpenCode dirs)
- `deploy.sh`: added `~/.config/opencode/orchestra/native-sessions/` directory creation
- `scripts/telemetry-summarize.sh`: forward extra args `${@:5}` to Python script
- `scripts/telemetry-summarize.py`: added `--status final|in_flight` arg; `in_flight` mode skips global jsonl append and T1/T2 cross-check; added `project_dir` field to output
- `scripts/orchestra-hook.sh`: Writer B (end mode) — partial `telemetry.json` after each SubagentStop; Writer A (stop mode) — native residual tick writing `native-sessions/native-<uuid>.json`
- `status-line/orchestra-block.sh`: replaced SoHoAI live-cost with glob+sum over Writer A + Writer B files; added cost_divergence cross-check
- `commands/brain.md`, `commands/duo-plan.md`: added `.project-dir` sidecar write for project attribution
- `scripts/session-report.py`: reads `project_dir` from telemetry.json (Stage 6.1+) instead of path-based inference
