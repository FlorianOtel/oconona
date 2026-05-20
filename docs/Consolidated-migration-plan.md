---
title: "Consolidated Porting Plan: claude-orchestra--non-Anthropic → opencode-orchestra--non-Anthropic"
created_at: 2026-05-20--23-30
created_by: Claude Code (Claude Opus 4.7, 1M context)
updated_by: Claude Code (Claude Sonnet 4.6, 1M context)
updated_at: 2026-05-20--23-30
context: >
  Composite, operator-ready porting plan, consolidated from four independent plans
  authored 2026-05-20: Plan A (Sonnet 4.6 1M), Plan B (Kimi via OpenCode), Plan C
  (GLM-5.1 via SoHoAI), and Plan D / Opus 4.7. Each contributing plan is credited
  inline where its best ideas are adopted. Goal: bootstrap the empty OAN repo from
  CAN's tree, apply the Phase 0 CC→OC rename delta that CAN missed, preserve every
  non-Anthropic differentiator, and ship in a single verifiable commit.
---

## Implementation Summary

**Implemented**: 2026-05-20 | **Executor**: Claude Code (/duo pipeline: Sonnet 4.6 brain + Haiku 4.5 Actor) | **Status**: COMPLETE — all functional edits applied; single commit `64f163b` on `main`.

### §11 Open-question resolutions (decided before dispatch)

1. **AGENTS.md branch-policy section**: Deleted for initial commit — OAN has no `litellm-gateway` branch yet. Re-add when OAN forks the branch.
2. **docs/CC-to-OC-migration-plan.md**: Deleted — five porting plans already in `docs/` is enough; a sixth invites drift.
3. **docs/design-history.md**: Left as historical record (Plan A recommendation confirmed).
4. **Repo URL**: Used `https://github.com/FlorianOtel/opencode-orchestra--non-Anthropic`.

### What was done

- **Step 1 (rsync bootstrap)**: CAN tree rsync'd to OAN with all 6 exclusions. Existing OAN docs planning files (Sonnet/Kimi/Glm/Opus/Consolidated) preserved unchanged.
- **Steps 2–3 (deploy.sh, collect.sh)**: `CLAUDE` → `OC_HOME` (53 occurrences total); `$CLAUDE/agents/` → `$OC_HOME/agent/`, `$CLAUDE/commands/` → `$OC_HOME/command/` (singular deploy targets). `GLOBAL_CLAUDE_MD` → `GLOBAL_AGENTS_MD`; `~/.opencode/CLAUDE.md` → `~/.config/opencode/AGENTS.md`. Actor-heavy drift-check block (reading `$REPO/agents/`) preserved verbatim.
- **Steps 4–8 (shell scripts)**: `bash-session-init.sh` updated for `opencode` process detection (variable names `cc_pid` preserved). `orchestra-hook.sh` `CLAUDE_SESSION_ID` fallback removed. `telemetry-summarize.sh` same. `ctx-segment.sh` `~/.opencode/` → `~/.config/opencode/`. `native-subagent-cost.sh` comment fix.
- **Step 9 (status-line/orchestra-block.sh)**: Six `$HOME/.opencode/` path fixes + all CC-native/CC-model/CC-context comment substitutions.
- **Steps 10–13 (Python scripts)**: All `Path.home() / ".claude" / ...` → `Path.home() / ".config" / "opencode" / ...` in session-report.py, native-session-report.py, native-session-finalize.py. Critical `.claude`→`.opencode` index-detection block in session-report.py. telemetry-summarize.py: only 2 path changes; `query_litellm_cost()` and alias detection preserved verbatim.
- **Step 14 (config/context-windows.yaml)**: Two `CC's own` → `OC's own` comment fixes.
- **Steps 15–19 (commands)**: `CLAUDE_SESSION_ID` fallback removed from brain.md, duo-act.md, duo-abandon.md, brain-abandon.md. CC→OC process comments in brain.md, duo-plan.md. `OPENCODE_ORCHESTRA_SESSION_DIR` preserved in all command files.
- **Step 20 (agents/planner.md)**: Two `CLAUDE.md` → `AGENTS.md` in doc-impact rule body. Model + tier annotations + `OPENCODE_ORCHESTRA_SESSION_DIR` preserved verbatim.
- **Step 21 (agents-md-block/orchestra-guard.md)**: `/home/florian/.opencode/plans/` → `/home/florian/.config/opencode/plans/`.
- **Step 22 (AGENTS.md)**: 9 CC→OC substitutions. `litellm-gateway` branch-policy section deleted.
- **Step 23 (README.md)**: OpenCode links fixed. Model-tier table with non-Anthropic model assignments inserted. Repo URL and `cd` references updated. ASCII tree root updated.
- **Step 24 (utils/snapshot_codebase.py)**: `PROJECT_ROOT` fixed to point at OAN (was pointing at OP — latent bug). `CLAUDE.md` → `AGENTS.md`. `actor-heavy.md` added to file list.
- **Steps 25–26 (docs/design.md, docs/resources.md)**: Applied by Brain post-Actor (Actor skipped these as "non-blocking"). All plan-specified edits applied: agent table singular paths, CC-native→OC-native, CC→OC context_window references, CLAUDE.md→AGENTS.md guard references, `.opencode/agents/`→`.opencode/agent/` singular forms, OC_SESSION_ID fix at line 522, and several additional functional references (bash-session-init.sh BASH_ENV path, process name in design narrative, OC statusLine reference).
- **Step 27 (docs/architecture-decisions.md)**: Created from OP verbatim with non-Anthropic-specific metadata. Decision 3 note emphasizes SoHoAI routing is more load-bearing here.
- **Step 28 (delete files)**: `docs/TODO.md` and `docs/CC-to-OC-migration-plan.md` deleted.
- **Step 29 (.gitignore)**: `.claude/` added.

