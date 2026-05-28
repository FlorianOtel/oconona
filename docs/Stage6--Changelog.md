---
title: "Stage 6 Changelog — oconona"
created_at: 2026-05-28--00-00
created_by: Claude Code (Claude Sonnet 4.6)
context: >
  Implementation log for Stage 6 dual-stream cost telemetry in oconona.
  Records delivered functionality in reverse-chronological order.
  Each entry includes timestamp, commit hash, and a summary of changes.
---

# Stage 6 Changelog

Entries are reverse-chronological. Newest at the top.

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
