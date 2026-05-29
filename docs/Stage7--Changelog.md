---
title: "Stage 7 Changelog — oconona"
created_at: 2026-05-28--18-16
created_by: Actor (Claude Haiku 4.5)
updated_by: Actor (Claude Haiku 4.5)
updated_at: 2026-05-29--12-37
context: >
  Reverse-chronological implementation log for Stage 7 OC-native telemetry
  redesign. Carries forward Stage 6 entries with status annotations. Newest
  entries at top.
---

# Stage 7 Changelog

Entries are reverse-chronological. Newest at the top.

---

## 2026-05-29 — v7.1: `oc-db.py` + `telemetry-summarize.py` OC-SQLite rewrite

**Commit:** `<hash>` *(backfilled after commit)*

### Empirical findings

- **`time_archived` Hypothesis B confirmed** (2026-05-29 DB inspection): `time_archived` is
  NULL for all observed sessions including those closed hours ago. OC never sets it on normal
  session close. The `time_updated < now - 30 min` fallback in `oc_db.is_session_over()` is
  **load-bearing**, not just defensive.

- **`model` column is JSON**: OC's `session.model` stores a JSON object
  `{"id":"kimi-k2.6","providerID":"sohoai","variant":"default"}`. `oc-db.py`'s `_parse_model()`
  extracts the `id` field; falls back to the raw string for NULL or non-JSON values.
  Stage7.md originally assumed plain strings — corrected in this commit.

- **File disambiguation**: `telemetry.json` (per-session, at
  `sessions/<UTC-ts>-<PID>/telemetry.json`) is distinct from `telemetry.jsonl` (global
  append-only index at `orchestra/telemetry.jsonl`). The latter is dropped here; v7.3's
  `session-report.py` rewrite will walk `sessions/*/telemetry.json` directly.

### Delivered

- **`scripts/oc-db.py`** (new, ~90 lines): read-only OC SQLite helper. Functions:
  `open_db()`, `_check_schema()`, `_parse_model()`, `get_session()`, `get_child_sessions()`,
  `is_session_over()`, `_zero_tier()`, `_row_to_tier()`, `get_session_telemetry()`.
  Safety: `?mode=ro` URI, WAL, 5 s timeout, schema self-check at first open.

- **`scripts/telemetry-summarize.py`** (full rewrite, 852 → ~150 lines): drops T2/SoHoAI/
  litellm/pricing.yaml cascade entirely. Now reads `.oc-session-id` sidecar, calls
  `oc_db.get_session_telemetry()`, writes `telemetry.json` per cross-repo contract shape.
  Drops global `telemetry.jsonl` append. Handles missing `.oc-session-id` gracefully
  (`cost_source: "none"` + stderr warning).

- **`scripts/telemetry-summarize.sh`** (minor): removed `.transcript-uuid` fallback.

- **`docs/Stage7.md`**: corrected empirical findings (Hypothesis B confirmed, `model` JSON
  format); added explicit path for `telemetry.json` + disambiguation note in §Cross-repo
  contract.

- **`docs/design.md`**: updated file inventory annotations: `telemetry.json` label corrected
  (removed stale "T2"); `telemetry.jsonl` noted as dropped in v7.1.

### Smoke tests: PASS T1–T8

T1 schema ok · T2 `_parse_model` JSON/None/plain · T3 `get_session` live row ·
T4 `is_session_over` old session · T5 `get_session_telemetry` structure ·
T6 unknown-id zero-struct · T7 summariser with `.oc-session-id` ·
T8 summariser without `.oc-session-id`

### Out of scope (v7.2)

Live callers (`orchestra-hook.sh`, `commands/*.md`) are not updated here.
The `.oc-session-id` sidecar is not yet written by any orchestra session command.
All live sessions produce `cost_source: "none"` until v7.2 ships. This is expected.

---

## 2026-05-28 — v7.0: Stage 7 redesign scaffold + design.md stale-ref purge

**Commit:** `de631cc`

### Delivered

- Created `docs/pre-Stage7--opencode-redesign.md`: architectural rationale for OC-native SQLite
  telemetry redesign; empirical findings; design choices; transient staging doc.
- Created `docs/Stage7.md`: 6-stage roadmap (v7.0–v7.5) with status markers and Stage 6
  sub-stage status mapping table.
