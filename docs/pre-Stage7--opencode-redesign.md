---
title: "Pre-Stage 7 — OpenCode-native telemetry redesign rationale"
created_at: 2026-05-28--18-16
created_by: Actor (Claude Haiku 4.5)
context: >
  Synthesized architectural rationale produced by Brain/Planner during the
  20260528T181605Z-2855594 session. Captures the decision to replace the T1/T2
  hybrid and SoHoAI cost-attribution path with OC-native SQLite telemetry.
  Transient staging doc; to be folded into docs/design.md after v7.1–v7.3 ship.
---

# Pre-Stage 7 — OpenCode-native telemetry redesign rationale

## Why T1/T2 was a CC-era workaround

The T1 (hook-based real-time events) and T2 (JSONL walking) framework solved a problem specific to Claude Code (CC), not OpenCode (OC). T1 hook events exposed no usage data—T1 was a dead-end even in claude-orchestra (operator's word: "T1 is essentially a dead-end"). T2 JSONL walking became necessary because CC's only authoritative cost record was its per-turn JSONL with `costUSD` fields. Neither applies to OC: OC writes no such JSONL shape, and its `@ai-sdk/anthropic` SDK populates cost directly into the `session` SQLite table.

## Why SoHoAI cost-attribution (Surface B) can be removed

OC's `@ai-sdk/anthropic` populates `cost` directly in the `session` SQLite row; `@ai-sdk/openai-compatible` correctly reports $0 for sohoai/* models (flat-rate marginal cost). SoHoAI billing database queries add nothing OC's session row doesn't already have. Empirically verified: 10 child sessions in the operator's database with `parent_id`, `agent`, `model`, `cost`, and `tokens_*` populated, demonstrating per-tier cost attribution works directly from OC's schema.

## SoHoAI dependency inventory (what remains after Surface B removal)

| Surface | What | Status after v7.X |
|---|---|---|
| A — Provider routing | `provider.sohoai` block in `~/.config/opencode/opencode.json`; agent frontmatter `model: sohoai/*` | Unchanged — required for flat-rate worker routing |
| B — Cost attribution | `query_sohoai_usage`, `query_sohoai_cost`, `sohoai-live-cost.sh`, `config.yaml:sohoai:` block, `active-sessions/*.lck` mechanism, `otel-headers-helper.sh` | Removed by v7.1–v7.3 |

## OC SQLite schema — empirical validation

- **DB path:** `~/.local/share/opencode/opencode.db`
- **`session` table columns used:** `cost`, `tokens_input`, `tokens_output`, `tokens_reasoning`, `tokens_cache_read`, `tokens_cache_write`, `model`, `agent`, `parent_id`, `time_created`, `time_updated`, `time_archived`, `directory`
- **Per-tier breakdown:** `WHERE parent_id = <parent>` returns child rows for each subagent dispatch
- **WAL mode confirmed safe:** `PRAGMA journal_mode` returned `wal`; read-only opens safe with `?mode=ro&immutable=0` URI flag
- **Local NVMe storage:** stored at `/dev/nvme0n1p7`, not NFS; no distributed locking concerns
- **Performance validated:** 5-reader × 100-query stress test completed in 12ms total (sub-millisecond per query)

## Design choices made

- **SQLite read-only (not HTTP API):** offline reporting works without OC server alive; <5 ms latency per query vs ~5 ms/turn HTTP roundtrip; allows `session-report.sh` to run from cron or cold start.
- **Full Surface B removal (not hybrid):** half-measure encodes a dead-end; sohoai/* cost is $0 anyway under flat-rate, so SoHoAI billing DB adds no new signal.
- **T1/T2 dropped entirely:** clean cut is cleaner than phased rollout; a phased approach would preserve the very framework we're trying to escape.
- **Schema coupling localized to `scripts/oc-db.py`:** future OC schema changes affect exactly one file; schema self-check at first open emits clear error if columns missing.
- **`time_archived` dual-check:** `time_archived IS NOT NULL OR time_updated < now - 30min` covers both possible semantics (whether OC sets it on session end or only on explicit archival).
- **Note on the 2026-05-28 glm-5.1 anomaly:** one historical session showed non-zero cost (`$0.048`) for a `sohoai/glm-5.1` model via OC's AI-SDK, contradicting the flat-rate-marginal-zero assumption. Resolution: OC's `cost` field is treated as truth unconditionally; we don't second-guess.

## Risks and mitigations

- **OC schema drift:** localized to oc-db.py; schema self-check at startup emits clear error if expected columns missing.
- **`OC_SESSION_ID` availability in setup bash:** verified at v7.2 (Session initialization captures env var into `.oc-session-id` sidecar; smoke test confirms row exists in SQLite).
- **SQLite WAL concurrent reads:** safe by design; read-only opens require no locks.
- **Per-tier child-session attribution depends on OC creating child sessions for Task-tool dispatches:** empirically present (10 already in operator's DB); smoke test in v7.1 verifies child-session creation for subagent dispatches.

## Forward pointer

This file is transient. After v7.1–v7.3 ship, its content will be folded into `docs/design.md` §Telemetry, replacing the stale T1/T2 and SoHoAI proxy sections. Track implementation in `docs/Stage7.md` v7.3 deliverables.