### Verification results (§9)

- **§9.1 Syntax**: PASS — `bash -n` and `python3 -m py_compile` on all scripts clean.
- **§9.2 Negative-grep**: PASS — zero matches for `$CLAUDE`, `CLAUDE_SESSION_ID`, `CLAUDE_ORCHESTRA_SESSION_DIR`, `~/.claude/`, `~/.opencode/`, `GLOBAL_CLAUDE_MD` in `*.sh`, `*.py`, `*.yaml`, `*.json`.
- **§9.3 Positive-grep**: PASS — `OC_HOME` confirmed in deploy.sh + collect.sh; `GLOBAL_AGENTS_MD` confirmed; `OPENCODE_ORCHESTRA_SESSION_DIR` confirmed; `"opencode"` process detection confirmed; non-Anthropic models confirmed in agents/*.md and pricing.yaml; `agents/actor-heavy` confirmed in brain.md + collect.sh.
- **§9.4 deploy --dry-run**: Not run (requires live OpenCode install).
- **§9.5 Live smoke test**: Not run (requires live OpenCode install).
- **§9.6 Model assignments**: PASS — `claude-code-qwen3-coder-next` (actor), `claude-code-kimi-k2.6` (actor-heavy, reviewer), `claude-code-glm-5.1` (planner).

### Discrepancies and notes

- Line numbers in §5 are approximate (plan referenced CAN as-of 2026-05-20). All edits applied by content match, not by line number — no misses detected.
- `scripts/__pycache__/telemetry-summarize.cpython-312.pyc` was committed to OAN (not excluded by rsync since it wasn't under `scripts/__pycache__/` — it was at that path). This is a .pyc bytecode file; consider adding `**/__pycache__/` to .gitignore.
- docs/design.md §See CC statusLine JSON schema section cross-reference at line ~367 was also updated to "OC statusLine" during Brain's post-Actor pass.

---

# Consolidated Porting Plan

## 0. Where this plan came from

Four independent porting plans were authored on 2026-05-20:

| ID | File | Author | Strongest contribution |
|---|---|---|---|
| **Plan A** | [`docs/Sonnet-porting-plan.md`](Sonnet-porting-plan.md) | Claude Sonnet 4.6 1M | Most complete file-by-file line-numbered edit list; correct three-project framing; best `Preserve from CAN` table; deploy smoke test in §9.4. |
| **Plan B** | [`docs/Kimi-oc-non-A-porting.plan.md`](Kimi-oc-non-A-porting.plan.md) | OpenCode (Kimi K2.6) | Only plan to flag the stale `scripts/orchestra-hook.sh.orig` backup, `scripts/__pycache__/`, and `scripts/telemetry-summarize.sh`'s `CLAUDE_SESSION_ID` fallback. Concise Phase 8 verification block. |
| **Plan C** | [`docs/Glm--oc-non-A-porting.plan.md`](Glm--oc-non-A-porting.plan.md) | GLM-5.1 via SoHoAI | Best `Preserve-from-CAN` granularity (Phase 3a-3h) and the only plan to make `Files to NOT port from OP` (Phase 4) an explicit list. Surfaces the litellm-gateway branch-policy decision. |
| **Plan D / Opus 4.7** | [`docs/Opus-porting-plan.md`](Opus-porting-plan.md) | Claude Opus 4.7 1M | Catches what Plans A/B missed — `scripts/ctx-segment.sh:41`, `agents/planner.md:50` CLAUDE.md inside the rule body, `utils/snapshot_codebase.py:29` wrong `PROJECT_ROOT`, README line 3 second broken link, repo-name references, branch-policy decision. Negative-grep verification. |

This consolidated plan adopts Plan A as the backbone, folds in Plan B's stale-artefact cleanup and telemetry-summarize.sh edit, folds in Plan C's Preserve/Do-Not-Port tables, and folds in Plan D's missed-edits sweep and negative-grep verification. Each section credits its source.

> **Provenance note**: Plan C contains several factual claims about CAN's contents that are wrong (CAN still has `claude-md-block/`, CAN has `CLAUDE.md` file, CAN has `agents/planner-long.md`). These claims are not adopted here; verified with `ls` and `git ls-files` against `~/Gin-AI/projects/claude-orchestra--non-Anthropic`. Plan B targets in-place edits to CAN, not the new OAN repo; the framing is corrected here.

## 1. Three projects, named

| Short | Path | Role |
|---|---|---|
| **CAN** | `~/Gin-AI/projects/claude-orchestra--non-Anthropic` | Source baseline. Has non-Anthropic models, actor-heavy tier, SoHoAI pricing, tier annotations. Phase 0 CC→OC rename is **partial**. CAN is a `git worktree` of OP — use `rsync`, not `git clone`. |
| **OP** | `~/Gin-AI/projects/opencode-orchestra` | Reference. Phase 0 CC→OC rename **complete**. Ships Anthropic models, no actor-heavy, no SoHoAI pricing. |
| **OAN** | `~/Gin-AI/projects/opencode-orchestra--non-Anthropic` | **Target**. Empty except for README. This is the repo we build. |

(Source: all four plans agree on the framing. Plan B's "edit CAN in place" wording is the outlier and is rejected here.)

## 2. Foundational rules (Plans A + C, consolidated)

These five model/feature invariants are non-negotiable. They are the entire reason OAN exists as distinct from OP.

1. **Never edit model assignments.** Non-Anthropic models stay (`claude-code-glm-5.1` for Planner, `claude-code-qwen3-coder-next` for Actor, `claude-code-kimi-k2.6` for actor-heavy and Reviewer).
2. **Never edit `pricing.yaml`'s SoHoAI flat-rate entries** ($0.00 marginal cost by design).
3. **Never edit `[tier: fast/default/heavy]` annotations** in `agents/planner.md`.
4. **Never edit actor-heavy dispatch logic** in `commands/brain.md` (the `subagent_type: actor-heavy` for `[tier: heavy]` steps).
5. **Preserve `OPENCODE_ORCHESTRA_SESSION_DIR`** verbatim. CAN is correct; OP is stale (`CLAUDE_ORCHESTRA_SESSION_DIR`). Do **not** import OP's name. A naive `sed -e 's/CLAUDE_ORCHESTRA/.../g'` style sweep is dangerous because CAN already has `OPENCODE_ORCHESTRA_SESSION_DIR`; the sweep would silently downgrade it.

(Plan B's "Foundational Rule" table covers rules 1-2. Plan C's Phase 3 covers rules 3-4. Plan A's §3 covers rule 5. All five live here.)

## 3. Strategy (Plan A, with Plan B + D enhancements)

`rsync` CAN's tracked tree into OAN with stale-artefact exclusions. Apply the Phase 0 rename delta CAN missed using **surgical line-numbered edits, not sed sweeps**. Add `docs/architecture-decisions.md` (the only OP-only file). Delete `docs/TODO.md` (OP's Phase 0 outcome). Fix the latent bugs uncovered during the four-plan review. Commit once.

## 4. Step 0 — Bootstrap (Plans A + B + D, merged)

```bash
# From OAN repo root.
rsync -av \
  --exclude='.git'                                  \
  --exclude='.claude/'                              \
  --exclude='.opencode/'                            \
  --exclude='scripts/__pycache__/'                  \
  --exclude='scripts/orchestra-hook.sh.orig'        \
  --exclude='utils/codebase_snapshot.md'            \
  ~/Gin-AI/projects/claude-orchestra--non-Anthropic/ .

