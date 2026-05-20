---
title: "Porting Plan: claude-orchestra--non-Anthropic → opencode-orchestra--non-Anthropic (Opus 4.7)"
created_at: 2026-05-20--23-00
created_by: Claude Code (Claude Opus 4.7, 1M context)
context: >
  Independent porting plan for building opencode-orchestra--non-Anthropic (OAN) from
  the claude-orchestra--non-Anthropic (CAN) baseline plus the Phase 0 CC→OC rename
  delta from opencode-orchestra (OP). Authored after reading CAN, OP, the three
  prior plans (Sonnet, Kimi, GLM), and direct file-level diffs of every script,
  agent, command, and doc that differs between CAN and OP. This plan favours
  surgical, verifiable changes and explicitly enumerates items the prior plans
  missed or got factually wrong.
---

# Porting Plan: CAN → OAN (Opus 4.7)

## 1. The three projects, named precisely

| Short | Path | State | Role |
|---|---|---|---|
| **CAN** | `~/Gin-AI/projects/claude-orchestra--non-Anthropic` | Worktree of OP; has non-Anthropic models, actor-heavy tier, SoHoAI pricing, but Phase 0 rename is **partial / inconsistent**. | Source baseline. |
| **OP**  | `~/Gin-AI/projects/opencode-orchestra` | Phase 0 CC→OC rename complete; ships Anthropic models, no actor-heavy, no SoHoAI pricing. | Reference for the rename delta. |
| **OAN** | `~/Gin-AI/projects/opencode-orchestra--non-Anthropic` | Empty except for README. | **Target.** This is the project to build. |

Critical framing the plans must get right: **the target is OAN, an empty repo. We do not "fix CAN in place." We bootstrap OAN from CAN's tree, then apply the Phase 0 delta from OP, then clean up CAN's known stale spots.**

