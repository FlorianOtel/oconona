---
title: "Porting Plan: claude-orchestra--non-Anthropic → opencode-orchestra"
created_at: 2026-05-20--13-30
created_by: Claude Code (Claude Sonnet 4.6)
context: >
  The claude-orchestra--non-Anthropic project is a git worktree of opencode-orchestra,
  sharing the same git history. The main branch of opencode-orchestra contains three
  commits beyond origin/main that perform a Phase 0 CC→OC rename (branding, paths, env
  vars). The non-Anthropic branch has all the SoHoAI/telemetry/status-line features
  plus non-Anthropic model assignments (GLM-5.1, Qwen3, Kimi) but the Phase 0 rename
  is incomplete and inconsistent in places. This plan completes the rename while
  preserving all non-Anthropic model content.
---

<!-- Opus-4.7> CRITICAL FRAMING ISSUE — this plan misreads the target. The user's
     instructions specify the target as opencode-orchestra--non-Anthropic (OAN),
     which is a NEW, currently-empty repo (README only). This plan instead targets
     "complete the rename in claude-orchestra--non-Anthropic" — i.e., edit CAN in
     place. That is the WRONG project. OAN is the destination; CAN is a source.
     Every "make this change in CAN" step in this plan needs to be re-read as
     "make this change in OAN after rsyncing CAN as the seed". Re-titling alone
     fixes most of the doc but leaves the operator at risk of touching CAN by
     mistake. -->

# Porting Plan

## Objective

Complete the Phase 0 CC→OC rename in the `claude-orchestra--non-Anthropic` codebase
so it matches the completion standard of `opencode-orchestra/main`, while **preserving
all non-Anthropic model assignments** (GLM-5.1 Planner, Qwen3 Actor, Kimi K2.6
actor-heavy + Reviewer).

<!-- Opus-4.7> Appreciated: the Foundational Rule table (rows for planner/actor/actor-heavy/
     reviewer + pricing.yaml) is concise and accurate. The "Files confirmed identical to
     opencode-orchestra/main" list is useful negative scoping (Plan A buries the same
     information in §8). -->

## Foundational Rule

**NEVER change model assignments.** The following files are frozen — they are the
non-Anthropic differentiator and must not be touched:

| File | Non-Anthropic assignment |
|---|---|
| `agents/planner.md` | `model: claude-code-glm-5.1` |
| `agents/actor.md` | `model: claude-code-qwen3-coder-next` |
| `agents/actor-heavy.md` | `model: claude-code-kimi-k2.6` |
| `agents/reviewer.md` | `model: claude-code-kimi-k2.6` |
| `config/pricing.yaml` | Zero-rate entries for all `claude-code-*` models |

Files confirmed identical to opencode-orchestra/main (no action needed):
- `LICENSE`
- `config/config.yaml`
- `config/settings-hooks.json`
- `config/context-windows.yaml`
- `agents-md-block/orchestra-guard.md`
- Most shell scripts (`ctx-segment.sh`, `sohoai-live-cost.sh`, `smoke-test.sh`, etc.)

---

