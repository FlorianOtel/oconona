# OpenCode Orchestra — project instructions

## Project workflows

```bash
./deploy.sh          # deploy to ~/.config/opencode/ (system-wide, all machines via NFS)
./collect.sh         # sync ~/.config/opencode/ changes back to repo before committing
```

## Brain model

**Brain** (the parent OpenCode session running `/brain` or `/duo-act`) is recommended to run on **Anthropic Opus 4.7**. The project name `--non-Anthropic` refers to the **worker tier** only (Planner / Actor / Reviewer / Actor-Heavy); Brain itself benefits from Anthropic's strongest reasoning model because the orchestrator's job (interrogation, planning, dispatch, review judgment) rewards strong reasoning. `/brain` emits an **advisory only** when Brain is not on Opus 4.7 — it does **not** enforce. Any model is permitted (deliberate deviation from `claude-orchestra`, which hard-gates this check).

## Layout

`commands/` and `agents/` are two distinct OpenCode artefacts — easy to conflate, important to keep separate:
- **`commands/*.md`** → operator-facing slash commands (deployed to `~/.config/opencode/commands/`). Invoked by the operator typing `/name`. The body becomes Brain's prompt.
- **`agents/*.md`** → dispatchable subagents (deployed to `~/.config/opencode/agents/`). Invoked by Brain via the `Task` tool with `subagent_type: name`. Each has frontmatter declaring its model and tool permissions.

- `agents/` — planner (claude-code-glm-5.1, read-only), actor (claude-code-qwen3-coder-next), actor-heavy (claude-code-kimi-k2.6), reviewer (claude-code-kimi-k2.6, read-only)
- `commands/` — /brain (full pipeline: Phase 0 inline + 3 subagents) + /brain-abandon (explicit cancel); /duo-plan, /duo-act, /duo-abandon (lightweight session-bracketed pipeline: Brain plans interactively across multiple turns, Actor acts after /duo-act)
- `scripts/orchestra-hook.sh` — PreToolUse / SubagentStop / PreCompact / Stop dispatcher
- `scripts/otel-headers-helper.sh` — X-Orchestra-Session-ID injection; auto-creates native session entries (OC 2.1.132: not called — fallback via bash-session-init.sh)
- `scripts/bash-session-init.sh` — sourced via `BASH_ENV`; registers native session as `native-<UUID>.lck` on first Bash call (UUID-keyed, cc_pid for liveness only)
- `scripts/native-session-finalize.py` — Stop-hook helper: finalise one native session; T2 fallback via `_walk_jsonl_for_tokens` + `pricing.yaml`
- `scripts/session-report.{sh,py}` — unified cost report (native + orchestra)
- `config/config.yaml` — global orchestra defaults
- `docs/design.md`    — full architecture reference

## Do not commit

- `.opencode/` — entirely runtime (orchestra state, local-deploy artifacts); gitignored

## Smoke test

- **Timestamp:** 2026-05-20T09:45:52Z
- **Model:** claude-code-kimi-k2.6 (Brain) + claude-code-glm-5.1 (Planner) + claude-code-qwen3-coder-next (Actor) + claude-code-kimi-k2.6 (Reviewer)
- **Reason:** status-line ctx + SoHoAI live-cost segments — implemented via /brain heavy-tier workflow, deployed, all smoke tests pass (ctx bar colors, 1M denominator, SoHoAI query, JSONL fallback).

## Telemetry Smoke Tests

Verify T1 (hook events) and T2 (transcript parse) after any /duo or /brain run.

### /duo smoke test
1. In plan mode, run: `/duo-plan add a comment line "# telemetry-smoke-test-<date>" to scripts/telemetry-report.sh`
2. (Optional) Refine across one or two turns to verify multi-turn refinement.
3. Run `/duo-act`, approve, and let Actor run.
4. After Phase 4 cleanup completes, run: `./scripts/smoke-test.sh`
5. Expected: T1 has ≥2 events (actor start + end), T2 cost > $0, subagents list contains "actor", `.outcome` mtime bounds the T2 window.

