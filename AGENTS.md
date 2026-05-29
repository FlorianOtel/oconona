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

- `agents/` — planner (sohoai/glm-5.1, read-only), actor (sohoai/qwen3-coder-next), actor-heavy (sohoai/kimi-k2.6), reviewer (sohoai/kimi-k2.6, read-only)
- `commands/` — /brain (full pipeline: Phase 0 inline + 3 subagents) + /brain-abandon (explicit cancel); /duo-plan, /duo-act, /duo-abandon (lightweight session-bracketed pipeline: Brain plans interactively across multiple turns, Actor acts after /duo-act)
- `scripts/orchestra-hook.sh` — PreToolUse / SubagentStop / PreCompact / Stop dispatcher
- `scripts/ctx-segment.sh` — status-line context-window bar renderer
- `scripts/oc-db.py` — read-only OC SQLite helper (new in v7.1)
- `scripts/session-report.{sh,py}` — unified cost report (orchestra sessions)
- `config/config.yaml` — global orchestra defaults
- `docs/design.md`    — full architecture reference

## Do not commit

- `.opencode/` — entirely runtime (orchestra state, local-deploy artifacts); gitignored

## Smoke tests (v7.3+)

After any /duo or /brain run:

```bash
./scripts/smoke-test.sh   # 3 OC-native checks: sidecar, DB row, telemetry.json
```

Check cost report:

```bash
~/.config/opencode/scripts/session-report.py --last 5
```

Check ctx segment (no OC restart needed):

```bash
~/.config/opencode/scripts/ctx-segment.sh 12 24000 200000 sohoai/kimi-k2.6
```
