---
title: "Stage 6 Changelog — oconona"
created_at: 2026-05-28--00-00
created_by: Claude Code (Claude Sonnet 4.6)
updated_by: Claude Code (Claude Opus 4.7)
updated_at: 2026-05-28--19-00
context: >
  Implementation log for Stage 6 dual-stream cost telemetry in oconona.
  Records delivered functionality in reverse-chronological order.
  Each entry includes timestamp, commit hash, and a summary of changes.
---

# Stage 6 Changelog

Entries are reverse-chronological. Newest at the top.

---

## 2026-05-28 — Brain model recommendation (Anthropic Opus 4.7, advisory only) + commands/agents docs clarification

**Commits:** *(pending)*

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

### Out of scope (kept as-is)
- Historical porting plans (`docs/Sonnet-porting-plan.md`, `docs/Opus-porting-plan.md`, `docs/Consolidated-migration-plan.md`) retain their original `claude-code-kimi-k2.6` Brain references as frozen migration records.
- Sample telemetry output blocks in `docs/design.md` (showing `brain claude-code-kimi-k2.6` in cumulative-totals tables) retain their original values as historical sample data.
- Smoke-test record in `AGENTS.md` line 29 retains its original `claude-code-kimi-k2.6 (Brain)` line as a historical record of a specific past smoke test; the next smoke run will overwrite it with the new Brain model.

---

## 2026-05-28 — Stage 6.1: Dual-stream writers + path audit fix

**Commits:** `cbfc067` (docs), `f39e96c` (code)

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

*(Future Stage 6 sub-stages will be prepended here)*