# Preserve the four planning docs already living in docs/
ls docs/   # Verify Sonnet/Kimi/Glm/Opus/Consolidated plans all present.
```

The exclusions (Plan B's contribution for `.orig` and `__pycache__`; Plan D for `codebase_snapshot.md`) keep three known-stale items from ever entering OAN's history.

## 5. File-by-file edits

Line numbers reference CAN as of 2026-05-20. Citations indicate which prior plan(s) flagged the change first.

### 5.1 `deploy.sh` (Plans A, B, C — fully detailed by A)

| Line | Change | Source |
|---|---|---|
| 14 | `CLAUDE="${HOME}/.config/opencode"` → `OC_HOME="${HOME}/.config/opencode"` | A, B, C |
| 57 | `echo "  target: $CLAUDE"` → `echo "  target: $OC_HOME"` | A |
| 63 | `[ -d "$CLAUDE" ]` → `[ -d "$OC_HOME" ]` | A |
| 66 | `for dir in agents commands scripts orchestra` → `for dir in agent command scripts orchestra` | A, D |
| 67, 69 | `"$CLAUDE/..."` → `"$OC_HOME/..."` | A |
| 74 | `"$CLAUDE/agents/..."` → `"$OC_HOME/agent/..."` | A, C |
| 92 | `"$CLAUDE/commands/..."` → `"$OC_HOME/command/..."` | A, C |
| 113-129, 133, 134, 137, 138 | All remaining `$CLAUDE/scripts/` and `$CLAUDE/orchestra/` → `$OC_HOME/...`. Agent/command paths singular. | A |
| 154, 156, 160, 162 (orphan cleanup) | `$CLAUDE/scripts/$orphan`, `$CLAUDE/agents/...` → `$OC_HOME/scripts/...`, `$OC_HOME/agent/...` | A |
| 173, 174 (orphan commands cleanup) | `$CLAUDE/commands/` → `$OC_HOME/command/` | A |
| 181, 182 (researcher orphan) | `$CLAUDE/agents/researcher.md` → `$OC_HOME/agent/researcher.md` | A |
| 188-190 | `$CLAUDE/orchestra/<file>` → `$OC_HOME/orchestra/<file>` | A |
| 194 | `SETTINGS="$CLAUDE/settings.json"` → `SETTINGS="$OC_HOME/settings.json"` | A |
| 236 | `STATUS_LINE="$CLAUDE/scripts/status-line.sh"` → `STATUS_LINE="$OC_HOME/scripts/status-line.sh"` | A |
| 294 | Comment: `Inject orchestra-guard block into ~/.config/opencode/CLAUDE.md` → `... AGENTS.md` | A, B |
| 295-300 | Body comments: `CLAUDE.md` → `AGENTS.md` throughout § 9 explanation | A |
| 301 | `echo "CLAUDE.md guard:"` → `echo "AGENTS.md guard:"` | A, B |
| 302 | `GLOBAL_CLAUDE_MD="$HOME/.opencode/CLAUDE.md"` → `GLOBAL_AGENTS_MD="$OC_HOME/AGENTS.md"` | A, B |
| 304-346 | All `GLOBAL_CLAUDE_MD` → `GLOBAL_AGENTS_MD`; `~/.opencode/CLAUDE.md` → `~/.config/opencode/AGENTS.md`; messages and warns | A, B |

Keep the actor-heavy drift-check block (lines 79-87) reading from `$REPO/agents/...` — that path is the **repo** (plural, CAN's convention), not the deploy target.

### 5.2 `collect.sh` (Plans A, B, C)

| Line | Change |
|---|---|
| 14 | `CLAUDE=...` → `OC_HOME=...` |
| 48 | `echo "  source: $CLAUDE"` → `echo "  source: $OC_HOME"` |
| 54-57 | `$CLAUDE/agents/...` → `$OC_HOME/agent/...`. Keep the `actor-heavy.md` line (Plan B explicitly preserves; missed in OP's collect.sh). |
| 60-64 | `$CLAUDE/commands/...` → `$OC_HOME/command/...` |
| 67-69 | `$CLAUDE/scripts/...` → `$OC_HOME/scripts/...` |
| 72-73 | `$CLAUDE/orchestra/...` → `$OC_HOME/orchestra/...` |

### 5.3 `scripts/bash-session-init.sh` (Plans A, B)

| Line | Change |
|---|---|
| 2 | `... every CC Bash tool call.` → `... every OC Bash tool call.` |
| 4 | `cc_pid (stable CC main process) ...` → `cc_pid (stable OC main process) ...` (keep the variable name `cc_pid`; it is referenced by `orchestra-hook.sh`) |
| 18-22 | Comment block: `CC main PID` / `claude process` → `OC main PID` / `opencode process` |
| 23 | `if [ "$_ppid_comm" != "claude" ]; then` → `if [ "$_ppid_comm" != "opencode" ]; then` |
| 26 | `[ "$_parent_comm" = "claude" ] && _cc_main_pid=$_parent` → `... = "opencode" ...` |

### 5.4 `scripts/orchestra-hook.sh` (Plans A, B)

| Line | Change |
|---|---|
| 25 | Comment: `... never block Claude` → `... never block OpenCode` |
| 32 | `STAMP_SESSION="${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-unknown}}"` → `STAMP_SESSION="${OC_SESSION_ID:-unknown}"` |
| ~215 | Add `# TODO(Phase 3): drop PreCompact — replaced by session.compacted plugin event in OC` after the PreCompact handler (matches OP) |
| 269 | Comment: `... never blocks Claude.` → `... never blocks OpenCode.` |
| 318 | Comment: `multi-Claude-Code-session concurrency` → `multi-OpenCode-session concurrency` |
| 328 | Comment: `whose CC process has ended` → `whose OC process has ended` |