<!-- Opus-4.7> The plan's claim that LICENSE, config.yaml, settings-hooks.json,
     context-windows.yaml, agents-md-block/orchestra-guard.md are all "identical to OP"
     is partially WRONG:
       - context-windows.yaml: differs by two comment lines (CC → OC) and CAN has
         additional non-Anthropic + local-Ollama model entries. Comment-only fix needed.
       - agents-md-block/orchestra-guard.md: NOT identical to OP. CAN's version is RICHER
         (has actor-heavy/planner-long dispatch language and uses .opencode/orchestra/
         path; OP's uses the stale .claude/orchestra/ path). CAN's is preferred but
         needs a one-line fix at line 15 (~/.opencode/plans/ → ~/.config/opencode/plans/).
     Treating these as "no action needed" leaves real defects in the port. -->

## Phase 1 — Fix inconsistent shell variable names (deploy.sh, collect.sh)

### Problem
Both `deploy.sh` and `collect.sh` still use `CLAUDE=` as the target directory variable
name. The opencode-orchestra/main branch renamed this to `OC_HOME=`.

### `deploy.sh`
```diff
- CLAUDE="${HOME}/.config/opencode"
+ OC_HOME="${HOME}/.config/opencode"
```
Replace **all** occurrences of `$CLAUDE` with `$OC_HOME` throughout the file.

### `collect.sh`
```diff
- CLAUDE="${HOME}/.config/opencode"
+ OC_HOME="${HOME}/.config/opencode"
```
Replace **all** occurrences of `$CLAUDE` with `$OC_HOME` throughout the file.

Also add back the `actor-heavy.md` collection entry (exists in non-Anthropic but
was missing from the opencode-orchestra collect.sh):
```diff
+ collect_file "$OC_HOME/agent/actor-heavy.md"    "$REPO/agents/actor-heavy.md"
```

---

<!-- Opus-4.7> Phase 1 missing items:
       - deploy.sh dir creation list at line 66: needs `agents commands` → `agent command`
         (singular form OpenCode expects). Plan B mentions deploy.sh changes but doesn't
         flag this specific line.
       - deploy.sh deploy-target paths inside the agents/commands loops (lines 74, 92):
         `$CLAUDE/agents/` → `$OC_HOME/agent/`, `$CLAUDE/commands/` → `$OC_HOME/command/`.
       - All orphan-cleanup paths in §7a-7d also need the singular fix.
     The "Replace **all** occurrences of $CLAUDE" instruction implicitly handles the
     variable name, but the plural→singular rename is independent and gets missed. -->

## Phase 2 — Fix guard injection target (deploy.sh)

### Problem
The guard injection section in `deploy.sh` still targets `~/.opencode/CLAUDE.md`
and labels everything with "CLAUDE.md". It should target `~/.config/opencode/AGENTS.md`
and use "AGENTS.md" labeling, matching the opencode-orchestra/main branch.

### Changes in `deploy.sh`
```diff
- GLOBAL_CLAUDE_MD="$HOME/.opencode/CLAUDE.md"
+ GLOBAL_AGENTS_MD="$OC_HOME/AGENTS.md"
```
Replace **all** occurrences of `CLAUDE.md` in the guard injection section with
`AGENTS.md`. Labels like "CLAUDE.md guard:" become "AGENTS.md guard:".

---

## Phase 3 — Remove stale fallback env var (scripts/telemetry-summarize.sh)

### Problem
The TRANSCRIPT_ID fallback chain still includes `${CLAUDE_SESSION_ID:-…}` as a
fallback before `${OC_SESSION_ID:-}`. The opencode-orchestra/main branch removed
this because `CLAUDE_SESSION_ID` is a CC-specific env var that does not exist in
OpenCode.

### Change in `scripts/telemetry-summarize.sh`
```diff
- TRANSCRIPT_ID="${4:-${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-}}}"
+ TRANSCRIPT_ID="${4:-${OC_SESSION_ID:-}}"
```

---

## Phase 4 — Remove stale fallback env var (scripts/orchestra-hook.sh)

### Problem
The STAMP_SESSION variable still includes `${CLAUDE_SESSION_ID:-…}` as a
fallback before `${OC_SESSION_ID:-unknown}`.

### Change in `scripts/orchestra-hook.sh`
```diff
- STAMP_SESSION="${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-unknown}}"
+ STAMP_SESSION="${OC_SESSION_ID:-unknown}"
```

---

## Phase 5 — Fix process detection in native session init (scripts/bash-session-init.sh)

### Problem
`bash-session-init.sh` still detects the `claude` process (CC-specific) and
uses "CC" in comments. In OpenCode the process is named `opencode`.

### Changes in `scripts/bash-session-init.sh`
```diff
- # bash-session-init.sh — sourced via BASH_ENV on every CC Bash tool call.
+ # bash-session-init.sh — sourced via BASH_ENV on every OC Bash tool call.
```
```diff
- # Find stable CC main PID (top-level 'claude' process, not ephemeral node subprocesses).
+ # Find stable OC main PID (top-level 'opencode' process, not ephemeral node subprocesses).
```
```diff
- if [ "$_ppid_comm" != "claude" ]; then
+ if [ "$_ppid_comm" != "opencode" ]; then
```
```diff
-     [ "$_parent_comm" = "claude" ] && _cc_main_pid=$_parent
+     [ "$_parent_comm" = "opencode" ] && _cc_main_pid=$_parent
```

---

<!-- Opus-4.7> Phases 3, 4, 5 are accurate and focused — and Plan B is the ONLY one of
     the three existing plans to catch telemetry-summarize.sh's CLAUDE_SESSION_ID
     fallback (Phase 3). Plan A missed this. Appreciated. -->

<!-- Opus-4.7> Missing entirely between Phases 5 and 6:
       - All five command files (brain.md:399, brain-abandon.md:59, duo-act.md:101,
         duo-abandon.md:59) carry CLAUDE_SESSION_ID fallbacks in bash heredocs to the
         telemetry summarizer. Plan A correctly catches these in §§5.11-5.14. Plan B
         doesn't.
       - All Python scripts (session-report.py, native-session-report.py,
         native-session-finalize.py) have ~/.claude/ runtime paths. Plan A's §§5.6-5.8
         enumerate them. Plan B doesn't.
       - status-line/orchestra-block.sh has 6 stale ~/.opencode/active-sessions paths.
         Plan A's §5.5 catches them. Plan B doesn't.
       - scripts/ctx-segment.sh:41 yaml_file path.
     This is the largest gap in Plan B — it's about 60% of the actual edit surface. -->

## Phase 6 — Remove stale artifacts

| File | Action | Reason |
|---|---|---|
| `scripts/orchestra-hook.sh.orig` | Delete | Contains old `CLAUDE_SESSION_ID` references; stale backup from prior edits |
| `scripts/__pycache__/*.pyc` | Delete | Runtime artifacts; should already be gitignored |

<!-- Opus-4.7> Appreciated: Plan B is the ONLY one of the three to flag .orig and __pycache__.
     Both are real defects in CAN that would propagate to OAN if not handled. -->

---

## Phase 7 — Documentation cleanup (descriptive references only)

These files contain old CC naming in **descriptive text** (not executable paths).
Apply the same renames the opencode-orchestra/main branch applied.

<!-- Opus-4.7> Missing from Phase 7:
       - AGENTS.md needs ~9 CC→OC edits (smoke test labels, telemetry-flow header,
         BASH_ENV path on line 100). Plan A's §5.16 has the full list.
       - README.md needs 2 broken-link fixes (claude.ai/code on line 3 and the docs.anthropic
         link on line 46) plus repo-name updates.
       - utils/snapshot_codebase.py needs PROJECT_ROOT update + CLAUDE.md → AGENTS.md +
         missing actor-heavy entry.
       - agents/planner.md:50 has CLAUDE.md inside the doc-impact rule body.
       - docs/architecture-decisions.md needs to be CREATED (OP has it; CAN doesn't). -->

### `docs/design.md`
- Line 45: "CLAUDE.md guard" → "AGENTS.md guard"
- Line 243: References to `CLAUDE.md` in file inventory → `AGENTS.md`
- Line 522: `CLAUDE_SESSION_ID` → `OC_SESSION_ID`

### `docs/design-history.md`
- All `~/.claude/` references in historical examples → `~/.config/opencode/`
- All `CLAUDE.md` references in commentary → `AGENTS.md`
- All `CLAUDE_SESSION_ID` references → `OC_SESSION_ID`

### `docs/TODO.md`
- `CLAUDE.md` references → `AGENTS.md`
- `~/.claude/` paths already correct

<!-- Opus-4.7> docs/TODO.md should be DELETED, not edited. OP's Phase 0 intentionally
     removed it; the architecture decisions doc (docs/architecture-decisions.md) is its
     successor. Plan A and Plan C both correctly call for deletion. Plan B keeping it
     diverges from Phase 0 without stated rationale. -->

---

<!-- Opus-4.7> Appreciated: the Phase 8 verification block is structurally good — `bash -n`
     syntax check + negative grep + positive grep + dry-run deploy + model-assignment grep.
     The negative grep pattern (CLAUDE_SESSION_ID|CLAUDE_ORCHESTRA|~/.claude/) catches the
     big three. Could be tightened by also including 'GLOBAL_CLAUDE_MD' and '~/.opencode/'. -->

## Phase 8 — Verification steps

After all changes are applied, run the following:

```bash
cd /home/florian/Gin-AI/projects/claude-orchestra--non-Anthropic

# 1. Syntax check all shell scripts
bash -n deploy.sh collect.sh scripts/*.sh

# 2. Confirm no stale CC-specific env var references remain in executable files
! grep -rE 'CLAUDE_SESSION_ID|CLAUDE_ORCHESTRA|~/.claude/' \
  --include='*.sh' --include='*.md' --include='*.yaml' . \
  | grep -v 'design-history' | grep -v 'TODO' | grep -v 'Binary'

# 3. Confirm AGENTS.md branding is consistent
grep -c 'AGENTS.md' AGENTS.md deploy.sh collect.sh docs/design.md

# 4. Dry-run deploy
./deploy.sh --dry-run

# 5. Confirm model assignments are untouched
grep '^model:' agents/*.md
# Expected:
# agents/actor.md:        model: claude-code-qwen3-coder-next
# agents/actor-heavy.md:  model: claude-code-kimi-k2.6
# agents/planner.md:      model: claude-code-glm-5.1
# agents/reviewer.md:     model: claude-code-kimi-k2.6
```

---

## Rollback

`git checkout -- .` before first commit if anything goes wrong.

<!-- Opus-4.7> Final summary of Plan B (Kimi):
     STRENGTHS — focused, concise. Phases 3, 4, 5 are correct and Plan B is the only
     one of the three to catch telemetry-summarize.sh's CLAUDE_SESSION_ID fallback
     (Phase 3) and the .orig + __pycache__ stale artefacts (Phase 6). Good "Files
     identical to OP" negative scoping. Verification steps are well-structured.

     WEAKNESSES — three major and one critical:
       0. CRITICAL: targets CAN for in-place edits; the actual target is OAN (empty
          target repo). The whole plan reads as if it's modifying CAN.
       1. Misses ~60% of the edit surface: Python scripts, command-md heredocs,
          status-line/orchestra-block.sh paths, ctx-segment.sh, AGENTS.md,
          README.md, utils/snapshot_codebase.py, agents/planner.md:50.
       2. Misclassifies several files as "identical to OP" when they're not
          (context-windows.yaml comments; orchestra-guard.md path).
       3. Tells the operator to EDIT docs/TODO.md when OP's Phase 0 DELETED it.

     RECOMMENDATION — useful as a focused complement to Plan A (Plan B catches what
     A misses on .orig/__pycache__ and telemetry-summarize.sh); not viable as the
     primary plan because of items 0 and 1 above. -->

## Expected outcome

After this plan is executed, the `claude-orchestra--non-Anthropic` repo will have:
- All branding, paths, and env vars internally consistent with OpenCode naming
- No stray `CLAUDE.md`, `~/.claude/`, or `CLAUDE_SESSION_ID` references in executable files
- All non-Anthropic model assignments fully preserved
- A clean `./deploy.sh --diff` against `~/.config/opencode/` with no unexpected changes
