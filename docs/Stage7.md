---
title: "Stage 7 — OC-native telemetry redesign roadmap"
created_at: 2026-05-28--18-16
created_by: Actor (Claude Haiku 4.5)
context: >
  Stage 7 roadmap doc, produced by Brain/Planner session
  20260528T181605Z-2855594. Tracks the v7.0–v7.5 sub-stages replacing the
  T1/T2 SoHoAI cost-attribution telemetry with OC-native SQLite telemetry.
---

# Stage 7 — OC-native telemetry redesign roadmap

## One-line intent for Stage 7

After Stage 7 ships, the T1/T2 hybrid and SoHoAI cost-attribution path (Surface B) are fully removed; a single OC-native SQLite-backed telemetry plane handles per-turn visibility and post-hoc reporting; ~1500 lines of CC-era workaround code are replaced by a thin `scripts/oc-db.py` helper module.

## Stage 7 sub-stage roadmap

| Stage | Scope | Status |
|---|---|---|
| **v7.0** | Doc restructure: `docs/pre-Stage7--opencode-redesign.md` + `docs/Stage7.md` + `docs/Stage7--Changelog.md` + delete Stage6 docs + clean `docs/design.md` stale refs | shipped (this commit) |
| **v7.1** | `scripts/oc-db.py` (new SQLite helper) + `scripts/telemetry-summarize.py` rewrite — read from OC SQLite instead of T2 JSONL | not started |
| **v7.2** | `scripts/orchestra-hook.sh` T1/T2 strip + commands setup/cleanup block updates — drop `active-sessions/*.lck` writes, add `.oc-session-id` sidecar capture | not started |
| **v7.3** | Status-line rewrite + `session-report.py` rewrite + dead file deletion (`sohoai-live-cost.sh`, `otel-headers-helper.sh`, `bash-session-init.sh`, `native-session-finalize.py`, `native-subagent-cost.sh`) + `deploy.sh`/`collect.sh` updates + fold `docs/pre-Stage7--opencode-redesign.md` into `docs/design.md` | not started |
| **v7.4** | Carry-forward of original Stage 6.2 model-relaxation for `/duo` (per-role `config.yaml models:`, deploy.sh materialisation, Anthropic rate refresh) | not started |
| **v7.5** | octmux integration — replace glob+sum cost aggregator with OC SQLite reader via `telemetry.json` shape; carry-forward of original Stage 6.4 | not started |

## Stage 6 sub-stage status mapping

| Stage 6 sub-stage | Commits | Status | Notes |
|---|---|---|---|
| Stage 6.1 — Dual-stream writers + path audit | `f39e96c` (code), `cbfc067` (docs) | PARTIALLY SUPERSEDED | Path audit (`~/.config/opencode/orchestra/` migration), `.project-dir` sidecar, `deploy.sh` `agent/`→`agents/` fix: PRESERVED. Writer A (native residual tick), Writer B (orchestra partial telemetry), glob+sum cost path: SUPERSEDED by v7.1–v7.3. |
| Stage 6.1.1 — `claude-code-*` alias purge | `67a1434` | PRESERVED (load-bearing) | Agent frontmatter `sohoai/*` IDs required for OC dispatch. `Σ$` status-line prefix preserved. `oc-db.py` (v7.1) will read these same `sohoai/*` model IDs from the session table. |
| Brain Opus 4.7 advisory + commands/agents clarification | `a90b4dc` | PRESERVED | Advisory-only model check carries forward unchanged into Stage 7. Commands/agents distinction doc unchanged. |
| Doc-hash backfills | `e15d904`, `1a9a010`, `774d71d`, `1f4271f`, `cbfc067` | PRESERVED | No conflict with Stage 7 work. Historical record. |

## Dependencies and sequencing

v7.1 is a prerequisite for v7.2 (oc-db.py must exist before commands reference it); v7.2 is a prerequisite for v7.3 (dead files cannot be deleted until their callers are updated); v7.4 and v7.5 are independent of v7.1–v7.3 but benefit from v7.1's telemetry shape stabilization; v7.5 requires v7.3 to have shipped the final `telemetry.json` shape.

## Changelog

See `docs/Stage7--Changelog.md` for per-commit entries.