### /brain smoke test
1. In plan mode, run: `/brain add a comment line "# telemetry-smoke-test-<date>" to scripts/telemetry-report.sh`
2. Go through Phase 0 interrogation, approve plan, let pipeline run.
3. After cleanup, run: `./scripts/smoke-test.sh`
4. Expected: T1 has events for planner+actor+reviewer, T2 cost > $0, subagents list contains "planner", "actor", "reviewer". If parser_warnings mentions "T1 usage=null", that is expected (T1 is timing-only; T2 is authoritative).

### Status-line ctx + SoHoAI cost smoke test (no OC restart needed)
1. Deploy: `./deploy.sh`
2. Test ctx segment (low fill, expect green):
   `~/.config/opencode/scripts/ctx-segment.sh 12 24000 200000 claude-code-kimi-k2.6`
   → colored `ctx ▓░░░░░░░░░ 12% 24K/200K`
3. Test ctx segment (high fill, expect orange):
   `~/.config/opencode/scripts/ctx-segment.sh 85 170000 200000 claude-code-kimi-k2.6`
   → `ctx ▓▓▓▓▓▓▓▓░░ 85% 170K/200K` in orange
4. Test ctx 1M variant:
   `~/.config/opencode/scripts/ctx-segment.sh 12 120000 1000000 'claude-code-deepseek-v4-pro[1m]'`
   → `ctx ▓░░░░░░░░░ 12% 120K/1M`
5. Test SoHoAI helper (replace SESSION_ID with active orchestra dir
   basename or `native-<UUID>` from `~/.config/opencode/active-sessions/`):
   `~/.config/opencode/scripts/sohoai-live-cost.sh SESSION_ID $(date +%s) /tmp/test-cost-cache`
   → `~$X.YZ` or empty; <2s wall time
6. Live render: send any message to OC; observe status bar shows
   `model | ctx ▓▓░░░░░░░░ N% XK/YM | ~$X.YZ | ◆ project | ⎇ branch`
   (cost shown for paid models; absent for zero-cost claude-code-* models)

### Native session telemetry smoke test
1. Open a fresh OC session (no /brain or /duo).
2. Run a trivial Bash command (triggers BASH_ENV → `bash-session-init.sh` writes `native-<UUID>.lck`).
3. Close the session (Ctrl+C or exit).
4. In another OC session, send any message (triggers Stop hook → finds dead `.lck` → T2 finalization).
5. Check: `cat ~/.config/opencode/native-sessions/telemetry.jsonl | tail -1 | jq .`
   Expected: `session_id="native-<UUID>"`, `cost_usd_estimate > 0`, `cost_source: "pricing_yaml"`, `model` field present.
6. Run: `~/.config/opencode/scripts/session-report.sh --source native --last 5`
   Expected: new row with cost, model, duration.

**Telemetry flow (OC 2.1.132):**
- `otelHeadersHelper` is configured but NOT called by OC 2.1.132 — no session attribution to SoHoAI, `cost_source: "none"` without the fallback
- `bash-session-init.sh` (sourced via `BASH_ENV`) registers the session on first Bash call: writes `~/.config/opencode/active-sessions/native-<UUID>.lck` with `cc_pid` (stable OC main process), `session_uuid`, `started_at`
- `OC_SESSION_ID` is available in Bash subprocesses but NOT in hooks — registration happens in bash-session-init.sh, not the Stop hook
- Stop hook only finalizes dead sessions: iterates `native-*.lck`, checks `kill -0 <cc_pid>`, runs `native-session-finalize.py` when dead → T2 parses JSONL → `cost_source: "pricing_yaml"`
- Session IDs: `native-<UUID>` (stable, globally unique — no timestamp-PID suffix)
- **Requires**: `BASH_ENV=/home/florian/.config/opencode/scripts/bash-session-init.sh` in `settings.json` env (NOT managed by deploy.sh — must be set manually or kept in settings.json)

### Reading the unified session report
```bash
~/.config/opencode/scripts/session-report.sh --last 10
~/.config/opencode/scripts/session-report.sh --since 2026-05-01
~/.config/opencode/scripts/session-report.sh --source native
```