- Created `docs/Stage7--Changelog.md`: this file; carries forward Stage 6 entries.
- Deleted `docs/Stage6.md` and `docs/Stage6--Changelog.md`.
- Cleaned `docs/design.md`: removed T1/T2 hybrid sections, SoHoAI proxy section, cost-source
  cascade section, native session tracking section (CC-era), CC statusLine JSON schema section
  (CC-era), SoHoAI live cost subsection, and all stale references. Added forward-pointer in
  telemetry slot. Refreshed frontmatter timestamps.

### Out of scope
Code changes deferred to v7.1–v7.3.

---

## 2026-05-28 — Stage 6.1.1: `claude-code-*` alias purge [status: PRESERVED, load-bearing for v7.X]

**Commit:** `67a1434`

### Delivered

**Load-bearing fix — agent frontmatter:** `agents/{planner,actor,actor-heavy,reviewer}.md` were declaring `model: claude-code-<X>` in their frontmatter. OpenCode's agent loader has no provider exposing that ID, so dispatch was silently falling back to the parent session's default model. In practice, the multi-tier worker design was running as **single-tier** (Planner, Actor, Reviewer all on whatever the parent used). All four agents now declare canonical OpenCode IDs from the `provider.sohoai` block in `~/.config/opencode/opencode.json`:

| Tier | Was | Now |
|---|---|---|
| Planner | `claude-code-glm-5.1` | `sohoai/glm-5.1` |
| Actor | `claude-code-qwen3-coder-next` | `sohoai/qwen3-coder-next` |
| Actor-Heavy | `claude-code-kimi-k2.6` | `sohoai/kimi-k2.6` |
| Reviewer | `claude-code-kimi-k2.6` | `sohoai/kimi-k2.6` |

**Cleanup — dead lookup keys / dead branches:**
- `config/pricing.yaml`: 6 key renames + `notes:` block rewritten (no more "gateway alias" framing — these are canonical OC IDs). `last_updated: 2026-05-28`.
- `config/context-windows.yaml`: 6 key renames; preamble comment updated to drop alias language.
- `scripts/telemetry-summarize.py`: 3 `startswith("claude-code-")` guards → `startswith("sohoai/")`; docstring at line 305 rewritten.
- `status-line/orchestra-block.sh`: case branches (lines 97, 99) and prefix-strip (line 127) switched to `sohoai/` discriminator. Prefix-strip logic now correctly uses `!=` test instead of empty-string check.

**Docs (live sections only):**
- `README.md`: model-tier table updated to `sohoai/*` IDs.
- `docs/design.md`: every live prose mention updated (intro, subagents section, /duo workflow advice, model-tier table, model-requirements `/duo` advisory row, non-Anthropic models section, cost section, "deployable surfaces" bullet, multi-model routing table, brain recommendation paragraph, SoHoAI routing-stability note, Reviewer rationale).
- `AGENTS.md`: agents/ inventory + ctx-segment smoke-test invocations.

### Files changed
`agents/planner.md`, `agents/actor.md`, `agents/actor-heavy.md`, `agents/reviewer.md`, `config/pricing.yaml`, `config/context-windows.yaml`, `scripts/telemetry-summarize.py`, `status-line/orchestra-block.sh`, `README.md`, `AGENTS.md`, `docs/design.md`, `docs/Stage6--Changelog.md`

---

## 2026-05-28 — Brain model recommendation (Anthropic Opus 4.7, advisory only) + commands/agents docs clarification [status: PRESERVED]

**Commit:** `a90b4dc`

### Delivered

**Brain model recommendation — Anthropic Opus 4.7 (advisory, never blocks):**
- `commands/brain.md`: replaced the prior `claude-code-kimi-k2.6` "recommended run environment" with an Anthropic Opus 4.7 recommendation. Implemented as a Prerequisite #1 **advisory check** — emits a one-line notice when Brain is not on Opus 4.7, then proceeds regardless. Any model is permitted; the operator's choice is final.
- **Deliberate deviation from `claude-orchestra`:** the upstream project hard-gates the equivalent check (STOPs on Haiku, older Sonnet, or non-Anthropic models). `oconona` downgrades to advisory only — the recommendation is preserved, but enforcement is removed. This is documented inline in `commands/brain.md`, `docs/design.md` §Model requirements, and `AGENTS.md`.
- Rationale captured inline: project name `--non-Anthropic` refers to the *worker tier* (Planner / Actor / Reviewer / Actor-Heavy) only. Brain itself benefits from Anthropic's strongest reasoning model because the orchestrator's job (multi-turn interrogation, plan reasoning, dispatch decisions, review judgment) rewards reasoning quality, and Brain is one session per pipeline (not per step), so the cost is bounded.

