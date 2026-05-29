---
title: "Stage 7 — OC-native telemetry redesign roadmap"
created_at: 2026-05-28--18-16
created_by: Actor (Claude Haiku 4.5)
updated_by: Actor (Claude Haiku 4.5)
updated_at: 2026-05-29--11-09
context: >
  Stage 7 roadmap doc, produced by Brain/Planner session
  20260528T181605Z-2855594. Tracks the v7.0–v7.5 sub-stages replacing the
  T1/T2 SoHoAI cost-attribution telemetry with OC-native SQLite telemetry.
  Backfilled with detailed implementation plan, deliverables, and per-stage
  handover notes mirroring the old docs/Stage6.md structure.
---

# Stage 7 — OC-native telemetry redesign roadmap

## One-line intent

After Stage 7 ships, the T1/T2 hybrid and SoHoAI cost-attribution path (Surface B) are fully removed; a single OC-native SQLite-backed telemetry plane handles per-turn visibility and post-hoc reporting; ~1500 lines of CC-era workaround code are replaced by a thin `scripts/oc-db.py` helper module.

## Roles and responsibilities

| Project | Owns |
|---|---|
| **oconona** (this repo) | The orchestra pipeline (`commands/`, `agents/`), the OC-SQLite read path (`scripts/oc-db.py`), telemetry summarisation (`scripts/telemetry-summarize.py`), the orchestra Stop-hook (`scripts/orchestra-hook.sh`), the standalone-OC status-line cost block (`status-line/orchestra-block.sh`), all reports (`scripts/session-report.{sh,py}`, `scripts/telemetry-report.sh`). |
| **octmux** (sibling repo) | The TUI rendering (`src/components/StatusLine.tsx`), the cost aggregator (`src/cost-aggregator.ts`, v7.5). Reads `telemetry.json` files written by oconona via the contract defined here. |
| **SoHoAI** (upstream proxy) | Provider routing only (Surface A — `provider.sohoai` block in OC's `opencode.json`). No telemetry coupling after Stage 7 ships. Surface B (cost-attribution SQLite/HTTP queries, `X-Orchestra-Session-ID` header, `active-sessions/*.lck` mechanism) is removed by v7.1–v7.3. |
| **OpenCode** (upstream runtime) | The `session` table in `~/.local/share/opencode/opencode.db`. We read its `cost`, `tokens_*`, `parent_id`, `agent`, `model` columns. We never write. WAL mode is preserved. |

## Sub-stage roadmap

| Stage | Scope | Status |
|---|---|---|
| **v7.0** | Doc restructure: `docs/pre-Stage7--opencode-redesign.md` + `docs/Stage7.md` + `docs/Stage7--Changelog.md` + delete Stage6 docs + clean `docs/design.md` stale refs | shipped (commit `de631cc`) |
| **v7.1** | `scripts/oc-db.py` (new SQLite helper) + `scripts/telemetry-summarize.py` rewrite — read from OC SQLite instead of T2 JSONL | shipped (commit `21c3bd3`) |
| **v7.2** | `scripts/orchestra-hook.sh` T1/T2 strip + commands setup/cleanup block updates — drop `active-sessions/*.lck` writes, add `.oc-session-id` sidecar capture | shipped (commit `0479ea8`) |
| **v7.3** | Status-line rewrite + `session-report.py` rewrite + dead file deletion (`sohoai-live-cost.sh`, `otel-headers-helper.sh`, `bash-session-init.sh`, `native-session-finalize.py`, `native-subagent-cost.sh`) + `deploy.sh`/`collect.sh` updates + fold `docs/pre-Stage7--opencode-redesign.md` into `docs/design.md` | not started |
| **v7.4** | Carry-forward of original Stage 6.2 model-relaxation for `/duo` (per-role `config.yaml models:`, deploy.sh materialisation, Anthropic rate refresh) | not started |
| **v7.5** | octmux integration — replace glob+sum cost aggregator with OC SQLite reader via `telemetry.json` shape; carry-forward of original Stage 6.4 | not started |

## Dependencies and sequencing

```
v7.0 (shipped)
 ↓
v7.1 (oc-db.py + telemetry-summarize.py)
 ↓
v7.2 (orchestra-hook.sh strip + command updates) — requires oc-db.py
 ↓
v7.3 (status-line + reports + deletes + deploy.sh + design.md fold) — requires all v7.1+v7.2 call-sites updated
 ↓
 ├──→ v7.4 (model-relaxation for /duo)   — independent of v7.5
 └──→ v7.5 (octmux integration)          — requires final telemetry.json shape from v7.3
```

v7.4 and v7.5 are independent of each other and can ship in either order (or in parallel) once v7.3 has stabilised the telemetry.json contract.

## Architecture (post-Stage-7)

### Single source of truth

OC's SQLite `session` table at `~/.local/share/opencode/opencode.db`. The `session` row carries `cost`, `tokens_input`, `tokens_output`, `tokens_reasoning`, `tokens_cache_read`, `tokens_cache_write`, `model`, `agent`, `parent_id`, `time_created`, `time_updated`, `time_archived`, `directory`. The `@ai-sdk/anthropic` provider populates `cost` accurately for Anthropic-routed sessions. The `@ai-sdk/openai-compatible` provider correctly reports `cost = 0` for `sohoai/*` (flat-rate marginal).

The `model` column stores a JSON object `{"id":"...","providerID":"...","variant":"..."}`.
`oc-db.py`'s `_parse_model()` helper extracts the `id` field; falls back to raw string
for NULL or non-JSON values.

### Per-tier breakdown via `parent_id`

OC creates child sessions for every `Task`-tool dispatch. Querying `WHERE parent_id = <brain_session_id>` returns one row per subagent dispatch, each with its own `agent` (`planner`, `actor`, etc.), `model`, `cost`, `tokens_*`. No SoHoAI session-ID tagging is required.

### The `.oc-session-id` sidecar

At orchestra session setup (`/brain`, `/duo-plan`), the bash setup block captures the `OC_SESSION_ID` env var into `${SESSION_DIR}/.oc-session-id`. This is the only "glue" between orchestra session-dirs and OC session rows. Cleanup reads it back, queries OC's DB, and writes `telemetry.json`.

### `telemetry.json` shape (the cross-repo contract)

**Path:** `${SESSION_DIR}/telemetry.json`
where `SESSION_DIR = ~/.config/opencode/orchestra/sessions/<UTC-ts>-<PID>/`

**Not to be confused with** `~/.config/opencode/orchestra/telemetry.jsonl` (global
append-only index, one summary line per session — dropped in v7.1).

```json
{
  "session_id": "<orchestra dir basename>",
  "oc_session_id": "<OC UUID>",
  "command": "brain|duo",
  "started_at": "<ISO8601>",
  "ended_at": "<ISO8601>",
  "duration_s": 123,
  "outcome": "pass|block|abandoned|partial",
  "parent": { "agent": "...", "model": "...", "cost": 0.0, "tokens_input": 0, ... },
  "subagents": [ { "agent": "...", "model": "...", "cost": 0.0, ... }, ... ],
  "totals": { "cost_usd_estimate": 0.0, "tokens_input": 0, ... },
  "cost_usd_estimate": 0.0,
  "cost_source": "oc_sqlite",
  "project_dir": "<from .project-dir sidecar>",
  "status": "final"
}
```

`cost_usd_estimate` is preserved at the top level (mirrors the value in `totals.cost_usd_estimate`) for octmux Stage 6.4 backward compatibility. Cross-repo consumers (octmux v7.5) read top-level `cost_usd_estimate`.

## Crash safety, race conditions, and sanity checks

The redesign removes most of the failure modes from Stage 6.1's dual-writer model. Many of the old races are **eliminated**, not just mitigated, because the writers that competed are gone.

### Failure mode table (under OC-SQLite model)

| Failure mode | Mitigation | Debug surface |
|---|---|---|
| **Stale `.brain-inflight` / `.duo-inflight` after OC process crash** | Read `.oc-session-id` sidecar. Call `oc_db.get_session(<id>)`. If row's `time_archived IS NOT NULL` OR `time_updated > 30 min` ago, orchestra session is stale. Stop-hook orphan finalizer (preserved from Stage 6.1) writes `.outcome=abandoned`, runs telemetry-summarize, removes marker. | `invocations.log` records `{"event":"stop"}` per turn. `find ~/.config/opencode/orchestra/sessions -name '.brain-inflight' -mtime +1` reveals truly stale markers. |
| **Partial `telemetry.json` write interrupted (oconona killed mid-flush)** | All writes use `mktemp` + `mv -f` (POSIX `rename(2)` atomic within same filesystem). Consumers always see prior complete file or new complete file. | Orphan `.tmp` files in `sessions/<id>/`. Find with `find ~/.config/opencode/orchestra -name '*.tmp'`. |
| **Race between orchestra setup writing `.inflight` and Stop-hook** | **Eliminated.** Writer A is gone (no `native_tick` events). Stop-hook has no telemetry-write to compete against setup. | n/a — no race exists. |
| **Race between cleanup removing `.inflight` and next Stop-hook** | **Eliminated.** Same — no Writer A. The orphan finalizer only acts on dirs with no `telemetry.json` AND no inflight marker. | n/a — no race exists. |
| **Concurrent reads (status-line / octmux) while oconona writes** | `telemetry.json` atomic tmp+rename — readers never see partial. OC's DB runs WAL mode: many concurrent readers + OC's writer never block each other. | If a stale value displays, check OC's DB is WAL: `sqlite3 ~/.local/share/opencode/opencode.db 'PRAGMA journal_mode'` should return `wal`. |
| **OC SQLite DB unavailable or corrupted** | `oc_db.open_db()` raises on schema mismatch with a clear `RuntimeError("OC schema mismatch: missing column 'X'...")`. Callers wrap in try/except and fall back to `cost = 0.0`, `cost_source = "none"`. The partial write still happens (never suppressed on source failure). | `cost_source: "none"` in telemetry.json. Also logged to `invocations.log` as `{"event":"telemetry_summarize_failed"}`. |
| **OC schema drift in future OC version** | All SQL is localised to `scripts/oc-db.py` (~80 lines). Schema self-check at first `open_db()` call asserts required columns and raises clear error. One file to update when OC's schema changes. | Schema-mismatch RuntimeError surfaces immediately at the next telemetry-summarize call. |
| **Two orchestra sessions simultaneously active (defend in depth)** | Each orchestra session writes its own `${SESSION_DIR}/.oc-session-id`. `telemetry-summarize` only queries the specific OC session ID for its session dir. No cross-contamination possible. | Status-line liveness check via `.brain-inflight`/`.duo-inflight` markers (per-session-dir). |
| **New OC session inherits stale files from prior crashed session** | **Improved over Stage 6.1.** No more `native-sessions/` directory (removed in v7.3). Each `${SESSION_DIR}/.oc-session-id` scopes attribution to one specific OC UUID. The 30-day session-dir reaper handles old orchestra dirs. | `find ~/.config/opencode/orchestra/sessions -maxdepth 1 -mtime +30` shows old dirs eligible for reaping. |
| **Empty / malformed / truncated JSON in `telemetry.json`** | Every consumer uses `jq -r '… // 0'` (bash) or Python try/except with fallback to 0. Atomic-rename guarantees this should never happen in normal operation. | octmux logs `[cost-aggregator] warn: unparseable telemetry at <path>` (v7.5). Bash status-line uses `jq … // 0` silently. |
| **OC's `cost` field reports unexpected non-zero for `sohoai/*` (the glm-5.1 anomaly)** | OC's `cost` field is treated as truth unconditionally. No second-guessing. If OC says non-zero, we report non-zero. | Compare with SoHoAI's billing DB if needed; not a debugging concern in production. |

### Write-order invariants

These invariants MUST be preserved by all writers.

1. **`.brain-inflight` / `.duo-inflight` written BEFORE any other session side effects.** Orchestra setup bash writes the marker as its first action. (Preserved from Stage 6.)
2. **`.oc-session-id` sidecar written during setup, BEFORE any subagent dispatch.** Ensures cleanup can resolve the OC session ID even if subagent dispatches modify the env.
3. **`.outcome` written BEFORE `telemetry-summarize.py` is invoked.** mtime bounds the cleanup time window for the orphan finalizer. (Preserved from Stage 6.)
4. **`telemetry.json` (final) written via atomic tmp+rename BEFORE `.inflight` is removed.** Guarantees consumers never see "no telemetry, no inflight" except for legitimately-abandoned sessions. (Preserved from Stage 6.)
5. **All `telemetry.json` writes are atomic.** `mktemp` + `mv -f` in `telemetry-summarize.py`.

### Sanity checks

1. **Schema self-check** at first `oc_db.open_db()` call per process. Raises `RuntimeError` with explicit missing-column name on mismatch.
2. **`time_archived` dual-check** in `oc_db.is_session_over()`: returns `True` if `time_archived IS NOT NULL OR time_updated < now - 30 min`. Safe under either Hypothesis A (OC sets on session end) or Hypothesis B (only on explicit archive).
3. **Trust OC's `cost` field unconditionally.** The 2026-05-28 glm-5.1 anomaly ($0.048 for a sohoai/* session contradicting flat-rate assumption) is handled by simply reporting what OC says. No reconciliation logic.
4. **Schema-drift guard** asserts column list at open-time, not at query-time. Errors surface immediately at the start of `telemetry-summarize`, not silently mid-row.
5. **Malformed JSON guard** in all consumers (jq // 0, TS try/catch, Python try/except).

### Idempotency requirements

- **`telemetry-summarize.py` re-run**: idempotent. Reads OC's DB at the moment of invocation, replaces `telemetry.json` atomically. Double-fire produces the same value (within OC's between-call deltas).
- **`oc_db.open_db()`**: schema check runs once per process via `_schema_checked` module flag.
- **deploy.sh materialisation** (v7.4 for `models:` block): presence sentinels, skip if already present. Re-running is safe.
- **Stop-hook orphan finalisation**: walks session dirs without `telemetry.json` and without inflight markers. Skips dirs where either is present. Re-running is safe.

### Cleanup machinery

- **Stop-hook orphan-marker finalisation** (preserved from Stage 6.1). Fires every response turn from `orchestra-hook.sh stop` mode. Walks session dirs without `telemetry.json` and without inflight markers; writes `.outcome=abandoned`, invokes summariser. Safety net for crashed orchestra sessions.
- **No lck liveness check needed.** `~/.config/opencode/active-sessions/*.lck` files are gone after v7.2.
- **Tmp file cleanup**: orphan `.json.tmp` files are benign — overwritten on next successful write. Periodic `find ~/.config/opencode/orchestra -name '*.tmp' -mtime +1 -delete` (operator action).
- **Session-dir reaper**: `find ~/.config/opencode/orchestra/sessions -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +` runs at every orchestra setup (existing housekeeping, preserved). Retention configurable in `config/config.yaml:housekeeping.session_retention_days`.


---

## Stage v7.0 — Doc restructure (shipped)

**Status:** shipped — commit `de631cc` (backfilled by `de40d03`).

Created `docs/pre-Stage7--opencode-redesign.md`, `docs/Stage7.md`, `docs/Stage7--Changelog.md`. Deleted `docs/Stage6.md`, `docs/Stage6--Changelog.md`. Purged stale references from `docs/design.md`. See `docs/Stage7--Changelog.md` for the full delivery record.

---

## Stage v7.1 — `oc-db.py` helper + `telemetry-summarize.py` rewrite

### Scope

Two deliverables. First, a new thin Python module `scripts/oc-db.py` that encapsulates all read-only SQLite queries against OC's `~/.local/share/opencode/opencode.db`. Second, a rewrite of `scripts/telemetry-summarize.py` to read session data from OC's DB via `oc-db.py` instead of walking CC-style JSONL transcripts.

After v7.1 ships, the new code path exists but is **not yet wired into the live pipeline** — v7.2 updates the call sites. v7.1 is independently testable: invoke `telemetry-summarize.py` directly with a session_dir containing `.oc-session-id` and verify it produces a well-formed `telemetry.json`.

### Numbered steps

1. **Create `scripts/oc-db.py`** with required functions: `open_db()`, `_check_schema()`, `get_session()`, `get_child_sessions()`, `is_session_over()`, `get_session_telemetry()`. Module docstring states safety guarantees (read-only `?mode=ro`, WAL semantics, local NVMe, 5s timeout). Schema self-check asserts all required columns at first open.

2. **Add standalone smoke test for `oc-db.py`**: `python3 -c "import sys; sys.path.insert(0,'.../scripts'); import oc_db; conn = oc_db.open_db(); print('schema ok')"`. Verify against the live DB.

3. **Verified pre-plan** (2026-05-29): Hypothesis B confirmed. `time_archived` is NULL for all
   observed sessions. No code change beyond the dual-check already designed. Documented in
   v7.1 changelog entry.

4. **Rewrite `scripts/telemetry-summarize.py`**. Drop: `_normalize_model_id` complexity, `get_transcript_path`, `load_pricing_yaml`, `_load_sohoai_config`, `query_sohoai_usage`, `query_sohoai_cost`, `query_litellm_cost`, `read_telemetry_events`, `_walk_jsonl_for_tokens`, `process_transcript`, `compute_cost`, `cross_check_t1_t2`, the entire cost-source cascade, `--status in_flight` separate write path, and the `~/.config/opencode/orchestra/telemetry.jsonl` global append. Keep: arg parsing, atomic tmp+rename write, the `--status` flag (now controls only an early-return for `in_flight`; no separate file shape).

5. **Implement the new `telemetry.json` shape** (matches the cross-repo contract above). Read `.oc-session-id` sidecar; call `oc_db.get_session_telemetry(oc_id)`; assemble parent + subagents + totals + top-level `cost_usd_estimate` mirror; atomic-write. Print one-line summary: `telemetry: cost=$X.XXXX source=oc_sqlite session=<id>`.

6. **Update the shell wrapper `scripts/telemetry-summarize.sh`** if needed (probably no change — same args).

7. **Prepend Stage v7.1 entry to `docs/Stage7--Changelog.md`**. Note the empirical `time_archived` finding. Refresh frontmatter timestamps.

### Deliverables

- `scripts/oc-db.py` (new, ~80 lines including docstrings)
- `scripts/telemetry-summarize.py` (rewritten, expected ~150 lines from current ~750)
- `docs/Stage7--Changelog.md` entry with commit hash

### Handover notes for v7.2

- `oc-db.py` is in `scripts/`. Callers add `sys.path.insert(0, "/path/to/scripts")` before `import oc_db`. The literal pattern is documented in `oc-db.py`'s module docstring.
- The new `telemetry-summarize.py` REQUIRES `${SESSION_DIR}/.oc-session-id` to exist. v7.2 must add the setup-block writes that produce it.
- v7.1 does NOT modify any caller. After v7.1 ships, `orchestra-hook.sh` still has Writer A + Writer B logic (now mostly redundant); `commands/*.md` still write `active-sessions/*.lck` files; `status-line/orchestra-block.sh` still uses glob+sum. These all get updated in v7.2 + v7.3.
- The `--status in_flight` flag becomes vestigial after v7.2 removes Writer B's call. Document but leave the arg in place for v7.1 — v7.2 will simplify further.
- `time_archived` empirical finding from Step 3 affects nothing in code (the dual-check is correct regardless) but should be noted in the changelog so v7.2/v7.3 reviewers understand the dependency.

---

## Stage v7.2 — `orchestra-hook.sh` strip + command setup/cleanup updates

### Scope

Strip the Stage 6.1 dual-stream writers (Writer A + Writer B) from `scripts/orchestra-hook.sh`. Update the orchestra command files (`commands/{brain,duo-plan,duo-act,duo-abandon,brain-abandon}.md`) to drop the `~/.config/opencode/active-sessions/*.lck` mechanism and add `.oc-session-id` sidecar capture at setup.

After v7.2 ships, the live pipeline uses the new OC-SQLite-native path. Status-line cost is **temporarily broken** until v7.3 ships the status-line rewrite — operator either runs OC standalone (in which case `orchestra-block.sh` is being rewritten in v7.3) or runs OC inside octmux (where the cost display is currently the hardcoded `~$0.00` placeholder pending Stage 6.4 / v7.5).

### Numbered steps

8. **Strip `scripts/orchestra-hook.sh` `stop` mode.** Remove the entire Writer A native-tick block (residual computation, native-sessions/*.json write). Remove the dead-lck-file finalizer loop (no more lck files). Keep: inflight-marker detection, state.env reset, orphan-session finalizer (safety net, walks dirs without `telemetry.json` AND without inflight markers).

9. **Strip `scripts/orchestra-hook.sh` `end` mode.** Remove the Writer B partial-write block (`telemetry-summarize.sh ... --status in_flight` call and `partial_write` log event). Keep: subagent start/end logging.

10. **Strip `scripts/orchestra-hook.sh` `start` mode and all modes.** Remove all `telemetry-events.jsonl` append logic. Remove `BASH_ENV` references if any.

11. **Update `commands/brain.md` setup block.** Remove: `~/.config/opencode/active-sessions/*.lck` write, `.transcript-path` sidecar, `.transcript-uuid` sidecar, the `otelHeadersHelper` / `ANTHROPIC_CUSTOM_HEADERS` write if present. Add: `printf '%s\n' "${OC_SESSION_ID:-}" > "${SESSION_DIR}/.oc-session-id"` immediately after `mkdir -p`.

12. **Update `commands/brain.md` housekeeping loop.** Remove the `for _f in ... *.lck; do kill -0 ...; done` loop. Keep the session-dir retention loop.

13. **Apply the same edits to `commands/duo-plan.md`** as in Steps 11–12.

14. **Update `commands/{brain-abandon,duo-abandon,duo-act}.md` cleanup blocks.** Remove `rm -f "${HOME}/.config/opencode/active-sessions/$(basename "<SESSION_DIR>").lck"` lines. Remove `ANTHROPIC_CUSTOM_HEADERS` / `X-Orchestra-Session-ID` removal logic. Update `telemetry-summarize.sh` call if arg signature changed in v7.1 (likely no change). Preserve the write-order invariant: `.outcome` → `telemetry-summarize.sh` → `.inflight` removal.

15. **Prepend Stage v7.2 entry to `docs/Stage7--Changelog.md`**. Refresh frontmatter timestamps.

### Deliverables

- `scripts/orchestra-hook.sh` (~150 lines shorter)
- 5 command files updated (`brain.md`, `duo-plan.md`, `duo-act.md`, `duo-abandon.md`, `brain-abandon.md`)
- `docs/Stage7--Changelog.md` entry

### Handover notes for v7.3

- A `/duo-plan` or `/brain` run after v7.2 produces a session_dir with `.oc-session-id` populated. v7.3 status-line work depends on this sidecar's presence at every active orchestra session.
- After v7.2, no new `*.lck` files are written under `~/.config/opencode/active-sessions/`. v7.3 deletes `bash-session-init.sh` and `otel-headers-helper.sh` (their writers).
- After v7.2, no new `telemetry-events.jsonl` files are written. v7.3 can safely remove the references in `docs/design.md` file-inventory annotations.
- Existing pre-v7.2 session-dirs may have `.transcript-uuid`, `.transcript-path`, no `.oc-session-id`. `telemetry-summarize.py` warns and emits `cost = 0.0` on missing `.oc-session-id`. Operator can manually `rm -rf` pre-v7.2 session-dirs or let the 30-day reaper take them.
- `orchestra-hook.sh stop` mode's orphan finalizer is preserved — still walks session dirs and writes `.outcome=abandoned` for crashed sessions. Critical for crash safety; v7.3 must not regress this.

---

## Stage v7.3 — Status-line + reports + dead-file deletes + `deploy.sh`/`collect.sh` + design.md fold

### Scope

The largest of the v7.x stages. Rewrite `status-line/orchestra-block.sh` cost path to read OC's DB directly. Rewrite `scripts/session-report.py` to query OC for native sessions instead of legacy JSONL. Rewrite `scripts/smoke-test.sh` and `scripts/telemetry-report.sh --tier` for the new shape. Delete dead-file scripts. Update `deploy.sh` and `collect.sh` to drop deleted-script references and add `oc-db.py`. Fold `docs/pre-Stage7--opencode-redesign.md` content back into `docs/design.md` §Telemetry as the authoritative architecture description. Delete `config/pricing.yaml`.

After v7.3 ships, the redesign is complete for oconona's scope. The standalone-OC status-line works again (no longer broken by v7.2). The pre-Stage7 architecture doc becomes redundant and is deleted (or kept as a one-line tombstone with a forward-pointer to `design.md`).

### Numbered steps

16. **Rewrite `status-line/orchestra-block.sh` cost path.** Replace the glob+sum block with a single `oc_db.get_session_telemetry()` Python invocation. Remove: SoHoAI live-cost call, `cost_divergence` cross-check, `_is_non_anthropic` branch, `live_session_id` / `.lck` reading block. Keep: `ctx-segment.sh` call, badge rendering, OC native status-line strip. Preserve `Σ$` cost prefix.

17. **Rewrite `scripts/session-report.py`.** Read OC's DB for native sessions (`WHERE parent_id IS NULL` minus those tagged by an orchestra `.oc-session-id` sidecar). Read orchestra sessions from `sessions/*/telemetry.json` (still written by v7.1's `telemetry-summarize.py`). Display `cost_source: oc_sqlite`. Preserve `--last`, `--since`, `--month`, `--source` flags.

18. **Rewrite `scripts/smoke-test.sh`** with 3 OC-native checks: (a) `.oc-session-id` sidecar present and non-empty; (b) OC DB row present + child sessions count; (c) `telemetry.json` written with `totals.cost_usd_estimate > 0`. Remove old T1/T2/global-log checks.

19. **Rewrite `scripts/telemetry-report.sh --tier` path.** Read new `telemetry.json` shape: `parent.{agent,model,cost,tokens_*}` + `subagents[].{...}` + `totals.cost_usd_estimate`. Remove SoHoAI cost-source split display.

20. **Delete dead scripts and config files.** `git rm`: `scripts/bash-session-init.sh`, `scripts/native-session-finalize.py`, `scripts/native-subagent-cost.sh`, `scripts/sohoai-live-cost.sh`, `scripts/otel-headers-helper.sh`, `scripts/native-session-report.sh`, `scripts/native-session-report.py`, `config/pricing.yaml`.

21. **Update `deploy.sh`.** Remove `copy_file` calls for the 7 deleted scripts. Add `copy_file` call for `scripts/oc-db.py`. Remove the `mkdir -p "$OC_HOME/orchestra/native-sessions"` line and the `mkdir -p "$OC_HOME/active-sessions"` line if present. Remove the `pricing.yaml` copy. Add orphan-cleanup block to remove the 7 deleted scripts (and `pricing.yaml`) from existing deploy targets:
    ```bash
    for orphan in bash-session-init.sh native-session-finalize.py native-subagent-cost.sh \
                  sohoai-live-cost.sh otel-headers-helper.sh native-session-report.sh \
                  native-session-report.py; do
        [ -f "$OC_HOME/scripts/$orphan" ] && rm -f "$OC_HOME/scripts/$orphan" && \
            ok "cleaned orphan: $OC_HOME/scripts/$orphan"
    done
    [ -f "$OC_HOME/orchestra/pricing.yaml" ] && rm -f "$OC_HOME/orchestra/pricing.yaml"
    ```

22. **Update `collect.sh`.** Remove references to deleted scripts. Add `oc-db.py`. Verify `collect.sh` exists in repo root before editing.

23. **Fold `docs/pre-Stage7--opencode-redesign.md` into `docs/design.md` §Telemetry.** Replace the v7.0 forward-pointer placeholder with the architecture description (rationale, OC SQLite schema, `.oc-session-id` sidecar, `telemetry.json` shape, SoHoAI dependency inventory — Surface A only). Update §"Data sources" table, §"File inventory", §"Troubleshooting" with current state. Refresh `updated_by` / `updated_at`.

24. **Delete `docs/pre-Stage7--opencode-redesign.md`** OR replace with a one-line tombstone "Content folded into `docs/design.md` §Telemetry as of v7.3 commit `<hash>`". Operator preference.

25. **Update `docs/Stage7.md` v7.0–v7.3 status markers to `shipped`** with commit hashes. Update `docs/Stage7--Changelog.md` with the v7.3 entry.

26. **Update `AGENTS.md`**. Remove the CC-era native-session smoke-test section. Update scripts inventory: add `oc-db.py`, remove the 7 deleted scripts.

27. **Update `README.md`**. Remove any T1/T2 / SoHoAI cost / `.lck` / `pricing.yaml` mentions. Brief OC-native telemetry description.

### Deliverables

- `status-line/orchestra-block.sh` (rewritten, ~100 lines shorter)
- `scripts/session-report.py` (rewritten)
- `scripts/smoke-test.sh` (rewritten)
- `scripts/telemetry-report.sh` (rewritten `--tier` path)
- 7 scripts + `config/pricing.yaml` deleted
- `deploy.sh`, `collect.sh` updated
- `docs/design.md` §Telemetry restored with current architecture (folded from `pre-Stage7--opencode-redesign.md`)
- `docs/pre-Stage7--opencode-redesign.md` deleted or tombstoned
- `AGENTS.md`, `README.md` updated
- `docs/Stage7.md` status markers updated
- `docs/Stage7--Changelog.md` entry

### Handover notes for v7.4 and v7.5

- After v7.3, `docs/pre-Stage7--opencode-redesign.md` no longer exists (or is a tombstone). `docs/design.md` is the authoritative architecture reference.
- The `telemetry.json` cross-repo contract is **stabilised** by v7.3. octmux Stage 6.4 / v7.5 can rely on the shape documented in `docs/design.md` §Telemetry.
- v7.4 and v7.5 are independent of each other and can ship in either order.
- v7.4's `MODEL_PLACEHOLDER` sed-rewrite in `deploy.sh` does not conflict with v7.3's `deploy.sh` updates — they touch different sections.

---

## Stage v7.4 — Model-relaxation for `/duo` pipeline (carry-forward of Stage 6.2)

### Scope

Originally planned as Stage 6.2 in the deprecated `docs/Stage6.md`. Carried forward unchanged. Adds per-role `models:` block to `config/config.yaml`, materialises model selection into agent frontmatter at deploy time via `# MODEL_PLACEHOLDER` sentinels, and refreshes Anthropic rate-limit config.

This stage is independent of the v7.1–v7.3 telemetry refactor. It can ship before or after v7.5.

### Numbered steps

28. **Add per-role `models:` block to `config/config.yaml`** (planner, actor, actor_heavy, reviewer).
29. **Loosen `commands/brain.md` model-check** from any "hard block" to advisory warning. Brain logs warning to `invocations.log` but proceeds. **Note:** this step is largely satisfied by commit `a90b4dc` (Brain Opus 4.7 advisory) which already removed any hard gate for Brain; v7.4 confirms no regression and applies the same posture for worker tiers.
30. **Update `deploy.sh` to materialise per-role model config into agent files.** `sed` rewrite of `model:` line in each `agents/*.md` at deploy time, targeting `# MODEL_PLACEHOLDER` sentinels.
31. **Verify Anthropic rate-limit config is current.** Update `config.yaml` `rate_limits:` section against current tier limits.
32. **Update `docs/Stage7.md`** v7.4 status to `shipped`. Prepend Stage v7.4 entry to `docs/Stage7--Changelog.md`.

### Deliverables

- `config/config.yaml` updated with `models:` block + refreshed `rate_limits:`
- `agents/*.md` modified with `# MODEL_PLACEHOLDER` sentinels (`model:` value moves to config)
- `deploy.sh` updated to materialise placeholders at deploy time
- `commands/brain.md` advisory-only model check confirmed
- Doc updates

### Handover notes

- After v7.4, agent model selection is config-driven. Operators tune per-role models via `config.yaml` without editing `agents/*.md`.
- Sentinels must be present in `agents/*.md` for `deploy.sh` to fill them in. A missing sentinel does not break deploy (sed substitution is a no-op) — but the deployed agent runs with whatever `model:` value was in the source file.

---

## Stage v7.5 — octmux integration (carry-forward of Stage 6.4)

### Scope

Originally planned as Stage 6.4 in the deprecated `docs/Stage6.md`. Forward-adapted for the new `telemetry.json` shape stabilised by v7.3. octmux replaces its `~$0.00` hardcoded status-line placeholder with a live `runningCost` value sourced from a `CostAggregator` that reads `~/.config/opencode/orchestra/sessions/*/telemetry.json` files (and aggregates `totals.cost_usd_estimate` or the top-level mirror).

This stage is in the **octmux repo**, not oconona. It is included in Stage 7's roadmap because the contract it depends on (the `telemetry.json` shape) is owned by oconona and stabilised by v7.3.

### Numbered steps

> **Note (superseded by Amendment 2026-05-29--07-54 below):** Steps 33–35 below describe the
> original `telemetry.json` glob-sum approach. The octmux /brain session revised this; see the
> amendment section after the Handover notes.

33. **Create `src/cost-aggregator.ts` in octmux.** Reads `~/.config/opencode/orchestra/sessions/*/telemetry.json`. Sums `cost_usd_estimate` (top-level field; falls back to `totals.cost_usd_estimate` if the top-level is absent). 5-second poll. Graceful absence (file missing → contributes 0). Never throws.
34. **Wire `CostAggregator` into `src/app.tsx`.** `useEffect` instantiates, subscribes `onChange`, disposes on unmount.
35. **Update `src/components/StatusLine.tsx`** to accept a `runningCost` prop. Replace the hardcoded `Σ$0.00` (line 64 in the file as of v7.0) with `Σ$${runningCost.toFixed(2)}` when > 0. Keep `Σ$0.00` for cold start.
36. **Rebuild the octmux binary** and smoke-test cost updates within ~5 s of turn completion. Verify against a session that produces non-zero cost (Brain on Opus 4.7).
37. **Update `docs/Stage7.md`** (oconona's) v7.5 status to `shipped` with octmux commit hash. Update octmux's own changelog. Update `docs/Stage7--Changelog.md` with v7.5 entry referencing the octmux commit.

### Deliverables (in octmux repo)

- `src/cost-aggregator.ts` (new)
- `src/app.tsx` updated
- `src/components/StatusLine.tsx` updated
- Rebuilt octmux binary
- octmux commit referenced in oconona's `docs/Stage7--Changelog.md`

### Handover notes

- After v7.5, the operator sees a live `Σ$X.XX` in the octmux status bar that updates within ~5 seconds of a paid response turn.
- The aggregator reads only `telemetry.json` files written by oconona. octmux does NOT query OC's SQLite DB directly — that coupling stays in oconona. If oconona's `telemetry.json` shape changes in a future stage, octmux's aggregator needs updating; the contract is documented in `docs/design.md` §Telemetry.
- Stage 6.3 (octmux orchestra inflight badge) was originally a separate sub-stage. If not yet shipped, it can fold into v7.5 or remain as a follow-on v7.6.

### Amendment 2026-05-29--07-54 — octmux uses OC SDK direct (from octmux /brain session)

**Status of v7.5:** approach revised; implementation pending in octmux repo (octmux Stage 8).
**Cross-reference:** octmux `docs/Stage8.md` · `oconona/docs/design.md` §Status line → §Amendment 2026-05-29--07-54.

#### What changed and why

The original v7.5 plan (Steps 33–35 above, now superseded) called for octmux to glob
`~/.config/opencode/orchestra/sessions/*/telemetry.json`, sum `cost_usd_estimate`, and display
the result in the status bar. The octmux `/brain` session (session `20260529T075453Z-2939750`,
2026-05-29) reviewed this approach and chose **Option A: OC SDK direct** instead.

Reasons:

1. **`telemetry.json` is written at session cleanup, not tick-time.** During any active orchestra
   session, `telemetry.json` for that session does not yet exist (or reflects the previous run).
   An aggregator reading it would display stale cost — the cost of the last completed session,
   not the current one.
2. **v7.2 removes `native-sessions/*.json`.** The "native cost" half of the original glob-sum
   disappears when v7.2 ships, leaving `telemetry.json` as the only file in the glob path. But
   see point 1: that file is absent during the very session whose cost we want to show.
3. **Symmetry with standalone-OC behaviour.** The standalone-OC status-line block reads live
   cost from OC's SQLite `session.cost` column. If octmux read `telemetry.json` (post-cleanup,
   stale) while standalone-OC reads live SQLite, the two would display different values for the
   same session. Option A is symmetric: both read live cost from the same underlying data via
   different access paths (HTTP SDK vs. direct SQLite).
4. **No oconona dependency at runtime.** octmux is a pure HTTP API consumer; coupling it to
   `oc-db.py`, to the `telemetry.json` shape, or to oconona's Python environment introduces a
   cross-repo coupling that breaks the layering. Option A removes this coupling entirely.

#### Replacement implementation (octmux Stage 8)

| Item | Detail |
|---|---|
| **Source** | `client.session.messages({ path: { id: sessionID } })` — sum `msg.info.cost` for `AssistantMessage` rows. Then `client.session.children({ path: { id: sessionID } })` — enumerate children, repeat per child. |
| **File** | `octmux/src/cost-aggregator.ts` (new) |
| **Cadence** | 5-second poll |
| **No `telemetry.json` reads** | octmux does NOT read or glob `telemetry.json` files |
| **No `oc-db.py` coupling** | octmux does NOT invoke or link any oconona Python scripts |
| **No Bun SQLite** | No direct SQLite reads in octmux |

In addition, the badge feature originally scoped as a possible v7.6 (Stage 6.3 — orchestra
inflight badge, referenced in the Handover notes above) has been **folded into Stage 8**.
Both the cost aggregator and the orchestra badge ship together in a single octmux rebuild and
commit as Stage 8. The badge reads `~/.config/opencode/orchestra/sessions/*/[.brain-inflight|.duo-inflight]`,
filters by `.project-dir` against `process.cwd()`, and reads `state.env` for the brain title.

#### Sequencing implication

Under the original plan, v7.5 depended on v7.3 because the `telemetry.json` shape had to be
stabilised before octmux could read it. **Under Option A, v7.5 has no hard dependency on any
prior oconona sub-stage.** The OC HTTP API has been stable since before Stage 7. octmux Stage 8
can ship independently of v7.1 / v7.2 / v7.3 / v7.4.

#### Revised deliverables for v7.5 (octmux Stage 8)

- `octmux/src/cost-aggregator.ts` — OC SDK direct poll; no `telemetry.json` reads
- `octmux/src/orchestra-watch.ts` — inflight marker watcher (folded in from original Stage 6.3)
- `octmux/src/app.tsx` — wiring of CostAggregator + OrchestraWatcher
- `octmux/src/components/StatusLine.tsx` — `runningCost` prop + `orchestraBadge` prop
- Rebuilt octmux binary; octmux `docs/Stage8.md` (new); memory update; git commit in octmux repo
- **No oconona files are modified by Stage 8** (these oconona doc amendments are the sole oconona-side output of this session)

### octmux notes — 2026-05-29 (Stage 8 shipped)

octmux Stage 8 (`feat(octmux): Stage 8 — live cost (OC SDK) + orchestra inflight badge`, commit `bd561fc`) implements the octmux side of v7.5. These notes document what shipped and what oconona must provide for the integration to work.

#### How octmux renders cost

Cost is summed event-driven (not polled): the existing `refreshTokenUsage()` in `src/app.tsx` is extended to also sum `AssistantMessage.cost` for all messages in the active session, then calls `client.session.children({ path: { id } })` and sums one level of child sessions. This runs on every `session-idle` SSE event (i.e. after each model response completes) and on session switches (cost resets to 0). Displayed as `Σ$X.XX` in the status bar; `Σ$0.00` for SoHoAI flat-rate sessions (OC reports cost=0 for those, which is correct).

No `telemetry.json` files are read. No `oc-db.py` coupling. Pure OC HTTP API.

#### How octmux renders the orchestra badge

`src/orchestra-watch.ts` (`OrchestraWatcher` class) uses Bun's `fs.watch()` on `~/.config/opencode/orchestra/sessions/` plus a 5-second `setInterval` fallback poll (handles missed events and NFS attribute cache lag). On each scan:
1. Glob all session subdirs.
2. Read `.project-dir` sidecar; skip if it doesn't match `process.cwd()`.
3. Skip if the inflight marker's `mtime` is older than 24 hours (stale-after-crash guard).
4. Check for `.duo-inflight` (priority) or `.brain-inflight`.
5. For `/duo`: read `.duo-inflight` content as title.
6. For `/brain`: read `ORCHESTRA_TITLE=` line from `~/.config/opencode/orchestra/state.env`.
7. Truncate title to 30 chars. Render as `♪ plan <title>` (duo) or `♪ brain <title>` (brain), color `#d3869b`.

#### What oconona must provide (contract)

| What octmux reads | Written by | Status |
|---|---|---|
| OC HTTP API `/session/{id}/message` — `AssistantMessage.cost` | OpenCode runtime | OC built-in, no oconona action needed |
| OC HTTP API `/session/{id}/children` | OpenCode runtime | OC built-in, no oconona action needed |
| `~/.config/opencode/orchestra/sessions/*/[.brain-inflight\|.duo-inflight]` | oconona `orchestra-hook.sh` + `/brain`/`/duo-plan` | Already deployed — stable since oconona Stage 5 |
| `${SESSION_DIR}/.project-dir` sidecar | oconona `/brain`/`/duo-plan` setup bash | Already deployed |
| `~/.config/opencode/orchestra/state.env` (`ORCHESTRA_TITLE=` line) | oconona `/brain` setup bash | Already deployed |

**No new oconona code, deploy steps, or configuration is needed for octmux Stage 8 cost or badge to function.** Both paths are stable against the current oconona deploy. This will remain true through oconona v7.1–v7.4. oconona v7.5's scope is superseded by this note; see Amendment 2026-05-29--07-54 above.

**Cross-reference:** octmux `docs/Stage8.md` · octmux commit `bd561fc`.

### octmux notes — 2026-05-29 (Stage 8.1 shipped)

octmux Stage 8.1 (`feat(octmux): Stage 8.1 — active subagent stage indicator`, commit `c30d30a`) adds the `▶ stage` real-time indicator.

#### How it works

`OrchestraWatcher.scan()` reads `~/.config/opencode/orchestra/invocations.log` synchronously on each scan (triggered by fs events or the 5-second fallback poll). It reverse-scans for the last `{"event":"start"}` and last `{"event":"end"}` lines, parses `.ts` and `.stage` fields as JSON, and compares timestamps lexicographically. If `start.ts > end.ts` (or no end event exists), the stage is active. The active stage label (`plan`, `implement`, `review`, `research`) is attached to `OrchestraBadge.stage` and rendered as `  ▶ <stage>` in yellow (`#d79921`) immediately after the badge title. The indicator only shows when the project-filtered badge is showing — it inherits the project filter implicitly.

#### What oconona must provide (contract)

| What octmux reads | Written by | Status |
|---|---|---|
| `~/.config/opencode/orchestra/invocations.log` — newline-delimited JSON with `event`, `stage`, `ts` fields | oconona `orchestra-hook.sh` PreToolUse(Agent) + SubagentStop hooks | Already deployed; explicitly preserved through v7.2 (`Keep: subagent start/end logging` per Stage7.md Step 9) |

**No new oconona code or deploy steps required.** The log is written by the current deploy and stable through all planned Stage 7 sub-stages.

**Cross-reference:** octmux `docs/Stage8.md` § Stage indicator · octmux commit `c30d30a`.

---

## Doc impact

| Doc | v7.1 | v7.2 | v7.3 | v7.4 | v7.5 |
|---|---|---|---|---|---|
| `docs/Stage7.md` | status marker update | status marker update | status marker update; fold `pre-Stage7` content into `design.md` (not here) | status marker update | status marker update |
| `docs/Stage7--Changelog.md` | new entry | new entry | new entry | new entry | new entry |
| `docs/design.md` | minor (mention `oc-db.py` exists if useful) | minor (mention `.oc-session-id` sidecar in artefact list) | **major** — fold `pre-Stage7--opencode-redesign.md` content into §Telemetry | none | none |
| `docs/pre-Stage7--opencode-redesign.md` | none | none | **deleted or tombstoned** after fold | none | none |
| `AGENTS.md` | minor | minor (drop `BASH_ENV` mention if present) | scripts inventory: add `oc-db.py`, drop 7 deleted scripts; remove CC-era smoke-test section | none | minor |
| `README.md` | none | none | drop T1/T2 / SoHoAI cost / pricing.yaml mentions | none | none |

## Risks / unknowns

1. **Confirmed Hypothesis B** (2026-05-29 DB inspection). `time_archived` is NULL for all
   observed sessions including those closed hours ago. OC never sets it on normal session
   close. The `time_updated < now - 30 min` fallback in `oc_db.is_session_over()` is
   **load-bearing**.
2. **`OC_SESSION_ID` availability in setup bash blocks.** Per `AGENTS.md` it is set in Bash subprocesses. v7.2 Step 11 depends on this. Smoke-test in v7.2 verifies by reading the resulting `.oc-session-id` and querying OC's DB.
3. **`OC session.agent` column values for subagent rows.** Empirically present (10 examples in the operator's DB). `oc-db.py` passes them through as-is. Risk: if values are OpenCode-internal symbols rather than human-readable strings, `telemetry.json` `subagents[].agent` may need a mapping. Document any mismatch in v7.1 changelog.
4. **2026-05-28 `sohoai/glm-5.1` cost anomaly.** OC's `cost` field is treated as truth unconditionally. No reconciliation. If future audit reveals systematic over-attribution, revisit at that point.
5. **Pre-v7.2 session-dirs** (created before v7.2 ships, no `.oc-session-id` sidecar) report `cost_usd_estimate = 0.0` in `telemetry.json`. `session-report.py` displays them as legacy or filters them out.
6. **`collect.sh` may not be in repo.** v7.3 Step 22 verifies before editing. If it exists only at deploy target, edit it there or skip.
7. **octmux Stage 6.3 status** (inflight badge): not in scope for Stage 7. If not yet shipped in octmux repo, v7.5 ships independently using the same `telemetry.json` contract.
8. **Schema drift risk** in future OC versions. Mitigated by `oc-db.py` self-check. One file to update on schema change.

## Out of scope

- Provider routing (SoHoAI Surface A — `provider.sohoai` block in `~/.config/opencode/opencode.json`). Unchanged.
- Orchestra pipeline workflow logic — `commands/` pipeline phases (Phase 0/1/2/3 in `/brain`, plan→act in `/duo`).
- Agent definitions — `agents/{planner,actor,actor-heavy,reviewer}.md`. Stage 6.1.1 `sohoai/*` IDs preserved.
- Session artefacts — `RESEARCH.md`, `PLAN.md`, `TASKS.json`, `review-comments.md`, `.outcome`, `.brain-inflight`, `.duo-inflight`, `state.env`. Unchanged.
- `oconona cleanup` CLI for pruning stale session dirs. Future work.
- Per-session cost breakdown UI in octmux. v7.5 ships totals only; per-tier UI is future work.
- `config/context-windows.yaml` (used by `ctx-segment.sh`) — unchanged.
- Frozen historical docs: `docs/design-history.md`, `docs/Sonnet-porting-plan.md`, `docs/Opus-porting-plan.md`, `docs/Glm--*.md`, `docs/Kimi-*.md`, `docs/Consolidated-migration-plan.md`, `docs/architecture-decisions.md`, `docs/architecture/*.md`. No touch.
- `docs/design.md:~320–340` (frozen sample `--tier` output block). No touch.

## Implementation log

Entries are appended as stages ship. Newest at top.

### 2026-05-29 — v7.1 shipped

**Commits:** `21c3bd3`

`scripts/oc-db.py` created. `scripts/telemetry-summarize.py` rewritten (852→~150 lines).
`telemetry.jsonl` global append dropped. Smoke tests T1–T8 PASS. Empirical findings:
`time_archived` Hypothesis B confirmed; `model` column is JSON.

### 2026-05-28 — v7.0 shipped

**Commits:** `de631cc` (main), `de40d03` (changelog backfill)

Doc restructure committed. See `docs/Stage7--Changelog.md` for delivery details.

*(Future v7.2–v7.5 entries appended here)*