> Note: CAN is a `git worktree` of OP (`.git` is a gitfile pointing into OP's worktrees/). That is why `git log` from inside CAN appears to share OP's history. This does not affect the porting — only the bootstrap mechanism (use `rsync`, not `git clone`, for the seed copy).

## 2. Foundational rules

1. **Never edit model assignments.** Non-Anthropic model IDs (`claude-code-glm-5.1`, `claude-code-qwen3-coder-next`, `claude-code-kimi-k2.6`) and the actor-heavy tier are the entire reason this project exists.
2. **Never edit `pricing.yaml`'s SoHoAI flat-rate entries.** Marginal cost is $0 per invocation by design.
3. **Never edit tier annotations** (`[tier: fast/default/heavy]` schema in `agents/planner.md`).
4. **Never edit actor-heavy dispatch logic** in `commands/brain.md`.
5. **Preserve `OPENCODE_ORCHESTRA_SESSION_DIR`.** CAN is correct; OP is stale (`CLAUDE_ORCHESTRA_SESSION_DIR`). Do **not** import OP's name.
6. **Preserve `agents-md-block/orchestra-guard.md`'s actor-heavy/planner-long dispatch.** CAN's guard is richer than OP's; do not overwrite it with OP's version.

## 3. Strategy in one paragraph

`rsync` CAN's tracked tree into OAN. Delete CAN-specific stale artefacts (`scripts/orchestra-hook.sh.orig`, `scripts/__pycache__/`, `docs/TODO.md`). Apply a small, named set of Phase 0 fixes that CAN missed: variable rename (`CLAUDE=` → `OC_HOME=`), deploy-dir singularization (`agents/` → `agent/`, `commands/` → `command/`), guard-injection target (`CLAUDE.md` → `AGENTS.md`), process-name detection (`claude` → `opencode`), Python script runtime paths (`~/.claude/` → `~/.config/opencode/`), status-line and ctx-segment runtime paths (`~/.opencode/` → `~/.config/opencode/`), session-ID fallback cleanup (`${CLAUDE_SESSION_ID:-}` → `${OC_SESSION_ID:-}`), and a handful of doc/comment cleanups. Add OP's `docs/architecture-decisions.md` (adapted to non-Anthropic context). Fix the broken README links. Commit once.

## 4. Step 0 — Bootstrap

From OAN's repo root:

```bash
# Seed: copy CAN's tracked tree, excluding .git and runtime state
rsync -av \
  --exclude='.git' \
  --exclude='.claude/' \
  --exclude='.opencode/' \
  --exclude='scripts/__pycache__/' \
  --exclude='scripts/orchestra-hook.sh.orig' \
  --exclude='utils/codebase_snapshot.md' \
  ~/Gin-AI/projects/claude-orchestra--non-Anthropic/ .

# Keep this plan and the other planning docs (they live in docs/)
# Verify nothing accidentally overwrote docs/Opus-porting-plan.md etc.
ls docs/
```

The exclusions above kill three known stale spots in one shot. The remaining work is content edits inside the seeded tree.

## 5. File-by-file changes, with line numbers

All line numbers reference CAN's current files as of 2026-05-20.

### 5.1 `deploy.sh`

| Line(s) | Change |
|---|---|
| 14 | `CLAUDE="${HOME}/.config/opencode"` → `OC_HOME="${HOME}/.config/opencode"` |
| 57 | `echo "  target: $CLAUDE"` → `echo "  target: $OC_HOME"` |
| 63 | `[ -d "$CLAUDE" ]` → `[ -d "$OC_HOME" ]` |
| 66 | `for dir in agents commands scripts orchestra` → `for dir in agent command scripts orchestra` |
| 67, 69 | `"$CLAUDE/$dir"` → `"$OC_HOME/$dir"`; `"$CLAUDE/orchestra/logs"` → `"$OC_HOME/orchestra/logs"` |
| 74 | `"$CLAUDE/agents/$(basename "$f")"` → `"$OC_HOME/agent/$(basename "$f")"` |
| 79-87 (drift-check block) | Replace `$REPO/agents/$base.md` / `$REPO/agents/$var.md` references — these read from the **repo**, not deploy target, so keep `$REPO/agents/`. Keep the block; it gates actor-heavy drift. |
| 92 | `"$CLAUDE/commands/$(basename "$f")"` → `"$OC_HOME/command/$(basename "$f")"` |
| 113, 114, 119-129, 133, 134, 137, 138 | All remaining `$CLAUDE/scripts/` → `$OC_HOME/scripts/`; `$CLAUDE/agents/` → `$OC_HOME/agent/` (the orphan cleanup paths); `$CLAUDE/commands/` → `$OC_HOME/command/`; `$CLAUDE/orchestra/` → `$OC_HOME/orchestra/`. |
| 154, 156, 160, 162, 173, 174, 181, 182 (orphan cleanup) | All `$CLAUDE/...` → `$OC_HOME/...`; `agents/` → `agent/`; `commands/` → `command/`. **Keep** the `planner-long.md` orphan-removal block (line ~160) — CAN does not ship planner-long, and OAN follows CAN, so the orphan removal stays relevant when redeploying over a previous OP install. |
| 188-190 | `"$CLAUDE/orchestra/<file>"` → `"$OC_HOME/orchestra/<file>"`. |
| 194 | `SETTINGS="$CLAUDE/settings.json"` → `SETTINGS="$OC_HOME/settings.json"` |
| 236 | `STATUS_LINE="$CLAUDE/scripts/status-line.sh"` → `STATUS_LINE="$OC_HOME/scripts/status-line.sh"` |
| 294 | Comment: `# ── 9. Inject orchestra-guard block into ~/.config/opencode/CLAUDE.md` → `# ── 9. Inject orchestra-guard block into ~/.config/opencode/AGENTS.md` |
| 295-300 | Update the body comment of section 9: replace `CLAUDE.md` with `AGENTS.md` in the explanatory paragraph. |
| 301 | `echo "CLAUDE.md guard:"` → `echo "AGENTS.md guard:"` |
| 302 | `GLOBAL_CLAUDE_MD="$HOME/.opencode/CLAUDE.md"` → `GLOBAL_AGENTS_MD="$OC_HOME/AGENTS.md"` |
| 304, 305, 310, 314, 317, 319, 321, 323, 327, 334, 335, 339, 340, 344, 346 | All `GLOBAL_CLAUDE_MD` → `GLOBAL_AGENTS_MD`; `CLAUDE.md` strings in messages → `AGENTS.md`; `~/.opencode/CLAUDE.md` → `~/.config/opencode/AGENTS.md`. |

Verification after edit: `bash -n deploy.sh` returns clean; `grep -n CLAUDE deploy.sh` returns only quoted text inside historical comments (if any).

### 5.2 `collect.sh`

| Line(s) | Change |
|---|---|
| 14 | `CLAUDE=...` → `OC_HOME=...` |
| 48 | `echo "  source: $CLAUDE"` → `echo "  source: $OC_HOME"` |
| 54-57 | `"$CLAUDE/agents/<file>"` → `"$OC_HOME/agent/<file>"`. Keep the `actor-heavy.md` line (CAN-specific). |
| 60-64 | `"$CLAUDE/commands/<file>"` → `"$OC_HOME/command/<file>"` |
| 67-69 | `"$CLAUDE/scripts/<file>"` → `"$OC_HOME/scripts/<file>"` |
| 72, 73 | `"$CLAUDE/orchestra/<file>"` → `"$OC_HOME/orchestra/<file>"` |

### 5.3 `scripts/bash-session-init.sh`

| Line(s) | Change |
|---|---|
| 2 | `# ... on every CC Bash tool call.` → `# ... on every OC Bash tool call.` |
| 4 | `# cc_pid (stable CC main process) ...` → `# cc_pid (stable OC main process) ...` (variable name stays `cc_pid` — it is referenced from orchestra-hook.sh; renaming it would be a larger refactor and is out of scope for this port.) |
| 18-22 | Comment block: replace `CC main PID` / `claude process` / `parent of node subprocess` references with `OC main PID` / `opencode process`. |
| 23 | `if [ "$_ppid_comm" != "claude" ]; then` → `if [ "$_ppid_comm" != "opencode" ]; then` |
| 26 | `[ "$_parent_comm" = "claude" ] && _cc_main_pid=$_parent` → `[ "$_parent_comm" = "opencode" ] && _cc_main_pid=$_parent` |

### 5.4 `scripts/orchestra-hook.sh`

| Line(s) | Change |
|---|---|
| 25 | Comment `... never block Claude` → `... never block OpenCode` |
| 32 | `STAMP_SESSION="${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-unknown}}"` → `STAMP_SESSION="${OC_SESSION_ID:-unknown}"` |
| 215 (insert) | After the PreCompact handler block, add: `# TODO(Phase 3): drop PreCompact — replaced by session.compacted plugin event in OC` (matches OP's annotation). |
| 269 | Comment `... never blocks Claude.` → `... never blocks OpenCode.` |
| 318 | Comment `multi-Claude-Code-session concurrency` → `multi-OpenCode-session concurrency` |
| 328 | Comment `whose CC process has ended` → `whose OC process has ended` |

### 5.5 `scripts/telemetry-summarize.sh`

| Line(s) | Change |
|---|---|
| 31 | Comment `Pass through CLAUDE_SESSION_ID if not explicitly given as 4th arg` → `Pass through OC_SESSION_ID if not explicitly given as 4th arg` |
| 32 | `TRANSCRIPT_ID="${4:-${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-}}}"` → `TRANSCRIPT_ID="${4:-${OC_SESSION_ID:-}}"` |

### 5.6 `scripts/ctx-segment.sh`  *(missed by Plans A and B)*

| Line(s) | Change |
|---|---|
| 41 | `yaml_file="$HOME/.opencode/orchestra/context-windows.yaml"` → `yaml_file="$HOME/.config/opencode/orchestra/context-windows.yaml"` |

This is the runtime path the status-line block calls at every status refresh. Leaving it pointing at `~/.opencode/` means ctx fallback breaks for every model whose ID is not in the YAML, with the failure mode being silent (returns `default` denominator).

### 5.7 `status-line/orchestra-block.sh`

| Line(s) | Change |
|---|---|
| 18 | `"$HOME/.opencode/orchestra/config.yaml"` → `"$HOME/.config/opencode/orchestra/config.yaml"` |
| 104 | `_lck="$HOME/.opencode/active-sessions/..."` → `_lck="$HOME/.config/opencode/active-sessions/..."` |
| 148 | `_sohoai_cache="$HOME/.opencode/active-sessions/..."` → `_sohoai_cache="$HOME/.config/opencode/active-sessions/..."` |
| 235 | `"$HOME/.opencode/active-sessions/..."` → `"$HOME/.config/opencode/active-sessions/..."` |
| 255 | `_sub_cache="$HOME/.opencode/active-sessions/..."` → `_sub_cache="$HOME/.config/opencode/active-sessions/..."` |
| 274 | `_cost_cache="$HOME/.opencode/active-sessions/..."` → `_cost_cache="$HOME/.config/opencode/active-sessions/..."` |
| Various comments | `CC-native progress bar` → `OC-native progress bar`; `CC reports 0% usage` → `OC reports 0% usage`; `CC gives no token counts` → `OC gives no token counts`; `override CC when` → `override OC when`; `CC model_id` → `OC model_id`; `CC's context_window_size` → `OC's context_window_size`; `CC provides cost.total_cost_usd` → `OC provides cost.total_cost_usd`; `Strip CC-native fields` → `Strip OC-native fields`. |

### 5.8 `scripts/session-report.py`

Three `~/.claude/projects` references, plus `~/.claude/native-sessions`, `~/.claude/orchestra/telemetry.jsonl`, `~/.claude/active-sessions`, `~/.claude/usage-data/session-meta`, all under `Path.home() / ".claude" / ...`. Replace each with `Path.home() / ".config" / "opencode" / ...` (one extra path component because `.config/opencode` is `~/.config/opencode`, not `~/.opencode`).

Critical: also fix the index-detection block (around line 245, but check the file):

```python
if ".claude" in parts:
    idx = parts.index(".claude")
```
→
```python
if ".opencode" in parts:
    idx = parts.index(".opencode")
```

Comment at ~line 240: `(legacy CC architecture)` → `(legacy OC architecture)`.

### 5.9 `scripts/native-session-report.py`

All `Path.home() / ".claude" / ...` references → `Path.home() / ".config" / "opencode" / ...`. Specifically:
- `".claude" / "orchestra" / "pricing.yaml"` (line ~62)
- `".claude" / "projects"` (lines ~80, ~299)
- `".claude" / "orchestra" / "telemetry.jsonl"` (line ~174)
- `".claude" / "active-sessions"` (line ~220)
- `".claude" / "usage-data" / "session-meta"` (line ~337)
- `".claude" / "native-sessions" / "telemetry.jsonl"` (line ~406)

### 5.10 `scripts/native-session-finalize.py`

| Line(s) | Change |
|---|---|
| 63 | Help text: `"CC session UUID (OC_SESSION_ID) for JSONL transcript lookup"` → `"OC session UUID (OC_SESSION_ID) for JSONL transcript lookup"` |
| 148 | `Path.home() / ".claude" / "orchestra" / "telemetry.jsonl"` → `Path.home() / ".config" / "opencode" / "orchestra" / "telemetry.jsonl"` |
| 186 | `Path.home() / ".claude" / "active-sessions" / ...` → `Path.home() / ".config" / "opencode" / "active-sessions" / ...` |
| 196 | `Path.home() / ".claude" / "native-sessions"` → `Path.home() / ".config" / "opencode" / "native-sessions"` |

### 5.11 `scripts/native-subagent-cost.sh`

Line 6 comment: `... a native CC session.` → `... a native OC session.`

(The Python heredoc paths inside the file are already correct at `~/.config/opencode/`.)

### 5.12 `scripts/telemetry-summarize.py`

Two `Path.home() / ".claude" / ...` paths (lines 54 and 100). Replace with `.config/opencode/...`. **Do not touch** the `query_litellm_cost()` function — it carries the non-Anthropic-specific `pricing_data` parameter, `claude-code-*` alias detection, and pricing.yaml cache-rate override logic. This is the key SoHoAI-pipeline enhancement in CAN versus OP. Keep verbatim.

### 5.13 `config/context-windows.yaml`

Two comment-only changes:
- `#   model_id isn't here: CC's own context_window.context_window_size.` → `OC's own context_window.context_window_size.`
- `# Fallback: CC's own context_window.context_window_size if model_id absent.` → `OC's own context_window.context_window_size if model_id absent.`

The non-Anthropic and local-Ollama model entries are preserved verbatim.

### 5.14 `commands/brain.md`

| Line(s) | Change |
|---|---|
| 19 | `/home/florian/.opencode/plans/<name>.md` → `/home/florian/.config/opencode/plans/<name>.md` |
| 110 | Comment `... content = CC process PID (lookup key).` → `... content = OC process PID (lookup key).` |
| 117 | Comment `... whose CC process is no longer running.` → `... whose OC process is no longer running.` |
| 399 | Bash heredoc fallback: `... echo \"${CLAUDE_SESSION_ID:-}\")` → `... echo \"${OC_SESSION_ID:-}\")` |

**Do not change**:
- `export OPENCODE_ORCHESTRA_SESSION_DIR="${SESSION_DIR}"` (line 88)
- The non-Anthropic prerequisite / model check block
- The Tier-aware dispatch instructions (`subagent_type: actor-heavy` for `[tier: heavy]` steps)
- The references to `~/.config/opencode/plans/` already present on lines 21, 23, 36, 236 (these are correct)

Optionally, add a `# TODO(Phase 2): replace with /brain-plan + /brain-act split` comment near the `ExitPlanMode` call to match OP's Phase 0 annotations. This is informational only and does not change behaviour.

### 5.15 `commands/duo-plan.md`

| Line(s) | Change |
|---|---|
| 114 | Comment `... CC process PID ...` → `... OC process PID ...` |
| 121 | Comment `... whose CC process is no longer running.` → `... whose OC process is no longer running.` |

Do NOT change `OPENCODE_ORCHESTRA_SESSION_DIR` (line 131); already correct.

### 5.16 `commands/duo-act.md`

Line 101: `echo \"${CLAUDE_SESSION_ID:-}\")` → `echo \"${OC_SESSION_ID:-}\")`.

### 5.17 `commands/duo-abandon.md`

Line 59: `echo \"${CLAUDE_SESSION_ID:-}\")` → `echo \"${OC_SESSION_ID:-}\")`.

### 5.18 `commands/brain-abandon.md`

Line 59: `echo \"${CLAUDE_SESSION_ID:-}\")` → `echo \"${OC_SESSION_ID:-}\")`.

### 5.19 `agents/planner.md`  *(missed by all three plans)*

Line 50, inside step 5 of the "Schema" section, the body of the doc-impact rule:

```
Scan for: root-level `*.md` files (`CLAUDE.md`, `README*.md`, ...
... any file referenced from CLAUDE.md's project-file inventory.
```

Replace both occurrences of `CLAUDE.md` with `AGENTS.md`. The project's project-instructions file in OAN is `AGENTS.md`; CAN already renamed the file, but missed updating this internal reference inside the planner's instructional text.

Do NOT change `model: claude-code-glm-5.1`, the tier annotations, or `OPENCODE_ORCHESTRA_SESSION_DIR`.

### 5.20 `agents/actor.md`, `agents/actor-heavy.md`, `agents/reviewer.md`

No changes required (CAN already has correct models, `OPENCODE_ORCHESTRA_SESSION_DIR`, and the generic "executor model from the session system context" identity language).

### 5.21 `agents-md-block/orchestra-guard.md`

| Line(s) | Change |
|---|---|
| 15 | `/home/florian/.opencode/plans/<name>.md` → `/home/florian/.config/opencode/plans/<name>.md` |

CAN's guard already has the correct `.opencode/orchestra/sessions/` path and the actor-heavy / planner-long dispatch language. This is the **only** path fix needed in this file.

### 5.22 `AGENTS.md`

| Line(s) | Change |
|---|---|
| 31 | `... (CC 2.1.132: not called ...)` → `... (OC 2.1.132: not called ...)` |
| 65 | `### Status-line ctx + SoHoAI cost smoke test (no CC restart needed)` → `... (no OC restart needed)` |
| 80 | `send any message to CC;` → `send any message to OC;` |
| 85 | `Open a fresh CC session` → `Open a fresh OC session` |
| 88 | `In another CC session` → `In another OC session` |
| 94 | `**Telemetry flow (CC 2.1.132):**` → `**Telemetry flow (OC 2.1.132):**` |
| 95 | `not called by CC 2.1.132` → `not called by OC 2.1.132` |
| 96 | `stable CC main process` → `stable OC main process` |
| 100 | `BASH_ENV=/home/florian/.opencode/scripts/bash-session-init.sh` → `BASH_ENV=/home/florian/.config/opencode/scripts/bash-session-init.sh` |

The **branch policy section** (lines 10-24) belongs to CAN's repo workflow (main → litellm-gateway). OAN does not yet have a `litellm-gateway` branch. **Decision needed**: delete the section, or replace with an OAN-specific equivalent. My recommendation: **delete it for the initial commit**; re-add only if/when OAN forks a litellm-gateway branch. (Plan A and Plan B miss this; Plan C correctly notes the policy must be re-documented but doesn't decide.)

### 5.23 `README.md`

| Line(s) | Change |
|---|---|
| 3 | `[OpenCode](https://claude.ai/code)` → `[OpenCode](https://opencode.ai)` *(broken hostname — Plan A only fixes line 46)* |
| 46 | `[OpenCode](https://docs.anthropic.com/en/docs/claude-code)` → `[OpenCode](https://opencode.ai)` |
| 54 | `git clone https://github.com/FlorianOtel/opencode-orchestra` → `git clone https://github.com/FlorianOtel/opencode-orchestra--non-Anthropic` |
| 55 | `cd opencode-orchestra` → `cd opencode-orchestra--non-Anthropic` |
| 137 | `cd opencode-orchestra` → `cd opencode-orchestra--non-Anthropic` |
| 162 | `opencode-orchestra/` (ASCII tree root) → `opencode-orchestra--non-Anthropic/` |
| Model tier table (lines 7-12) | Expand to name non-Anthropic models explicitly: |

```markdown
| Tier | Model | Fallback | Role |
|---|---|---|---|
| **Brain** | Your main session (`claude-code-kimi-k2.6` recommended) | — (main session) | Orchestrates, delegates, approves |
| **Planner** | `claude-code-glm-5.1` | — | Decomposes tasks into numbered, reviewable plans |
| **Actor** | `claude-code-qwen3-coder-next` | `claude-code-kimi-k2.6` for `[tier: heavy]` steps | Executes individual plan steps; scoped, fast, cheap |
| **Reviewer** | `claude-code-kimi-k2.6` | — | Reviews Actor's output; emits PASS / FIX / BLOCK verdicts |
```

### 5.24 `utils/snapshot_codebase.py`  *(missed by all three plans)*

| Line(s) | Change |
|---|---|
| 29 | `PROJECT_ROOT = Path("/mnt/nfs/Florian/Gin-AI/projects/opencode-orchestra")` → `PROJECT_ROOT = Path("/mnt/nfs/Florian/Gin-AI/projects/opencode-orchestra--non-Anthropic")` |
| 35 | `"CLAUDE.md",` → `"AGENTS.md",` |
| ~40 (file list) | Add `"agents/actor-heavy.md",` after `"agents/actor.md",` |
| 47 | Comment `# Claude.md injection block` → `# AGENTS.md injection block` |

CAN's `PROJECT_ROOT` is misleadingly pointed at the wrong sibling project. This is a latent bug in CAN that becomes a real bug in OAN if not fixed (snapshot would render from the wrong tree).

### 5.25 `docs/design.md`

| Anchor | Change |
|---|---|
| Line 45 (long paragraph) | `~/.config/opencode/CLAUDE.md` (2 occurrences) → `~/.config/opencode/AGENTS.md`; `CLAUDE.md guard is the load-bearing component` → `AGENTS.md guard is the load-bearing component` |
| Lines 58-61 (Agent table) | `~/.config/opencode/agents/<file>.md` → `~/.config/opencode/agent/<file>.md` (singular, all 4 rows) |
| Line 112 | `It replaces the CC-native progress bar` → `It replaces the OC-native progress bar` |
| Line 131 | `Without this fix CC's context_window_size` → `Without this fix OC's context_window_size` |
| Line 243 | `CLAUDE.md  (sentinel-bracketed orchestra-guard block ...)` → `AGENTS.md  (sentinel-bracketed orchestra-guard block ...)` |
| Line 280 | `rm -rf ~/.config/opencode/agents/{planner,actor,reviewer}.md ~/.config/opencode/commands/{brain,duo}.md` → `... agent/{planner,actor,actor-heavy,reviewer}.md ... command/{brain,duo}.md` |
| Line 296 | `Subagent definitions (.opencode/agents/*.md ...)` → `... .opencode/agent/*.md ...` |
| Line 522 | `CLAUDE_SESSION_ID is not set in subprocess environments` → `OC_SESSION_ID is not set in subprocess environments` (the historical context still references the variable name CC used; updating to OC keeps the doc internally consistent) |

### 5.26 `docs/design-history.md`

15 occurrences of `Claude Code` / `~/.claude/` / `CLAUDE.md` remain in CAN. These are historical-narrative passages. Recommendation: **leave them as historical record** (Plan A's stance — CAN's design-history is "already updated to OpenCode throughout"). Validate by re-grepping; if any are forward-looking or instructional rather than historical, rename those individually.

Optional polish: replace `~/.claude/` paths inside historical examples with `~/.config/opencode/` if the example is meant to teach current usage; preserve if the example is timestamped as a CC-era operation.

### 5.27 `docs/resources.md`

Both versions are near-identical. Apply the one or two CC-era references CAN still carries (run a fresh grep after copy).

### 5.28 `docs/architecture/2026-04-28-headless-revert.md`

Metadata-only delta between CAN and OP (model field in frontmatter). No changes needed for OAN — keep CAN's version.

### 5.29 `docs/CC-to-OC-migration-plan.md`

CAN has a 120-line "Porting opencode-orchestra--non-Anthropic to opencode-orchestra conventions" doc (the earlier Kimi-authored porting plan). OP has the 499-line claude.ai chat-export migration plan. **Decision**: keep CAN's version, but rename to something less misleading — e.g., `docs/legacy-Kimi-porting-plan.md` — so it does not conflict with the Sonnet/Kimi/GLM/Opus/Consolidated plans already in this `docs/` directory. Alternative: delete it (its content is superseded by the Sonnet/Opus/Consolidated plans). My recommendation: **delete**, because keeping multiple porting plans live invites drift.

### 5.30 `docs/TODO.md`

Delete. OP's Phase 0 deleted it as part of the architectural-decisions move. OAN follows OP on Phase 0 outcomes.

### 5.31 `.gitignore`

Add `.claude/` next to the existing `.opencode/` entry — matches OP's Phase 0 addition.

## 6. New files to create

### 6.1 `docs/architecture-decisions.md`

Copy OP's `docs/architecture-decisions.md` verbatim, then update:

```yaml
---
title: "OpenCode Orchestra (non-Anthropic) — Phase 0 Architecture Decisions"
created_at: 2026-05-20--23-00
created_by: Claude Code (Claude Opus 4.7, 1M context) — adapted from opencode-orchestra Phase 0
context: >
  Four architectural decisions inherited from the opencode-orchestra Phase 0 migration,
  applied to the non-Anthropic variant. All four decisions (Plan-approval gate,
  Pre-compact state, SoHoAI routing, Status-line cost display) are unchanged in substance.
  Decision 3 (SoHoAI routing: option C — all traffic through SoHoAI) is even more
  load-bearing here because the entire non-Anthropic pipeline depends on SoHoAI's
  LiteLLM router for model aliasing.
---
```

The body (Decisions 1-4) is identical. No model-specific edits.

## 7. Files to delete (post-rsync)

The exclusions in §4 prevent these from being copied. If you skipped them, delete:
- `scripts/orchestra-hook.sh.orig` — stale backup, dead code path.
- `scripts/__pycache__/` — runtime artifact, must be gitignored.
- `docs/TODO.md` — deleted in OP's Phase 0.
- (Optionally) `docs/CC-to-OC-migration-plan.md` — see §5.29.
- `utils/codebase_snapshot.md` — gitignored runtime artifact (see CAN's .gitignore line 21).

## 8. Files explicitly NOT changed (preserved verbatim from CAN)

| File | Reason |
|---|---|
| `agents/actor.md` | model + dynamic identity text + `OPENCODE_ORCHESTRA_SESSION_DIR` already correct. |
| `agents/actor-heavy.md` | CAN-only; preserve entirely. |
| `agents/planner.md` | Only line-50 `CLAUDE.md` strings change (see §5.19); tier schema and model preserved. |
| `agents/reviewer.md` | Already correct in CAN. |
| `config/config.yaml` | Identical between CAN and OP. |
| `config/settings-hooks.json` | Identical between CAN and OP. |
| `config/pricing.yaml` | Non-Anthropic flat-rate entries are the differentiator. |
| `config/context-windows.yaml` | Only two comment-text edits (§5.13); non-Anthropic and local-Ollama entries preserved. |
| `scripts/sohoai-live-cost.sh` | Already uses `~/.config/opencode/`. |
| `scripts/native-session-report.sh` | Wrapper; no path issues. |
| `scripts/session-report.sh` | Wrapper; no path issues. |
| `scripts/telemetry-report.sh` | Already uses `~/.config/opencode/`. |
| `scripts/smoke-test.sh` | Already uses `OPENCODE_PROJECT_DIR`. |
| `scripts/otel-headers-helper.sh` | Already correct (`OC_SESSION_ID`). |
| `LICENSE` | No changes. |

## 9. Verification

After all edits, **before committing**, run all of the following and require each to pass:

### 9.1 Syntactic
```bash
bash -n deploy.sh collect.sh scripts/*.sh status-line/*.sh
python3 -m py_compile scripts/*.py utils/*.py
```

### 9.2 Negative greps (must return zero matches under .)

```bash
grep -rn --include='*.sh' --include='*.py' --include='*.md' --include='*.yaml' --include='*.json' \
  -e '\$CLAUDE\b' \
  -e 'CLAUDE_SESSION_ID' \
  -e 'CLAUDE_CODE_SESSION_ID' \
  -e 'CLAUDE_ORCHESTRA_SESSION_DIR' \
  -e 'CLAUDE_PROJECT_DIR' \
  -e '~/.claude/' \
  -e '"\.claude"' \
  -e "'\.claude'" \
  -e '~/.opencode/' \
  -e 'GLOBAL_CLAUDE_MD' \
  --exclude='*.md' \
  .
# (Drop the --exclude='*.md' to find any in design-history etc. as a manual review pass.)
```

A clean result here is the strongest single signal that the port is complete.

### 9.3 Positive greps (must each return ≥ 1 match)

```bash
grep -n 'OC_HOME' deploy.sh collect.sh
grep -n 'GLOBAL_AGENTS_MD' deploy.sh
grep -n 'OPENCODE_ORCHESTRA_SESSION_DIR' commands/brain.md agents/planner.md
grep -n '"opencode"' scripts/bash-session-init.sh
grep -n 'claude-code-glm-5.1\|claude-code-qwen3-coder-next\|claude-code-kimi-k2.6' agents/*.md config/pricing.yaml
grep -rn 'agents/actor-heavy' commands/brain.md collect.sh
```

### 9.4 Deploy smoke test (read-only)

```bash
./deploy.sh --dry-run
# Expected lines (verify these specifically):
#   target: /home/florian/.config/opencode
#   would create: /home/florian/.config/opencode/agent/actor-heavy.md
#   would create: /home/florian/.config/opencode/agent/planner.md
#   AGENTS.md guard: ... (NOT "CLAUDE.md guard")
```

### 9.5 Live render smoke test (post-deploy, post-OpenCode-restart)

The five-step smoke test currently in `AGENTS.md` (ctx low-fill, ctx high-fill, ctx 1M, SoHoAI helper, live render). Each must produce the expected output. If any step fails, the §5 edits are incomplete.

## 10. Single-commit policy

This entire porting work goes into **one commit** on `main`. Commit message:

```
feat: bootstrap opencode-orchestra--non-Anthropic from CAN baseline + Phase 0 delta

- rsync claude-orchestra--non-Anthropic tree as the starting point
- apply Phase 0 CC→OC rename delta (CLAUDE= → OC_HOME=, agents/ → agent/,
  commands/ → command/, CLAUDE.md → AGENTS.md guard target, .claude/ → .config/opencode/
  runtime paths, claude process → opencode process detection)
- remove stale CAN artefacts (scripts/orchestra-hook.sh.orig, __pycache__/, docs/TODO.md)
- add docs/architecture-decisions.md adapted from opencode-orchestra Phase 0
- fix latent bugs found during port: utils/snapshot_codebase.py PROJECT_ROOT,
  agents/planner.md doc-impact rule references, README.md broken links,
  scripts/ctx-segment.sh runtime path

Preserved verbatim from CAN: all non-Anthropic model assignments
(claude-code-glm-5.1 / claude-code-qwen3-coder-next / claude-code-kimi-k2.6),
actor-heavy tier, [tier: heavy] dispatch in /brain, OPENCODE_ORCHESTRA_SESSION_DIR
env var, SoHoAI flat-rate pricing entries, query_litellm_cost() pricing.yaml
override + claude-code-* alias detection.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
```

Rationale for one commit: the port is mechanical and atomic from a release-management perspective; bisecting through intermediate "partial port" commits provides no value.

## 11. Open questions for the operator

1. **Branch policy section in AGENTS.md (§5.22):** delete entirely, or rewrite for a yet-to-exist OAN-side litellm-gateway branch?
2. **`docs/CC-to-OC-migration-plan.md` (§5.29):** delete, rename, or keep as-is?
3. **Repo URL in README (§5.23):** I assumed `https://github.com/FlorianOtel/opencode-orchestra--non-Anthropic`. Confirm or correct.
4. **`docs/design-history.md` (§5.26):** do you want a polish pass on the 15 remaining historical `Claude Code` / `~/.claude/` references, or leave them as historical record?

Decide before commit; each affects exactly one file.

## 12. Why this plan is structured this way

- **CAN-first bootstrap**, not OP-first: CAN has more divergent and harder-to-reproduce content (tier annotations, actor-heavy, enhanced telemetry-summarize, SoHoAI pricing, context-windows for non-Anthropic models). Starting from OP and re-applying these would be tedious and error-prone.
- **Line numbers, not regex sweeps**: a global `sed -i` for `CLAUDE` → `OC` would destroy `OPENCODE_ORCHESTRA_SESSION_DIR` and the historical-record passages. Surgical edits are slower to read but safer to execute.
- **Negative-grep verification, not positive checklists alone**: a verification step that asks "is *anything* still stale?" catches sites you didn't think to enumerate. The grep in §9.2 covers every known stale pattern.
- **Single commit**: this is migration plumbing, not a feature rollout. Operators bisect features, not plumbing.
- **Operator-facing open questions in §11**: each is a one-file decision with no architectural follow-on. Surface them early; do not assume.