### 5.5 `scripts/telemetry-summarize.sh` (Plan B — solo)

| Line | Change |
|---|---|
| 31 | Comment: `Pass through CLAUDE_SESSION_ID ...` → `Pass through OC_SESSION_ID ...` |
| 32 | `TRANSCRIPT_ID="${4:-${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-}}}"` → `TRANSCRIPT_ID="${4:-${OC_SESSION_ID:-}}"` |

(This file was missed by Plans A and C.)

### 5.6 `scripts/ctx-segment.sh` (Plan D — solo)

| Line | Change |
|---|---|
| 41 | `yaml_file="$HOME/.opencode/orchestra/context-windows.yaml"` → `yaml_file="$HOME/.config/opencode/orchestra/context-windows.yaml"` |

(Read at every status refresh; silent breakage if not fixed — status-line falls back to default context-window denominator. Plan C listed the file but never specified the edit; Plans A and B missed it entirely.)

### 5.7 `status-line/orchestra-block.sh` (Plan A — fully detailed)

Six `$HOME/.opencode/...` paths → `$HOME/.config/opencode/...` at lines 18, 104, 148, 235, 255, 274. Plus comment cleanups (`CC-native` → `OC-native`, `CC reports 0% usage` → `OC reports 0% usage`, `CC gives no token counts` → `OC gives no token counts`, `override CC when` → `override OC when`, `CC model_id` → `OC model_id`, `CC's context_window_size` → `OC's context_window_size`, `CC provides cost.total_cost_usd` → `OC provides cost.total_cost_usd`, `Strip CC-native fields` → `Strip OC-native fields`).

### 5.8 `scripts/session-report.py` (Plan A)

All `Path.home() / ".claude" / ...` → `Path.home() / ".config" / "opencode" / ...`. Specifically:
- `.claude/projects` (3 occurrences)
- `.claude/native-sessions/telemetry.jsonl`
- `.claude/orchestra/telemetry.jsonl`
- `.claude/active-sessions`
- `.claude/usage-data/session-meta`

**Critical** index-detection block:
```python
if ".claude" in parts:
    idx = parts.index(".claude")
```
→
```python
if ".opencode" in parts:
    idx = parts.index(".opencode")
```

Plus the `(legacy CC architecture)` → `(legacy OC architecture)` comment near the same block.

### 5.9 `scripts/native-session-report.py` (Plan A)

All `Path.home() / ".claude" / ...` → `Path.home() / ".config" / "opencode" / ...` at lines ~62, ~80, ~174, ~220, ~299, ~337, ~406.

### 5.10 `scripts/native-session-finalize.py` (Plan A)

| Line | Change |
|---|---|
| 63 | Help text: `CC session UUID` → `OC session UUID` |
| 148 | `.claude/orchestra/telemetry.jsonl` → `.config/opencode/orchestra/telemetry.jsonl` |
| 186 | `.claude/active-sessions/...` → `.config/opencode/active-sessions/...` |
| 196 | `.claude/native-sessions` → `.config/opencode/native-sessions` |

### 5.11 `scripts/native-subagent-cost.sh` (Plan A)

Line 6 comment: `... a native CC session.` → `... a native OC session.`

### 5.12 `scripts/telemetry-summarize.py` (Plan A)

Two `Path.home() / ".claude" / ...` paths (lines 54, 100). Replace with `.config/opencode/...`. **Do not touch** `query_litellm_cost()`'s `pricing_data` parameter, `claude-code-*` alias detection, or pricing.yaml cache-rate override logic — these are the SoHoAI-pipeline enhancements (Plan C §3e correctly identifies these as preserve-verbatim).

### 5.13 `config/context-windows.yaml` (Plan A)

Two comment-only fixes:
- `# model_id isn't here: CC's own context_window.context_window_size.` → `OC's own ...`
- `# Fallback: CC's own context_window.context_window_size if model_id absent.` → `OC's own ...`

(All non-Anthropic and local-Ollama model entries preserved verbatim — Plan C §3f.)

### 5.14 `commands/brain.md` (Plans A + D)

