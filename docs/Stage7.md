---
title: "Stage 7 — OC-native telemetry redesign roadmap"
created_at: 2026-05-28--18-16
created_by: Actor (Claude Haiku 4.5)
updated_by: Actor (Claude Haiku 4.5 — via oconona /brain Stage 8 dispatch)
updated_at: 2026-06-05--13-00
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
| **v7.3** | Status-line rewrite + `session-report.py` rewrite + dead file deletion (`sohoai-live-cost.sh`, `otel-headers-helper.sh`, `bash-session-init.sh`, `native-session-finalize.py`, `native-subagent-cost.sh`) + `deploy.sh`/`collect.sh` updates + fold `docs/pre-Stage7--opencode-redesign.md` into `docs/design.md` | shipped (commit `76b9800`) |
| **v7.3.5** | Token accounting for hybrid orchestra — Reviewer revert to Sonnet 4.6 + `scripts/model-rates.yaml` (TTL-parameterised) + `_compute_hybrid_attribution()` in oc-db.py + per-agent cost delineation in session-report.py + `verify-cost-rates.py` rate-drift detector (Check D) | shipped (commit `ba998ee`) (hotfix 1) (hotfix 2) (hotfix 3) |
| **v7.4** | Config rename + dead-key purge + CC-ism sweep + parked-file deletion | shipped (commit `f4e06f1`) |
| **v7.5beta** | SSOT tier config + deploy-time audit script + arch sweep | shipped (commit `4c1e292`) |
| **v7.5** | per-OC-session-segment attribution + hierarchical badge + harness contract doc | shipped (commit `eb540aa`) |
| **v7.5.1** | SoHoAI tier-model remap (Planner→minimax-m3, Actor→qwen3-4b-q6, Actor-heavy→glm-5.1) | shipped (commit `4184f4b`) |

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
 ├──→ v7.4 (config rename + CC-ism sweep)
 ├──→ v7.5beta (SSOT tier config + audit)
 └──→ v7.5 (per-segment attribution + badge + harness contract)