**Docs clarification — slash commands vs subagents:**
- `README.md`: added an explicit "Slash commands vs subagents" section with a comparison table; updated the model-tier table to reflect Brain = Anthropic Opus 4.7.
- `docs/design.md`: added a dedicated "Slash commands vs subagents" section near the top with full table (source dir, deploy dir, invocation mechanism, frontmatter expectation, purpose). Updated all Brain references (intro, tier table, model-requirements table, telemetry rationale, sample tier proportions, multi-model routing). Added a new "Why /brain is hard-gated to Anthropic" subsection under §Model requirements.
- `AGENTS.md`: added a "Brain model" section and a "Layout" preamble that explicitly distinguishes `commands/` (operator-facing slash commands) from `agents/` (dispatchable subagents).

### Files changed
`commands/brain.md`, `README.md`, `docs/design.md`, `AGENTS.md`, `docs/Stage6--Changelog.md`

---

## 2026-05-28 — Stage 6.1: Dual-stream writers + path audit fix [status: PARTIALLY SUPERSEDED]

**Commits:** `f39e96c` (code), `cbfc067` (docs)

**Superseded by:** v7.1–v7.3 (Writer A + Writer B + glob+sum cost path will be replaced by OC-SQLite reads).
**Preserved:** Path audit (`~/.config/opencode/orchestra/` migration), `.project-dir` sidecar, `deploy.sh` `agent/`→`agents/` fix.

### Delivered

**Path audit (all scripts, commands, docs):**
- Migrated all `${OPENCODE_PROJECT_DIR}/.opencode/orchestra/` references to `~/.config/opencode/orchestra/` (global NFS-shared path)
- Fixed `deploy.sh`: `agent/` → `agents/`, `command/` → `commands/` (canonical OpenCode dirs per opencode.ai/docs)
- Added native-sessions directory creation to `deploy.sh`
- Added `.project-dir` sidecar file written at session creation for project attribution across the global sessions directory

**Stage 6.1 writers:**
- **Writer A** (native residual tick): `scripts/orchestra-hook.sh` stop mode now writes `~/.config/opencode/orchestra/native-sessions/native-<uuid>.json` on every response turn while no orchestra session is in flight. Residual = OC session total minus sum of orchestra session costs. Atomic write (tmp + rename). Logs `native_tick` events and `native_cost_decrease` violations to invocations.log.
- **Writer B** (orchestra partial telemetry): `scripts/orchestra-hook.sh` end mode now triggers `telemetry-summarize.py --status in_flight` after each SubagentStop. Writes `telemetry.json` in the session dir with `"status": "in_flight"` — skips global `telemetry.jsonl` append and T1/T2 cross-check.

**Telemetry infrastructure:**
- `scripts/telemetry-summarize.sh`: added `${@:5}` passthrough so `--status in_flight` reaches the Python script
- `scripts/telemetry-summarize.py`: added `--status final|in_flight` arg; added `project_dir` field to `telemetry.json` and global log (read from `.project-dir` sidecar)
- `scripts/session-report.py`: reads `project_dir` from `telemetry.json` first (Stage 6.1+), falls back to path-based inference for legacy sessions

**Status-line cost display:**
- `status-line/orchestra-block.sh`: replaced SoHoAI + native-subagent-cost.sh live-cost with direct glob+sum over `native-sessions/*.json` and `sessions/*/telemetry.json`. Added 5% cost_divergence cross-check (logs to invocations.log, never suppresses display).

### Files changed
`deploy.sh`, `scripts/orchestra-hook.sh`, `scripts/telemetry-summarize.sh`, `scripts/telemetry-summarize.py`, `scripts/session-report.py`, `status-line/orchestra-block.sh`, `commands/brain.md`, `commands/brain-abandon.md`, `commands/duo-plan.md`, `commands/duo-abandon.md`, `commands/duo-act.md`, `agents-md-block/orchestra-guard.md`, `config/config.yaml`, `scripts/smoke-test.sh`, `.gitignore`, `docs/Stage6.md`, `docs/design.md`, `README.md`, `docs/Stage6--Changelog.md` (new)

---

*(Future Stage 7 sub-stage entries will be prepended here)*