| Line | Change | Source |
|---|---|---|
| 19 | `/home/florian/.opencode/plans/<name>.md` → `/home/florian/.config/opencode/plans/<name>.md` | A |
| 110 | Comment: `... CC process PID ...` → `... OC process PID ...` | A |
| 117 | Comment: `... whose CC process is no longer running.` → `... whose OC process is no longer running.` | A |
| 399 | Bash heredoc: `... echo \"${CLAUDE_SESSION_ID:-}\")` → `... echo \"${OC_SESSION_ID:-}\")` | A, D |

**Preserved verbatim** (Plan C §3d):
- `export OPENCODE_ORCHESTRA_SESSION_DIR="${SESSION_DIR}"` (line 88)
- Non-Anthropic prerequisite/model check block
- Tier-aware dispatch instructions (`subagent_type: actor-heavy` for `[tier: heavy]` steps)
- `~/.config/opencode/plans/` references on lines 21, 23, 36, 236 (already correct)

Optionally add `# TODO(Phase 2): replace with /brain-plan + /brain-act split` near the `ExitPlanMode` call to mirror OP's Phase 0 annotations (informational; no behaviour change).

### 5.15 `commands/duo-plan.md` (Plan A)

| Line | Change |
|---|---|
| 114 | Comment: `... CC process PID ...` → `... OC process PID ...` |
| 121 | Comment: `... whose CC process is no longer running.` → `... whose OC process is no longer running.` |

`OPENCODE_ORCHESTRA_SESSION_DIR` on line 131 — preserve verbatim (already correct).

### 5.16 `commands/duo-act.md` (Plan A)

Line 101: `echo \"${CLAUDE_SESSION_ID:-}\")` → `echo \"${OC_SESSION_ID:-}\")`. Do **not** import OP's `TODO(Phase 2): replace with /brain-plan + /brain-act split` annotation — that's specific to the Anthropic-model pipeline design and not part of this port (Plan A explicitly notes this).

### 5.17 `commands/duo-abandon.md` (Plan A)

Line 59: `echo \"${CLAUDE_SESSION_ID:-}\")` → `echo \"${OC_SESSION_ID:-}\")`.

### 5.18 `commands/brain-abandon.md` (Plan A)

Line 59: `echo \"${CLAUDE_SESSION_ID:-}\")` → `echo \"${OC_SESSION_ID:-}\")`.

### 5.19 `agents/planner.md` (Plan D — solo)

Line 50 inside step 5 (doc-impact rule):

```
Scan for: root-level `*.md` files (`CLAUDE.md`, `README*.md`, ...
... any file referenced from CLAUDE.md's project-file inventory.
```