```

v7.4, v7.5beta, and v7.5 are independent of each other and can ship in any order once v7.3 has stabilised the telemetry.json contract. v7.5.1 is a config-only model remap; no new mechanisms or telemetry shape changes. A future unnumbered octmux refactor `/brain` session will consume `docs/Stage7.5--implementation-details.md` to revise octmux's `docs/Stage8.md`.

## v7.5.1 — SoHoAI tier-model remap

Configuration-only update: Planner, Actor, and Actor-Heavy tiers remapped to different SoHoAI models per operator-directed SoHoAI model rebalance (session 20260603T213230Z-814278). No new mechanisms. SSOT (`config/orchestra-tiers.yaml`) updated; agent frontmatter, model-rates.yaml, context-windows.yaml, and user-facing docs synced via `check-tiers.py` audit (0 hard-fails, 0 soft-warns). Verify systemd restart post-deploy.

## Architecture (post-Stage-7)

### Single source of truth

OC's SQLite `session` table at `~/.local/share/opencode/opencode.db`. The `session` row carries `cost`, `tokens_input`, `tokens_output`, `tokens_reasoning`, `tokens_cache_read`, `tokens_cache_write`, `model`, `agent`, `parent_id`, `time_created`, `time_updated`, `time_archived`, `directory`. The `@ai-sdk/anthropic` provider populates `cost` accurately for Anthropic-routed sessions. The `@ai-sdk/openai-compatible` provider correctly reports `cost = 0` for `sohoai/*` (flat-rate marginal).

The `model` column stores a JSON object `{"id":"...","providerID":"...","variant":"..."}`.
`oc-db.py`'s `_parse_model()` helper extracts the `id` field; falls back to raw string
for NULL or non-JSON values.

### Per-tier breakdown via `parent_id`

OC creates child sessions for every `Task`-tool dispatch. Querying `WHERE parent_id = <brain_session_id>` returns one row per subagent dispatch, each with its own `agent` (`planner`, `actor`, `actor-heavy`, `reviewer`, etc.), `model` (the resolved provider/model JSON), `cost`, and `tokens_*`. The OC daemon populates `agent` and `model` at session-create time from the Task-tool `subagent_type` parameter and the resolved agent frontmatter. No SoHoAI session-ID tagging is required.

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
- **Session-dir reaper**: `find ~/.config/opencode/orchestra/sessions -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} +` runs at every orchestra setup (existing housekeeping, preserved). Retention configurable in `config/oconona-config.yaml:housekeeping.session_retention_days`.


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

---

## Stage v7.4 — Config rename + dead-key purge + CC-ism sweep

### Scope

The global config file is renamed `config/config.yaml` → `config/oconona-config.yaml` (deployed name also moves to `~/.config/opencode/orchestra/oconona-config.yaml`). The config file shrinks from 8 unused top-level keys to just `housekeeping:` — every removed key was dead code (no live consumer; the `sohoai:` block had been orphaned since v7.1 when its consumer functions were deleted from `telemetry-summarize.py`). All remaining CC-isms (`ExitPlanMode`, `bypassPermissions`, `Shift+Tab`, `--dangerously-skip-permissions`, `plan-mode`, `claude-code-*` aliases) are purged from live (non-historical) files. The frozen `--tier` sample block in `docs/design.md` is also updated to current `sohoai/*` IDs. The parked `to-be-reviewed--AGENTS.md` (superseded by `AGENTS.md` in v7.3) is removed.

### Numbered steps

28. **Rename `config/config.yaml` → `config/oconona-config.yaml`** via `git mv`. Update the 9 live references across the repo (`commands/{brain,duo-plan}.md`, `deploy.sh`, `collect.sh`, `status-line/orchestra-block.sh`, `utils/snapshot_codebase.py`, `AGENTS.md`, `README.md`, `docs/{Stage7,design}.md`).
29. **Strip dead keys** from the renamed config — drop `orchestra_mode`, `gates:`, `approval_method`, `review_loop_max`, `commit:`, `crosscheck_loop_max`, `token_budget_usd`, `commit_auto:`, `test_gate:`, full `sohoai:` block. Keep only header + `housekeeping:`.
30. **CC-ism sweep across live files** — `docs/design.md`, `README.md`, `docs/resources.md`, `deploy.sh` (comments), `config/oconona-config.yaml` (header). Delete (per operator override) the two historical CC-only amendment paragraphs in `docs/design.md` ("Pipeline-rules guard 2026-05-05" and "/duo-plan setup-bash override 2026-05-06"). Update the frozen sample `--tier` block in `docs/design.md` from `claude-code-*` IDs to `sohoai/*` + `anthropic/claude-sonnet-4-6`.
31. **Delete `to-be-reviewed--AGENTS.md`** via `git rm`.
32. **Update `docs/Stage7.md` v7.4 status to `shipped`**, refresh frozen-exclusion line (now at `docs/design.md:~383–396`). Prepend Stage v7.4 entry to `docs/Stage7--Changelog.md`.

### Deliverables

- `config/config.yaml` → `config/oconona-config.yaml` (renamed, stripped to ≤15 lines: header + `housekeeping:`)
- 9 reference-path updates across the repo
- `docs/design.md`, `README.md`, `docs/resources.md`, `deploy.sh` CC-ism sweeps
- `to-be-reviewed--AGENTS.md` deleted
- `docs/Stage7.md` + `docs/Stage7--Changelog.md` updates

### Handover notes

- The `sohoai:` block removal in v7.4 cleans up a long-orphaned config block — it had been dead since v7.1 (when its consumer functions were deleted from `telemetry-summarize.py`). No runtime behaviour changes.

---

## Stage v7.5 — per-OC-session-segment attribution + hierarchical badge + harness contract doc

### Scope

Each `/brain` and `/duo` orchestration run now attributes cost and tokens only to itself (no double-counting across multiple runs in the same OC session) via snapshot-delta mechanics. The status-line badge follows the symmetric format `♪ orchestra -> <title> -> <mode> [-> <subagent>]` with mode segment always present. Reporting scripts surface per-segment breakdowns. A new authoritative contract document `docs/Stage7.5--implementation-details.md` documents the filesystem sidecar layout, badge rendering, and telemetry shape for any OC harness consumer (octmux + future TUIs).

### Numbered steps summary

1. `oc-db.py`: add `get_session_snapshot()` + `get_child_sessions_in_window()` (lightweight point-in-time snapshots + time-window child filtering).
2. `commands/brain.md` + `commands/duo-plan.md`: add `.parent-snapshot-start` capture at setup (NEW).
3. All cleanup paths (brain.md, duo-act.md, duo-abandon.md, brain-abandon.md, orchestra-hook.sh): add `.parent-snapshot-end` capture AFTER outcome + BEFORE telemetry-summarize.sh (NEW).
4. `telemetry-summarize.py`: rewrite for per-segment attribution; new fields `parent_delta`, `parent_total`, `started_at_oc_ms`, `ended_at_oc_ms`, `parent_snapshot_*`, `parser_warnings`.
5. `orchestra-block.sh`: symmetric badge format `♪ orchestra -> <title> -> <mode> [-> <subagent>]`; subagent role from `invocations.log` `subagent` field.
6. `session-report.py`: surfaces `parent_delta.cost`, `parent_total.cost`, `parser_warnings` in `--hybrid-detail` mode.
7. `telemetry-report.sh`: fix latent `--tier` bug (flat `tokens_*` fields, not nested dict) + new shape compat.
8. `smoke-test.sh`: Check E verifies snapshot sidecars exist + valid JSON. `TOTAL_CHECKS=5`; pre-v7.5 sessions skipped.
9. NEW `docs/Stage7.5--implementation-details.md`: 14-section authoritative contract for harnesses (sidecars, badge, invocations.log, telemetry.json v7.5 shape, match key, write-order invariants, crash recovery, deprecations, harness checklist).
10. Update `docs/Stage7.md`: relabel v7.5→v7.5beta; add new v7.5 section; remove legacy octmux row.
11. Update `docs/Stage7--Changelog.md`: prepend v7.5 entry referencing code commit.
12. Update `docs/design.md`: new per-segment-attribution subsection; symmetric badge table; data sources update; Amendment 2026-05-29--07-54 forward-pointer; sidecar inventory.
13. Update `docs/TODO.md`: prepend v7.5-delivered entry; note octmux refactor as separate future /brain cycle; C-γ deferred.

### Deliverables

**Code files (steps 1–8):**
- `scripts/oc-db.py` — two new public functions
- `commands/brain.md`, `commands/duo-plan.md` — snapshot-start capture
- `commands/brain.md`, `commands/duo-act.md`, `commands/duo-abandon.md`, `commands/brain-abandon.md`, `scripts/orchestra-hook.sh` — snapshot-end capture
- `scripts/telemetry-summarize.py` — per-segment rewrite
- `status-line/orchestra-block.sh` — symmetric badge
- `scripts/session-report.py` — hybrid-detail flag + new fields
- `scripts/telemetry-report.sh` — latent bug fix + shape compat
- `scripts/smoke-test.sh` — Check E snapshot validation

**Documentation files (steps 9–13):**
- `docs/Stage7.5--implementation-details.md` (NEW; 14 sections; authoritative harness contract)
- `docs/Stage7.md` — relabel, new section, remove legacy octmux row
- `docs/Stage7--Changelog.md` — v7.5 entry
- `docs/design.md` — attribution subsection, badge table, Amendment forward-pointer
- `docs/TODO.md` — v7.5 closed entry

### Handover notes

Detailed mechanics are documented in the new `docs/Stage7.5--implementation-details.md` — required reading for any OC harness consuming the snapshot sidecars, badge format, and telemetry shape. The contract supersedes octmux `docs/Stage8.md` §C-α and §Stage indicator.

A **future, unnumbered, separate `/brain` cycle** (octmux refactor) will consume `docs/Stage7.5--implementation-details.md` to revise/replace/refactor octmux's stale `docs/Stage8.md`. That session will update octmux's badge renderer to use `.oc-session-id` match key instead of `.project-dir` + `process.cwd()`, and will adopt the symmetric badge format. **This `/brain` does NOT touch any octmux files.**

---

## (Deprecated section below — Stage v7.5 old plan for octmux integration)

### Stage v7.5 — octmux integration (carry-forward of Stage 6.4) [SUPERSEDED]

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
- Stage 6.3 (octmux orchestra inflight badge) was originally a separate sub-stage. If not yet shipped, it can fold into v7.5 or remain as a follow-on octmux refactor cycle.

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

In addition, the badge feature originally scoped as a possible follow-on cycle (Stage 6.3 — orchestra
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
- `docs/design.md:~383–396` (frozen sample `--tier` output block). No touch.

## Implementation log

Entries are appended as stages ship. Newest at top.

### 2026-05-31 — v7.4: oconona-config.yaml rename + dead-key purge + CC-ism sweep

**Commit:** `f4e06f1`
**Scope:** Touches v7.0–v7.3.5 deliverables — `config/` (rename + content strip), `commands/{brain,duo-plan}.md` (reference path), `deploy.sh`/`collect.sh`/`status-line/orchestra-block.sh` (reference paths), `AGENTS.md`/`README.md` (reference + CC-ism), `docs/{design,resources}.md` (CC-ism + reference), `to-be-reviewed--AGENTS.md` (deleted).

The trigger for this rescoping was investigation of `config/config.yaml`'s actual usage post-Stage-7. Audit showed **only one of nine top-level keys was consumed by live code** (`housekeeping.session_retention_days`, read by setup-bash in `commands/{brain,duo-plan}.md`). The `sohoai:` block had been orphaned since v7.1 (`21c3bd3`) when its consumer functions (`_load_sohoai_config`, `query_sohoai_usage`, `query_sohoai_cost`) were deleted from `telemetry-summarize.py`. The `gates:`, `approval_method`, `commit:`, `commit_auto:`, `test_gate:`, `crosscheck_loop_max`, `token_budget_usd`, `orchestra_mode` keys were never wired in the OC port — they were CC-orchestra v2-stub holdovers carried forward unaltered. The rename + radical key purge cleans the file from 68 lines to 9 lines and disambiguates its filename from generic "config.yaml" patterns.

The final CC-ism sweep closes v7.3.5's loose ends — the v7.3 hotfix `#4` (`a676e18`) and `#5` (`a990703`) cleaned operator-facing files (`commands/*.md`, `agents/*.md`, command-frontmatter descriptions, the `agents-md-block/orchestra-guard.md` injection), but did not touch `docs/design.md`, `README.md`, `docs/resources.md`, or `deploy.sh` comments. v7.4 closes that gap. The frozen `--tier` sample block in `docs/design.md` (L383–396) was originally exempted from the sweep per Stage7.md:537 ("No touch"), but its `claude-code-*` model IDs were stale post-Stage-6.1.1 alias purge (`67a1434`). v7.4 updates the sample to current `sohoai/*` + `anthropic/claude-sonnet-4-6` IDs and updates the exclusion line accordingly. Two CC-only historical amendment paragraphs in `docs/design.md` ("Pipeline-rules guard 2026-05-05" and "/duo-plan setup-bash override 2026-05-06") describing failure modes that don't exist in OC were deleted per operator override ("delete rather than rewrite, fine-tune later"). The "Aligned with canonical:" list in `docs/design.md §Deviations from canonical OpenCode` was reduced from 5 bullets to 3 — two bullets conflated octmux permission modes (`ask`/`allow`/`deny`) with OC canonical (`default`/`acceptEdits`/`plan`/`bypassPermissions`); operator chose deletion over re-writing pending a fine-tune pass with OC-native terminology.

### 2026-05-30 — v7.3 hotfix: restore native-session-report + smoke-test deploy/import + $HOME-cwd advisory

**Commits:** `7fabdaa`
**Scope:** Touches v7.3 deliverables — `scripts/` (`smoke-test.sh`, new `native-session-report.{sh,py}`), `deploy.sh`, `commands/{brain,duo-plan}.md`. Three small issues surfaced by the end-to-end smoke test:

1. **`native-session-report.{sh,py}` restored (OC-SQLite-sourced).** v7.3 (`76b9800`) deleted the CC-era native-session reporter. Per `claude-orchestra` convention (see `~/Gin-AI/projects/claude-orchestra/scripts/` and its `docs/design.md`), every Python report should have a `.sh` wrapper (+x) that calls the `.py` impl (not +x). `session-report.{sh,py}` already followed this; native-session-report was the missing pair. New OC version walks OC's DB for `parent_id IS NULL` sessions and excludes any whose `id` appears in some orchestra session_dir's `.oc-session-id` sidecar.

2. **`smoke-test.sh` deploy + `oc_db` import fix.** `deploy.sh` `Scripts:` loop omitted `smoke-test.sh` entirely — `~/.config/opencode/scripts/smoke-test.sh` never existed post-deploy. Check B's `import oc_db` failed because the deployed file is `oc-db.py` (hyphen) which Python can't `import` by that name. Replaced with `importlib.util.spec_from_file_location` (same pattern as `scripts/telemetry-summarize.py`). Bonus: Check C's `total_tokens` now includes `cache_read + cache_write`, matching the v7.3 hotfix #2 fix to `session-report.py` (previously displayed 119K for a 457K-token session).

3. **`$HOME`-cwd advisory in `brain.md` + `duo-plan.md` setup bash (nice-to-have).** When OC's daemon is launched from `$HOME` with no project anchor (the systemd-unit pattern `WorkingDirectory=%h`), relative paths in `/brain` / `/duo-plan` prompts resolve against `$HOME`, not octmux's launch directory. Setup bash now emits 3 `WARN:` lines explaining this so Brain/Planner surface it in Phase 0. The long-term systemic fix lives in octmux — pass `process.cwd()` to `client.session.create({})` — out of scope here.

`deploy.sh` also reorganized: shell wrappers all in one `+x` loop, Python impls all in one no-chmod loop, header clarifies the wrapper-and-implementation convention so future additions don't drift.

Verified post-deploy: `~/.config/opencode/scripts/native-session-report.sh --last 5` shows 5 non-orchestra OC sessions with costs; `~/.config/opencode/scripts/smoke-test.sh <prior-passing-session>` is 3/3 PASS with the corrected 457,388 token total.

### 2026-05-29 — v7.3 hotfix: drop CC-isms, use OC-native permission vocabulary

**Commits:** `a676e18`
**Scope:** Touches v7.0 / v7.2 deliverables — `commands/{brain,duo-plan,duo-act,duo-abandon,brain-abandon}.md` and `agents/{planner,actor,actor-heavy,reviewer}.md`.

The orchestra commands and `agents/planner.md` were ported from `claude-orchestra` and still contained Claude-Code-specific mechanics that have no equivalent in OC 1.15.11: "Plan mode is active" prerequisites + "Shift+Tab" instructions, `ExitPlanMode` tool-call references, "auto-edit / manually approve / cancel" UX descriptions, `--dangerously-skip-permissions` flag references, and a defensive "Override of plan-mode's plan-file directive" section in `brain.md` that guarded a CC reminder OC doesn't emit. Symptom (verified in the v7.3 hotfix #1 smoke-test session): Opus had to *roleplay* the approval gate because `ExitPlanMode` doesn't exist; tool call silently failed and the model narrated around it.

Replaced throughout with the OC + octmux native vocabulary documented in `octmux/docs/Stage5.md §5.3` (octmux commit `2d440b9`): octmux's global permission mode (`ask` yellow / `allow` green / `deny` red, cycled with **Shift-TAB**), covering all OC tool categories (filesystem `read`/`edit`/`glob`/`grep`/`list`, shell `bash`, network `webfetch`/`websearch`, repository `repo_clone`/`repo_overview`, agents `task`/`skill`, other `external_directory`/`lsp`/`todowrite`). Plan approval is a natural-language operator signal (`"approved"`/`"go ahead"`/`"proceed"`) — no tool call gates it.

Each agent body now carries an explicit "frontmatter grants X; runtime mode determines per-call behaviour" sentence to make the two-layer permission model (frontmatter `tools:` + runtime mode) visible. The two stack: a tool denied in either layer cannot be authorised by the other (e.g., Planner stays read-only even under `allow`).

**Pipeline semantics unchanged.** Brain/Planner/Actor/Reviewer phases, session-dir artefacts, atomic-rename, cleanup ordering — all identical. Verified `opencode agent list` still shows all four agents registered post-deploy; deploy-time `actor` → `actor-heavy` body-mirror invariant maintained (framing sentence added after the `You are the Actor tier` marker in both, so structural-drift check passes).

### 2026-05-29 — v7.3 hotfix: resolve OC session ID via HTTP API

**Commits:** `51073cf`
**Scope:** Touches v7.2 (`commands/brain.md`, `commands/duo-plan.md`, originally `0479ea8`) deliverables.

The v7.2 setup-bash assumed OC exports `OC_SESSION_ID` into bash subprocesses. **OC 1.15.11 does not.** Verified by extracting the binary's full `OPENCODE_*` env-var list — no `OPENCODE_SESSION_ID`, no `OC_SESSION_ID`. The assumption traces back to early Stage 6 (and the deleted `scripts/bash-session-init.sh` used the same env var name as its primary key); either OC dropped it in a past version or it was never exported.

Consequence: `.oc-session-id` has been silently empty in every orchestra session since v7.2 → `telemetry-summarize.py` produces `cost_source: "none"`, zero totals. OC's DB has the correct data throughout; the sidecar contract just never connected to it. Verified against `ses_18c16888dffe0njgOjZs0MXnge` (octmux smoke test 2026-05-29 13:27Z): OC's `session` row has the right cost ($0.7787, Opus 4.7) + 3 child sessions (planner/actor/reviewer with `parent_id` correctly set); orchestra `telemetry.json` for the same session has all zeros and `oc_session_id: ""`.

Fix: replace the `${OC_SESSION_ID:-}` write with an HTTP-API query that hits `GET /session` (port from `OPENCODE_PORT` env var, default 4096), filters to top-level sessions in the current directory, takes the most-recently-updated one. Requires `curl` (universal) and `jq` (already a deploy prereq). Falls back to empty on API failure — same degraded behaviour as pre-fix, no regression.

Verified the snippet against the live OC server: correctly resolves `ses_18c16888dffe0njgOjZs0MXnge` for `directory = /home/florian`.

### 2026-05-29 — v7.3 hotfix: cache_read+cache_write in token totals

**Commits:** `d4b1ab7`
**Scope:** Touches v7.1 (`scripts/oc-db.py`, originally `21c3bd3`) and v7.3 (`scripts/session-report.py`, originally `76b9800`) deliverables.

`oc_db.get_session_telemetry()` was building `totals` with only `cost_usd_estimate, tokens_input, tokens_output, tokens_cache_read` — `tokens_cache_write` was missing. `session-report.py` was then summing `tokens_input + tokens_output` only and displaying that as the "Tokens" column.

Symptom (verified against `ses_18c3a3e2fffeZg3SOuHaCnoJOy`, Opus 4.7 Brain session): displayed Tokens = 11,891. Real volume processed by OC = 489,813 (37 input + 11,854 output + 438,260 cache_read + 39,662 cache_write). Display understated by ~97.5% for cached-heavy sessions.

**Cost was unaffected** throughout — `cost_usd_estimate` is read from OC's `cost` column, which already includes cache pricing at the correct rates. The hotfix is display-only.

Fix: oc-db.py totals now sum `tokens_cache_write` too (and the not-found fallback's zero totals carry the same shape). session-report.py adds cache-read and cache-write into the displayed total.

### 2026-05-29 — v7.3 hotfix: agent `tools:` frontmatter as YAML object

**Commits:** `7310878`
**Scope:** Touches v7.0 / v7.2 agent deliverables (frontmatter shape predates Stage 7 but surfaced when v7.3 made `/brain` exercisable end-to-end).

OC 1.15.11 rejects `tools:` as a comma-separated string with `Expected object | undefined, got "Read, Grep, ..." tools`. One bad agent file silently kills the entire `~/.config/opencode/agents/` discovery — `opencode agent list` fails, Brain sees only the built-in `general`/`explore` subagents, and Phase 1 dispatch fails with "Unknown agent type: planner".

Verified the failure mode against `ses_18c3a3e2fffeZg3SOuHaCnoJOy` (octmux `/brain` session, 2026-05-29 12:49Z): parent row present, **0 child sessions** in OC's DB — confirming Planner Task dispatch never created a child row.

Fix: reformatted `tools:` to a YAML map (`Read: true\nGrep: true\n...`) in all four agents — `planner.md`, `actor.md`, `actor-heavy.md`, `reviewer.md`. Verified with `opencode agent list` — planner/actor/actor-heavy/reviewer now register as `(all)` mode.

### 2026-05-29 — v7.3 shipped

**Commits:** `76b9800`

status-line/orchestra-block.sh rewritten to read OC SQLite via oc-db.py (SoHoAI/lck/glob+sum removed).
scripts/smoke-test.sh rewritten: 3 OC-native checks (sidecar, DB row, telemetry.json).
scripts/session-report.py: walks sessions/*/telemetry.json (native session reads removed).
scripts/telemetry-report.sh: walks sessions/ directly, no pricing.yaml needed.
Dead files deleted: bash-session-init.sh, native-session-finalize.py, native-subagent-cost.sh,
  sohoai-live-cost.sh, otel-headers-helper.sh, native-session-report.{sh,py}, pricing.yaml.
deploy.sh: adds oc-db.py copy, orphan cleanup for 8 deleted files, auto-creates AGENTS.md.
AGENTS.md: created from to-be-reviewed--AGENTS.md, updated with v7.3+ content.
docs/design.md: §OC SQLite schema subsection added; pre-Stage7 forward pointers removed.
docs/pre-Stage7--opencode-redesign.md: tombstoned (breadcrumb preserved).

### 2026-05-29 — v7.2 shipped

**Commits:** `0479ea8`

scripts/orchestra-hook.sh: stripped T1/T2 event capture, added .oc-session-id sidecar write.
commands/*: setup/cleanup blocks updated to drop active-sessions/*.lck writes.

### 2026-05-29 — v7.1 shipped

**Commits:** `21c3bd3`

`scripts/oc-db.py` created. `scripts/telemetry-summarize.py` rewritten (852→~150 lines).
`telemetry.jsonl` global append dropped. Smoke tests T1–T8 PASS. Empirical findings:
`time_archived` Hypothesis B confirmed; `model` column is JSON.

### 2026-05-28 — v7.0 shipped

**Commits:** `de631cc` (main), `de40d03` (changelog backfill)

Doc restructure committed. See `docs/Stage7--Changelog.md` for delivery details.