Both `CLAUDE.md` → `AGENTS.md`. (Missed by Plans A, B, C — operator-instruction text inside the planner's body still tells Actor to scan a file that no longer exists in OAN.)

Preserve: `model: claude-code-glm-5.1`, all tier annotations (`[tier: fast/default/heavy]`), `OPENCODE_ORCHESTRA_SESSION_DIR` references. (Plan C §3c.)

### 5.20 `agents/actor.md`, `agents/actor-heavy.md`, `agents/reviewer.md`

No changes. CAN already has correct models, `OPENCODE_ORCHESTRA_SESSION_DIR`, and the dynamic "executor model from the session system context" identity language. (Plan C §3a + §3g; Plan A §8.)

### 5.21 `agents-md-block/orchestra-guard.md` (Plan A)

Line 15: `/home/florian/.opencode/plans/<name>.md` → `/home/florian/.config/opencode/plans/<name>.md`.

CAN's version is already richer than OP's (uses `.opencode/orchestra/sessions/` correctly; has actor-heavy / planner-long dispatch language). This is the **only** edit needed in this file.

### 5.22 `AGENTS.md` (Plans A + D)

| Line | Change | Source |
|---|---|---|
| 31 | `(CC 2.1.132: not called ...)` → `(OC 2.1.132: not called ...)` | A |
| 65 | `... (no CC restart needed)` → `... (no OC restart needed)` | A |
| 80 | `send any message to CC;` → `send any message to OC;` | A |
| 85 | `Open a fresh CC session` → `Open a fresh OC session` | A |
| 88 | `In another CC session` → `In another OC session` | A |
| 94 | `**Telemetry flow (CC 2.1.132):**` → `**Telemetry flow (OC 2.1.132):**` | A |
| 95 | `not called by CC 2.1.132` → `not called by OC 2.1.132` | A |
| 96 | `stable CC main process` → `stable OC main process` | A |
| 100 | `BASH_ENV=/home/florian/.opencode/scripts/bash-session-init.sh` → `BASH_ENV=/home/florian/.config/opencode/scripts/bash-session-init.sh` | A |

**Branch-policy section (lines 10-24).** CAN's `litellm-gateway` branch policy refers to a branch that doesn't yet exist in OAN. Plan C surfaces this; Plan D resolves it. **Decision**: delete the section in the initial OAN commit; re-add (or rewrite for OAN-specific equivalent) once OAN forks a `litellm-gateway` branch. **Open question for operator** — see §11.

### 5.23 `README.md` (Plans A + D, A's model-tier table + D's link/repo-name fixes)

| Line | Change | Source |
|---|---|---|
| 3 | `[OpenCode](https://claude.ai/code)` → `[OpenCode](https://opencode.ai)` | D — second broken link missed by Plan A |
| 7-12 | Add model-name column with non-Anthropic values (see table below) | A |
| 46 | `[OpenCode](https://docs.anthropic.com/en/docs/claude-code)` → `[OpenCode](https://opencode.ai)` | A |
| 54 | `git clone https://github.com/FlorianOtel/opencode-orchestra` → `... /opencode-orchestra--non-Anthropic` | D — confirm repo URL with operator |
| 55 | `cd opencode-orchestra` → `cd opencode-orchestra--non-Anthropic` | D |
| 137 | `cd opencode-orchestra` → `cd opencode-orchestra--non-Anthropic` | D |
| 162 (ASCII tree root) | `opencode-orchestra/` → `opencode-orchestra--non-Anthropic/` | D |

Model-tier table (Plan A §5.18.1):

```markdown
| Tier | Model | Fallback | Role |
|---|---|---|---|
| **Brain** | Your main session (`claude-code-kimi-k2.6` recommended) | — (main session) | Orchestrates, delegates, approves |
| **Planner** | `claude-code-glm-5.1` | — | Decomposes tasks into numbered, reviewable plans |
| **Actor** | `claude-code-qwen3-coder-next` | `claude-code-kimi-k2.6` for `[tier: heavy]` steps | Executes individual plan steps; scoped, fast, cheap |
| **Reviewer** | `claude-code-kimi-k2.6` | — | Reviews Actor's output; emits PASS / FIX / BLOCK verdicts |
```

### 5.24 `utils/snapshot_codebase.py` (Plan D — solo)

| Line | Change |
|---|---|
| 29 | `PROJECT_ROOT = Path("/mnt/nfs/Florian/Gin-AI/projects/opencode-orchestra")` → `... /opencode-orchestra--non-Anthropic")` |
| 35 | `"CLAUDE.md",` → `"AGENTS.md",` |
| ~40 (file list) | Insert `"agents/actor-heavy.md",` after `"agents/actor.md",` |
| 47 | Comment: `# Claude.md injection block` → `# AGENTS.md injection block` |

CAN's `PROJECT_ROOT` literal points at OP's path — latent bug in CAN, becomes a real bug in OAN (snapshot would render from OP's tree). Missed by Plans A, B, C.

### 5.25 `docs/design.md` (Plan A + D)

| Anchor | Change | Source |
|---|---|---|
| Line 45 paragraph | `~/.config/opencode/CLAUDE.md` (2x) → `~/.config/opencode/AGENTS.md`; `CLAUDE.md guard is the load-bearing component` → `AGENTS.md guard ...` | A |
| Lines 58-61 (Agent table) | `~/.config/opencode/agents/<file>.md` → `~/.config/opencode/agent/<file>.md` (singular) for all 4 rows | A |
| Line 112 | `It replaces the CC-native progress bar` → `It replaces the OC-native progress bar` | A |
| Line 131 | `Without this fix CC's context_window_size` → `Without this fix OC's context_window_size` | A |
| Line 243 | `CLAUDE.md  (sentinel-bracketed orchestra-guard block ...)` → `AGENTS.md  ...` | D |
| Line 280 | `rm -rf ~/.config/opencode/agents/{planner,actor,reviewer}.md ~/.config/opencode/commands/{brain,duo}.md` → `... agent/{planner,actor,actor-heavy,reviewer}.md ... command/{brain,duo}.md` | D |
| Line 296 | `Subagent definitions (.opencode/agents/*.md ...)` → `... .opencode/agent/*.md ...` | D |
| Line 522 | `CLAUDE_SESSION_ID is not set in subprocess environments` → `OC_SESSION_ID is not set in subprocess environments` | D |

### 5.26 `docs/design-history.md`

15 occurrences of `Claude Code` / `~/.claude/` / `CLAUDE.md` remain. Plan A's stance — **leave them as historical record** — is adopted. These are timestamped historical narrative; rewriting them rewrites history. **Open question for operator** — see §11.

### 5.27 `docs/resources.md`

CAN has 2 `Claude Code`/`CLAUDE.md` references vs OP's 1. Re-grep after copy and decide per-occurrence.

### 5.28 `docs/architecture/2026-04-28-headless-revert.md`

Metadata-only delta (model field). Keep CAN's version.

### 5.29 `docs/CC-to-OC-migration-plan.md` (Plan D)

CAN has a 120-line Kimi-authored doc here. OP has a 499-line claude.ai chat export. With five live porting plans already in `docs/` (this Consolidated plan + Sonnet + Kimi + Glm + Opus), keeping a sixth invites drift. **Recommendation**: delete CAN's version. **Open question for operator** — see §11.

### 5.30 `docs/TODO.md` (Plans A + C)

Delete. OP's Phase 0 deleted it (its content is superseded by `docs/architecture-decisions.md`). Plan B keeps it — that diverges from Phase 0 without rationale and is rejected here.

### 5.31 `.gitignore` (Plan A)

Add `.claude/` next to the existing `.opencode/` entry — matches OP's Phase 0 addition.

## 6. Files to create

### 6.1 `docs/architecture-decisions.md` (Plans A + C agree)

Copy OP's verbatim, then update metadata only:

```yaml
---
title: "OpenCode Orchestra (non-Anthropic) — Phase 0 Architecture Decisions"
created_at: 2026-05-20--23-30
created_by: Claude Code (Claude Opus 4.7, 1M context) — adapted from opencode-orchestra Phase 0
context: >
  Four architectural decisions inherited from the opencode-orchestra Phase 0 migration,
  applied to the non-Anthropic variant. All four decisions (plan-approval gate,
  pre-compact state, SoHoAI routing, status-line cost display) are unchanged in substance.
  Decision 3 (SoHoAI routing: option C — all traffic through SoHoAI) is more load-bearing
  here because the entire non-Anthropic pipeline depends on SoHoAI's LiteLLM router for
  model aliasing.
---
```

Decision bodies are identical.

## 7. Files to delete (post-rsync)

If the §4 rsync exclusions were followed, none of these will be present. If you skipped them, delete:

- `scripts/orchestra-hook.sh.orig` (Plan B)
- `scripts/__pycache__/` (Plan B)
- `docs/TODO.md` (Plans A, C)
- `utils/codebase_snapshot.md` (Plan D)
- *(decision pending)* `docs/CC-to-OC-migration-plan.md` (Plan D — see §11)

## 8. Files preserved verbatim from CAN (Plan A §8 + Plan C Phase 4, consolidated)

| File | Reason | Source |
|---|---|---|
| `agents/actor.md` | Correct model + dynamic identity text + `OPENCODE_ORCHESTRA_SESSION_DIR` | A, C |
| `agents/actor-heavy.md` | CAN-only; preserve entirely | A, B, C |
| `agents/reviewer.md` | Correct model + correct env var | A, C |
| `agents/planner.md` | Preserve tier schema and model; only line-50 `CLAUDE.md`→`AGENTS.md` edits (see §5.19) | A, C, D |
| `config/config.yaml` | Identical CAN vs OP | A, B |
| `config/settings-hooks.json` | Identical | A, B |
| `config/pricing.yaml` | Non-Anthropic flat-rate entries are the differentiator | A, B, C |
| `config/context-windows.yaml` | Only comment text edits per §5.13; non-Anthropic + Ollama entries preserved | A, C |
| `scripts/sohoai-live-cost.sh` | Already correct | A, B |
| `scripts/native-session-report.sh` | Wrapper; no path issues | A, B |
| `scripts/session-report.sh` | Wrapper; no path issues | A, B |
| `scripts/telemetry-report.sh` | Already uses `~/.config/opencode/` | A, B |
| `scripts/smoke-test.sh` | Already uses `OPENCODE_PROJECT_DIR` | A, B |
| `scripts/otel-headers-helper.sh` | Already correct (`OC_SESSION_ID`) | A, B |
| `scripts/telemetry-summarize.py` (the `query_litellm_cost()` enhancements) | SoHoAI gateway alias detection + pricing.yaml cache-rate override | C §3e, D |
| `LICENSE` | No changes | A, B, C |

## 9. Verification (Plans A + B + D, merged)

### 9.1 Syntactic (Plan B)

```bash
bash -n deploy.sh collect.sh scripts/*.sh status-line/*.sh
python3 -m py_compile scripts/*.py utils/*.py
```

### 9.2 Negative-grep — must return zero matches (Plan D, with B's pattern as base)

```bash
grep -rn \
  --include='*.sh' --include='*.py' --include='*.yaml' --include='*.json' \
  -e '\$CLAUDE\b'                                  \
  -e 'CLAUDE_SESSION_ID'                           \
  -e 'CLAUDE_CODE_SESSION_ID'                      \
  -e 'CLAUDE_ORCHESTRA_SESSION_DIR'                \
  -e 'CLAUDE_PROJECT_DIR'                          \
  -e '~/.claude/'                                  \
  -e '"\.claude"'                                  \
  -e "'\.claude'"                                  \
  -e '~/.opencode/'                                \
  -e 'GLOBAL_CLAUDE_MD'                            \
  .
# Rerun with --include='*.md' for a manual review pass over docs/*.md.
```

A clean result is the strongest single signal that the port is complete. (Plan B's narrower pattern misses `GLOBAL_CLAUDE_MD` and `~/.opencode/`; Plan A omits the negative-grep step entirely.)

### 9.3 Positive-grep — must each return ≥1 match (Plan B + D)

```bash
grep -n 'OC_HOME' deploy.sh collect.sh
grep -n 'GLOBAL_AGENTS_MD' deploy.sh
grep -n 'OPENCODE_ORCHESTRA_SESSION_DIR' commands/brain.md agents/planner.md agents/reviewer.md
grep -n '"opencode"' scripts/bash-session-init.sh
grep -n 'claude-code-glm-5.1\|claude-code-qwen3-coder-next\|claude-code-kimi-k2.6' \
  agents/*.md config/pricing.yaml
grep -rn 'agents/actor-heavy' commands/brain.md collect.sh
```

### 9.4 Deploy --dry-run (Plan A §9.4)

```bash
./deploy.sh --dry-run
# Must show:
#   target:   /home/florian/.config/opencode
#   ...would create: /home/florian/.config/opencode/agent/actor-heavy.md
#   ...would create: /home/florian/.config/opencode/agent/planner.md
#   AGENTS.md guard:   (NOT "CLAUDE.md guard:")
```

### 9.5 Live render smoke test (Plan A §9.5)

After `./deploy.sh` and restarting OpenCode, run the five-step ctx + SoHoAI smoke test in `AGENTS.md` (low-fill, high-fill, 1M variant, SoHoAI helper, live render). All five steps must produce the expected output.

### 9.6 Model-assignment confirmation (Plan B)

```bash
grep '^model:' agents/*.md
# Expected, exactly:
#   agents/actor.md:        model: claude-code-qwen3-coder-next
#   agents/actor-heavy.md:  model: claude-code-kimi-k2.6
#   agents/planner.md:      model: claude-code-glm-5.1
#   agents/reviewer.md:     model: claude-code-kimi-k2.6
```

If any line shows an Anthropic model (Sonnet/Opus/Haiku), the port is broken — re-check §2 rule 1.

## 10. Single-commit policy (Plan D)

The whole port goes into **one commit** on `main`. Suggested message:

```
feat: bootstrap opencode-orchestra--non-Anthropic from CAN baseline + Phase 0 delta

- rsync claude-orchestra--non-Anthropic tree as the seed (excluding .git, .claude/,
  .opencode/, scripts/__pycache__/, scripts/orchestra-hook.sh.orig,
  utils/codebase_snapshot.md)
- apply Phase 0 CC→OC rename delta CAN missed: CLAUDE= → OC_HOME=, agents/ → agent/
  and commands/ → command/ deploy-target singular form, ~/.opencode/CLAUDE.md →
  ~/.config/opencode/AGENTS.md guard target, ~/.claude/ → ~/.config/opencode/
  runtime paths in Python scripts and status-line, claude → opencode process
  detection, CLAUDE_SESSION_ID fallback removal in orchestra-hook.sh,
  telemetry-summarize.sh, and four command files.
- add docs/architecture-decisions.md adapted from opencode-orchestra Phase 0
- delete docs/TODO.md (superseded by architecture-decisions.md per OP Phase 0)
- fix latent bugs surfaced during multi-plan review:
    utils/snapshot_codebase.py PROJECT_ROOT (was pointing at sibling project)
    agents/planner.md doc-impact rule (CLAUDE.md inside the rule body)
    README.md broken links (two) and repo-name references (four)
    scripts/ctx-segment.sh runtime path (status-line ctx fallback)

Preserved verbatim from CAN:
  - non-Anthropic model assignments (claude-code-glm-5.1, claude-code-qwen3-coder-next,
    claude-code-kimi-k2.6)
  - actor-heavy tier and [tier: heavy] dispatch in /brain
  - OPENCODE_ORCHESTRA_SESSION_DIR env var (CAN-correct; OP carries stale
    CLAUDE_ORCHESTRA_SESSION_DIR — do NOT import OP's name)
  - SoHoAI flat-rate pricing.yaml entries
  - query_litellm_cost() pricing.yaml override + claude-code-* alias detection
  - agents-md-block/orchestra-guard.md actor-heavy/planner-long dispatch language

Consolidated from four prior plans (docs/Sonnet-, Kimi-, Glm-, Opus-porting-plan.md).
Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

Rationale (Plan D §10): the port is mechanical and atomic; bisecting intermediate "partial port" commits has no value.

## 11. Open questions for operator (Plan D §11, expanded with Plans A + C inputs)

Each is a one-file decision with no architectural follow-on. Resolve before commit.

1. **`AGENTS.md` branch-policy section (§5.22).** CAN's `litellm-gateway` policy references a branch that doesn't exist in OAN yet. Plan D recommends: **delete for initial commit, re-add when OAN forks the branch**. Confirm.
2. **`docs/CC-to-OC-migration-plan.md` (§5.29).** Plan A keeps CAN's 120-line version; Plan D recommends deleting it because five porting plans already live in `docs/`. Confirm: keep, rename to `docs/legacy-Kimi-porting-plan.md`, or delete.
3. **`docs/design-history.md` (§5.26).** 15 historical `Claude Code` / `~/.claude/` / `CLAUDE.md` references remain. Plan A's stance — leave them as historical record. Confirm or request a polish pass.
4. **Repo URL (§5.23).** Plan D assumes `https://github.com/FlorianOtel/opencode-orchestra--non-Anthropic`. Confirm or correct.

## 12. Pre-commit checklist

- [ ] §4 rsync executed with all six exclusions
- [ ] §5.1 - §5.31 line-numbered edits applied
- [ ] §6.1 `docs/architecture-decisions.md` created with non-Anthropic metadata
- [ ] §7 deletions verified (or §4 exclusions prevented copy)
- [ ] §9.1 syntactic check passes
- [ ] §9.2 negative-grep returns no matches (across `*.sh`, `*.py`, `*.yaml`, `*.json`)
- [ ] §9.3 positive-grep returns expected matches
- [ ] §9.4 `./deploy.sh --dry-run` shows AGENTS.md guard, `agent/`/`command/` singular dirs
- [ ] §9.5 status-line smoke test five steps pass after deploy
- [ ] §9.6 model assignments match expected non-Anthropic values
- [ ] §11 operator decisions resolved
- [ ] `git diff --stat` ≈ 35 files (deploy.sh, collect.sh, 9 scripts, 5 commands, 4 agents, 4 configs, status-line, AGENTS.md, README.md, .gitignore, ~5 docs, snapshot_codebase.py, agents-md-block/orchestra-guard.md, new docs/architecture-decisions.md) — sanity check that nothing unexpected got staged

## 13. Acknowledgements

This plan is a synthesis. Credit:

- **Plan A** ([`Sonnet-porting-plan.md`](Sonnet-porting-plan.md)) provided the backbone — three-project framing (§1), preserve-from-CAN catalog (§2 / §8), most of the line-numbered file edits in §5, and the deploy smoke test (§9.4/§9.5).
- **Plan B** ([`Kimi-oc-non-A-porting.plan.md`](Kimi-oc-non-A-porting.plan.md)) contributed the stale-artefact cleanup (§4 exclusions, §7 deletions), the `scripts/telemetry-summarize.sh` edit (§5.5) that A and C both missed, the model-assignment confirmation grep (§9.6), and the concise verification structure (§9.1).
- **Plan C** ([`Glm--oc-non-A-porting.plan.md`](Glm--oc-non-A-porting.plan.md)) contributed the most granular preserve-from-CAN catalog (Phase 3a-3h, folded into §2 and §8), the explicit "files to NOT port from OP" list (Phase 4, folded into §8 footer), and the surfacing of the branch-policy decision (§5.22 / §11.1).
- **Plan D / Opus 4.7** ([`Opus-porting-plan.md`](Opus-porting-plan.md)) contributed the missed-edits sweep (`scripts/ctx-segment.sh`, `agents/planner.md:50`, `utils/snapshot_codebase.py`, README line-3 and repo-name fixes, design.md lines 243/280/296/522), the negative-grep verification (§9.2), the single-commit message text (§10), and the operator-facing open-questions structure (§11).

Where the plans disagreed, this Consolidated plan follows whichever was verified against the file-level evidence in CAN and OP:
- Plan B's "edit CAN in place" framing is rejected in favour of A/C/D's "bootstrap OAN from CAN".
- Plan C's claims about CAN containing `claude-md-block/`, `CLAUDE.md` file, and `agents/planner-long.md` are factual errors and are not adopted — CAN already renamed these or never had them.
- Plan A's "leave CAN's `docs/CC-to-OC-migration-plan.md` alone" is set aside as an open question (§11.2) rather than a default — five live porting plans in `docs/` are too many.
