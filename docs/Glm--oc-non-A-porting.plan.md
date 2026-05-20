---
title: "Porting Plan: claude-orchestra--non-Anthropic → opencode-orchestra--non-Anthropic"
created_at: 2026-05-20--19-23
created_by: Claude Code (GLM-5.1 via SoHoAI)
context: >
  Plan to port the oc-renaming and structural changes from opencode-orchestra (OP)
  into the claude-orchestra--non-Anthropic (CAN) codebase, producing
  opencode-orchestra--non-Anthropic (OAN) — a non-Anthropic model variant that
  uses OC directory paths and conventions. The target is nearly empty (README only).
  The strategy is: start from CAN (which has the non-Anthropic model assignments,
  SoHoAI routing, actor-heavy tier, pricing entries), then apply every OC path/branding
  rename that OP already did to the original CC codebase.
---

<!-- Opus-4.7> Overall framing: this plan correctly identifies all three projects
     (CAN/OP/OAN) and that OAN is the empty target. The "Start from CAN, apply OC renames"
     strategy is the right call. However, the plan contains several factual errors about
     CAN's contents that materially change the work: it claims CAN has `claude-md-block/`,
     `CLAUDE.md`, and `agents/planner-long.md` — all three of these claims are wrong (CAN
     already renamed claude-md-block/ to agents-md-block/, already renamed CLAUDE.md to
     AGENTS.md, and never had planner-long.md — deploy.sh actively removes it as an orphan).
     See inline annotations below. -->

# Porting Plan: CAN → OAN

## Goal

Produce `opencode-orchestra--non-Anthropic` (OAN): the non-Anthropic model variant
of opencode-orchestra, starting from the `claude-orchestra--non-Anthropic` (CAN)
codebase and applying the same CC→OC renaming pass that transformed the original
`claude-orchestra` into `opencode-orchestra`.

## Source projects

| Abbreviation | Full path | Role |
|---|---|--- |
| CAN | `~/Gin-AI/projects/claude-orchestra--non-Anthropic` | Source — has non-Anthropic models, SoHoAI pricing, actor-heavy tier |
| OP | `~/Gin-AI/projects/opencode-orchestra` | Reference — shows exactly what CC→OC renaming looks like |
| OAN | `~/Gin-AI/projects/opencode-orchestra--non-Anthropic` | Target — nearly empty, needs to be built |

## Key differences: CAN vs OP

These are the substantive (non-path) differences that must be **preserved from CAN**
rather than copied from OP:

1. **Agent models** — CAN uses non-Anthropic models; OP uses Anthropic models
   - CAN `actor.md`: `model: claude-code-qwen3-coder-next`
   - OP `actor.md`: `model: claude-haiku-4-5-20251001`
   - CAN `actor-heavy.md`: `model: claude-code-kimi-k2.6` (extra file, absent in OP)
   - CAN `planner.md`: `model: claude-code-glm-5.1` (with tier annotations)
   - OP `planner.md`: `model: claude-sonnet-4-6` (no tier annotations)
   - CAN `reviewer.md`: `model: claude-code-kimi-k2.6`
   - OP `reviewer.md`: `model: claude-sonnet-4-6`

2. **pricing.yaml** — CAN has SoHoAI non-Anthropic model entries (all $0.00) plus
   Anthropic entries for historical T2 fallback. OP has only Anthropic entries.

3. **planner.md tier annotations** — CAN's planner has an extended schema section
   with `[tier: fast]`, `[tier: default]`, `[tier: heavy]` step-level annotations.
   OP's planner has no tier annotations.

4. **brain.md tier-dispatch** — CAN's brain.md has a "Tier-aware dispatch" section
   for actor-heavy steps. OP's brain.md dispatches only the default actor.

5. **telemetry-summarize.py** — CAN has enhanced `query_litellm_cost()` with:
   - `pricing_data` parameter for pricing.yaml cache-rate override
   - `claude-code-*` alias detection (returns $0 for SoHoAI gateway models)
   - Litellm cache-rate override logic

6. **context-windows.yaml** — CAN has entries for non-Anthropic models
   (`claude-code-qwen3-coder-next`, `claude-code-kimi-k2.6`, `claude-code-deepseek-v4-pro`,
   `claude-code-glm-5.1`, plus local Ollama models). OP has Anthropic models only.

7. **Extra files in CAN** (not in OP):
   - `agents/actor-heavy.md`
   - `agents/planner-long.md` (not present in OP either)
   - `claude-md-block/orchestra-guard.md` (OP has `agents-md-block/` instead)
   - `docs/TODO.md`
   - `docs/architecture/` subdirectory

<!-- Opus-4.7> Factual errors here:
       - CAN does NOT have agents/planner-long.md. deploy.sh lines 159-163 actively
         remove planner-long.md as an orphan; the file is not in the repo's agents/.
       - CAN does NOT have claude-md-block/. It has agents-md-block/orchestra-guard.md
         (already renamed). The claim that "OP has agents-md-block/ instead" is reversed.
     Verify with: `ls ~/Gin-AI/projects/claude-orchestra--non-Anthropic/{agents,agents-md-block,claude-md-block}` -->

8. **Extra files in OP** (not in CAN):
   - `AGENTS.md` (project instructions file)
   - `agents-md-block/orchestra-guard.md` (renamed from `claude-md-block/`)
   - `docs/architecture-decisions.md`
   - `docs/CC-to-OC-migration-plan.md`

<!-- Opus-4.7> More factual errors:
       - CAN DOES have AGENTS.md (the project-instructions file is already renamed).
         Both projects ship AGENTS.md; they differ in content, not in name.
       - CAN DOES have agents-md-block/orchestra-guard.md (already renamed).
       - CAN DOES have a docs/CC-to-OC-migration-plan.md (a 120-line Kimi-authored
         porting plan; different from OP's 499-line claude.ai chat export, but same
         file path).
     The only file in OP not in CAN is `docs/architecture-decisions.md`. -->

## Execution strategy

**Start from CAN, apply OC renames.** This preserves all non-Anthropic-specific
content while gaining the OC path/branding changes. Then add the structural
improvements from OP that CAN lacks (AGENTS.md, architecture decisions doc, etc.).

The alternative (start from OP, add non-Anthropic models) was rejected because:
CAN has more diverged content (actor-heavy, tier system, SoHoAI pricing, enhanced
telemetry) and it's simpler to rename paths than to reconstruct this logic.

---

## Phase 1: Mechanical CC→OC rename pass

Copy CAN to OAN, then apply these string/file renames everywhere:

| Old (CC) | New (OC) |
|---|---|
| `~/.claude/` | `~/.config/opencode/` |
| `CLAUDE_PROJECT_DIR` | `OPENCODE_PROJECT_DIR` |
| `CLAUDE_SESSION_ID` | `OC_SESSION_ID` |
| `CLAUDE_CODE_SESSION_ID` | `OC_SESSION_ID` |
| `CLAUDE.md` | `AGENTS.md` |
| `.claude/orchestra/` | `.opencode/orchestra/` |
| `.claude/projects/` | `.config/opencode/projects/` |
| `.claude/active-sessions/` | `.config/opencode/active-sessions/` |
| `claude-md-block/` | `agents-md-block/` |
| `~/.claude/scripts/` | `~/.config/opencode/scripts/` |
| `~/.claude/agents/` | `~/.config/opencode/agent/` (singular) |
| `~/.claude/commands/` | `~/.config/opencode/command/` (singular) |
| `~/.claude/orchestra/` | `~/.config/opencode/orchestra/` |
| `Claude Orchestra` | `OpenCode Orchestra` |
| `Claude Code` | `OpenCode` |
| `CC session` | `OC session` |
| `CC process` | `OC process` |

<!-- Opus-4.7> Issues with this rename table:
       - A naive global sed for `CLAUDE_SESSION_ID` → `OC_SESSION_ID` would mangle
         every variable-substitution context, but more dangerously, a global sed for
         `Claude Code` → `OpenCode` would corrupt design-history.md historical
         passages. Mechanical sed is too blunt; Plan A's line-numbered approach is safer.
       - Missing rows for the items that affect OAN:
           - `~/.opencode/` (no .config/) → `~/.config/opencode/`
           - `~/.opencode/CLAUDE.md` (the guard target) → `~/.config/opencode/AGENTS.md`
           - `GLOBAL_CLAUDE_MD` variable name → `GLOBAL_AGENTS_MD`
           - `$CLAUDE=` shell var → `$OC_HOME=`
           - `agents/` (deploy target) → `agent/` (singular) — listed in row 9 only
             via "~/.claude/agents/", which doesn't catch the `$CLAUDE/agents/` form
       - The `claude-md-block/` row is moot — CAN doesn't have that directory; see
         the factual-errors comment above. -->

<!-- Opus-4.7> Missing from the rename table entirely:
       - `OPENCODE_ORCHESTRA_SESSION_DIR` — CAN's name (correct) must NOT be touched.
         This is dangerous because CAN/OP differ on this: OP has the stale
         CLAUDE_ORCHESTRA_SESSION_DIR. Anyone running "apply OP's rename to CAN"
         would inadvertently rename CAN's correct env var to OP's stale one.
         This needs an EXPLICIT "preserve OPENCODE_ORCHESTRA_SESSION_DIR, do not
         touch" rule before any sed pass runs. -->

Files affected (full list from diff analysis):

- `README.md` — full rewrite to OP style but preserving non-Anthropic model table
- `CLAUDE.md` → renamed to `AGENTS.md`
- `claude-md-block/orchestra-guard.md` → `agents-md-block/orchestra-guard.md`

<!-- Opus-4.7> Rename steps based on factually wrong premises:
       - `CLAUDE.md → AGENTS.md`: this rename was done already in CAN. There is no
         `CLAUDE.md` file in CAN to rename. The file already lives at `AGENTS.md`.
       - `claude-md-block/orchestra-guard.md → agents-md-block/orchestra-guard.md`:
         same — CAN already shipped this rename. The path is `agents-md-block/` in
         CAN today.
     What does need to happen: the BODY of the existing AGENTS.md and agents-md-block/
     orchestra-guard.md still carry CC-era residuals (BASH_ENV path, CC restart label,
     `~/.opencode/plans/`). These body edits are real; the file renames are not. -->
- `agents/actor.md`
- `agents/actor-heavy.md`
- `agents/planner.md`
- `agents/reviewer.md`
- `commands/brain.md`
- `commands/brain-abandon.md`
- `commands/duo-plan.md`
- `commands/duo-act.md`
- `commands/duo-abandon.md`
- `collect.sh`
- `deploy.sh`
- `scripts/orchestra-hook.sh`
- `scripts/bash-session-init.sh`
- `scripts/ctx-segment.sh`
- `scripts/sohoai-live-cost.sh`
- `scripts/native-session-report.sh`
- `scripts/native-session-report.py`
- `scripts/native-session-finalize.py`
- `scripts/native-subagent-cost.sh`
- `scripts/session-report.sh`
- `scripts/session-report.py`
- `scripts/smoke-test.sh`
- `scripts/telemetry-report.sh`
- `scripts/telemetry-summarize.sh`
- `scripts/telemetry-summarize.py`
- `scripts/otel-headers-helper.sh`
- `status-line/orchestra-block.sh`
- `config/settings-hooks.json`
- `utils/snapshot_codebase.py`
- All files under `docs/`

<!-- Opus-4.7> Appreciated about the file-list in Phase 1: it is the most complete
     enumeration of "files touched" among the three plans. It correctly includes
     ctx-segment.sh, otel-headers-helper.sh, smoke-test.sh, telemetry-report.sh, etc.
     But listing the file isn't enough — Plan C never specifies the exact edits.
     Compare Plan A's §§5.5-5.10 which give line numbers; Plan C just says
     "Copy + rename paths/branding" in the action-matrix at the end. -->

## Phase 2: Structural alignment with OP

Add files/directories that exist in OP but not in CAN:

1. **`AGENTS.md`** — Create a project instructions file modeled on OP's AGENTS.md
   but with non-Anthropic model table and CAN's smoke test entries. Replace CAN's
   `CLAUDE.md` with this.

<!-- Opus-4.7> Wrong — CAN already has AGENTS.md (with the right non-Anthropic smoke
     test entries and branch policy). The work is to EDIT CAN's AGENTS.md in-place
     in OAN to fix the ~9 lingering CC-era references (smoke test labels, BASH_ENV
     path, telemetry-flow header). Plan A's §5.16 has the correct line-numbered list.
     "Replace CAN's CLAUDE.md with this" is a no-op — there is no CLAUDE.md in CAN. -->

2. **`.gitignore`** — Copy from OP, adjust for OAN paths.

3. **`docs/architecture-decisions.md`** — Port from OP, preserving the four
   Phase 0 decisions. Content stays the same (the decisions are model-agnostic)
   but verify the CC→OC renames are applied.

4. **Delete `docs/TODO.md`** — OP removed this during Phase 0; OAN follows suit.

<!-- Opus-4.7> Appreciated: Phase 3's enumeration of preserve-from-CAN items (3a-3h)
     is comprehensive — including the planner.md tier annotations, brain.md
     tier-aware dispatch section, the enhanced query_litellm_cost() in
     telemetry-summarize.py, and the dynamic actor.md identity language. This is
     the strongest part of Plan C. Plan A captures the same content in its §3
     table but is less granular. -->

## Phase 3: CAN-specific content that MUST be preserved

These are the non-Anthropic differences from CAN that must survive the rename pass
unchanged in substance (only path/branding strings change):

### 3a. Agent model assignments

Keep CAN's models, rename only the orchestra branding:

| File | Model line | Keep as-is |
|---|---|---|
| `agents/actor.md` | `model: claude-code-qwen3-coder-next` | Yes |
| `agents/actor-heavy.md` | `model: claude-code-kimi-k2.6` | Yes (whole file preserved) |
| `agents/planner.md` | `model: claude-code-glm-5.1` | Yes |
| `agents/reviewer.md` | `model: claude-code-kimi-k2.6` | Yes |

### 3b. pricing.yaml non-Anthropic entries

Keep all SoHoAI `$0.00` entries. The Anthropic entries stay as historical T2 fallback
(unchanged from CAN, just path-neutral now).

### 3c. planner.md tier annotations

CAN's planner has an extended schema section with `[tier: fast]`, `[tier: default]`,
`[tier: heavy]` annotations and an example plan. This must be preserved — it's the
instructional content that tells Brain how to annotate plan steps for tier-aware
dispatch.

### 3d. brain.md tier-aware dispatch

CAN's brain.md Phase 2 section has:

```
**Tier-aware dispatch:** For each step or step-group, check the PLAN.md entry
for a `[tier: heavy]` annotation. If present, dispatch with `subagent_type:
actor-heavy`; otherwise use `subagent_type: actor` (default).
```

This section is absent in OP. It must be preserved in OAN.

### 3e. telemetry-summarize.py enhanced litellm cost

CAN's `query_litellm_cost()` has:
- `pricing_data` parameter with pricing.yaml cache-rate override
- `claude-code-*` alias detection (returns $0 for SoHoAI gateway aliases)
- Extended docstring explaining the override logic

These must be preserved. Only path strings (`~/.claude/` → `~/.config/opencode/`,
`Claude Code` → `OpenCode`) change.

### 3f. context-windows.yaml non-Anthropic entries

CAN has entries for `claude-code-qwen3-coder-next`, `claude-code-kimi-k2.6`,
`claude-code-deepseek-v4-pro`, `claude-code-glm-5.1`, and local Ollama models.
These must be preserved. OP only has Anthropic entries.

### 3g. actor.md identity assertion

CAN's actor.md says:

```
own identity — the executor model from the session system context — not
whatever identity Brain happened to write into the plan.
```

OP's actor.md hardcodes `Haiku 4.5 (claude-haiku-4-5-20251001)`. OAN should
use CAN's dynamic version (referencing the session context, not a hardcoded model)
since the actor model varies by tier.

### 3h. Extra smoke test entries

CAN's `CLAUDE.md` has a newer smoke test entry (2026-05-20 with non-Anthropic
models). Port this to OAN's `AGENTS.md` with OC paths.

<!-- Opus-4.7> Phase 3h "Extra smoke test entries" — slightly misleading. CAN's AGENTS.md
     already has the non-Anthropic smoke test entries. They are not "ported" from
     anywhere; they live in CAN. The work is just to clean up the CC-era language in
     their wrappers (e.g. "no CC restart needed" → "no OC restart needed"). -->

## Phase 4: Files to NOT port from OP

These OP files/content should NOT be brought into OAN because CAN's version is
the authoritative one:

1. **OP's `agents/planner.md`** — CAN's version has tier annotations; OP's doesn't.
2. **OP's `agents/actor.md`** — CAN's version has dynamic model identity; OP hardcodes.
3. **OP's `agents/reviewer.md`** — CAN has `claude-code-kimi-k2.6`; OP has `claude-sonnet-4-6`.
4. **OP's `pricing.yaml`** — CAN has SoHoAI entries; OP doesn't.
5. **OP's `context-windows.yaml`** — CAN has non-Anthropic models; OP doesn't.
6. **OP's `telemetry-summarize.py`** — CAN has enhanced litellm cost logic.

<!-- Opus-4.7> Appreciated: Phase 4 "do not port" list is correct — OP's planner.md
     (no tier annotations), OP's actor.md (hardcoded Haiku identity), OP's reviewer.md
     (Sonnet model), OP's pricing.yaml (no SoHoAI), OP's context-windows.yaml (no
     non-Anthropic), OP's telemetry-summarize.py (no pricing override). This is a
     useful "negative" complement to Phase 3's positive list. Plan A captures it
     implicitly in its §8 "no changes needed"; making it explicit (Plan C's
     approach) is clearer for operators. -->

## Phase 5: Verify consistency

After all phases, verify:

1. **No `CLAUDE_PROJECT_DIR`, `CLAUDE_SESSION_ID`, `.claude/`, or `Claude Code` references**
   remain in any file under OAN (except in historical/comments context).

2. **All agent models are non-Anthropic** — no `claude-haiku-4-5`,
   `claude-sonnet-4-6`, or `claude-opus-4-7` in `model:` frontmatter.

3. **All paths use `~/.config/opencode/`** — no `~/.claude/` in deploy scripts,
   commands, or shell scripts.

4. **SoHoAI features intact** — actor-heavy tier dispatch, tier annotations in
   planner, `$0.00` pricing entries, `claude-code-*` alias detection in telemetry.

5. **Git state** — verify `deploy.sh` references `~/.config/opencode/` and
   `collect.sh` references the same.

6. **Branch policy** — verify `AGENTS.md` documents the litellm-gateway merge
   policy from CAN's `CLAUDE.md`.

<!-- Opus-4.7> Branch policy issue: CAN's litellm-gateway policy assumes a litellm-gateway
     branch exists in the SAME repo. OAN is a separate, freshly-initialised repo with
     only a main branch. Re-documenting the policy verbatim in OAN's AGENTS.md is
     premature — the policy refers to a branch that doesn't exist yet. Decide:
       (a) delete the section in OAN, re-add when/if OAN gets a litellm-gateway branch
       (b) keep the section as a forward-looking commitment
     This is a real decision; Plan C surfaces it but doesn't resolve it. Plan A misses
     it entirely. My Opus plan §5.22 recommends (a). -->

<!-- Opus-4.7> Verify section is high-level but doesn't operationalise. Missing:
     - explicit grep commands (Plan B has them; Plan A has them)
     - `bash -n` syntax check (Plan B has it)
     - `./deploy.sh --dry-run` smoke test (Plan B has it)
     - Live-render ctx/SoHoAI test (Plan A has it via §9.5) -->

---

## File-by-file action matrix

| Source | Action | Notes |
|---|---|---|
| CAN `agents/actor.md` | Copy + rename paths/branding | Keep `model: claude-code-qwen3-coder-next`, dynamic identity text |
| CAN `agents/actor-heavy.md` | Copy + rename paths/branding | Doesn't exist in OP; keep entirely |
| CAN `agents/planner.md` | Copy + rename paths/branding | Keep tier annotations, `model: claude-code-glm-5.1` |
| CAN `agents/reviewer.md` | Copy + rename paths/branding | Keep `model: claude-code-kimi-k2.6` |
| CAN `commands/brain.md` | Copy + rename paths/branding | Keep tier-aware dispatch section; apply `TODO(Phase 2)` ExitPlanMode note from OP |
| CAN `commands/brain-abandon.md` | Copy + rename paths/branding | |
| CAN `commands/duo-plan.md` | Copy + rename paths/branding | |
| CAN `commands/duo-act.md` | Copy + rename paths/branding | |
| CAN `commands/duo-abandon.md` | Copy + rename paths/branding | |
| CAN `scripts/*` | Copy + rename paths/branding | All scripts get CC→OC path renames |
| CAN `status-line/orchestra-block.sh` | Copy + rename paths/branding | |
| CAN `config/config.yaml` | Copy + rename paths/branding | |
| CAN `config/context-windows.yaml` | Copy + rename paths/branding | Keep non-Anthropic model entries |
| CAN `config/pricing.yaml` | Copy + rename paths/branding | Keep SoHoAI $0 entries |
| CAN `config/settings-hooks.json` | Copy + rename paths/branding | |
| CAN `deploy.sh` | Copy + rename paths/branding | `~/.claude/` → `~/.config/opencode/`, `agents/` → `agent/`, `commands/` → `command/` |
| CAN `collect.sh` | Copy + rename paths/branding | Same path renames as deploy.sh |
| CAN `utils/snapshot_codebase.py` | Copy + rename paths/branding | Update project root path, `CLAUDE.md` → `AGENTS.md` |
| CAN `CLAUDE.md` | Copy → `AGENTS.md` + rename paths/branding | Rename file, update content with OC conventions |
| CAN `claude-md-block/orchestra-guard.md` | Copy → `agents-md-block/orchestra-guard.md` | Rename directory and file |
| CAN `docs/design.md` | Copy + rename paths/branding | Preserve all non-Anthropic model references |
| CAN `docs/design-history.md` | Copy + rename paths/branding | |
| CAN `docs/resources.md` | Copy + rename paths/branding | |
| CAN `docs/TODO.md` | **Delete** | Removed in OP's Phase 0 |
| OP `docs/architecture-decisions.md` | Copy (adapt) | Preserve 4 decisions; apply CC→OC renames |
| OP `AGENTS.md` | Create new | Model after OP's AGENTS.md but with CAN's non-Anthropic model table |
| OP `.gitignore` | Copy | Adjust paths if needed |
| OP `LICENSE` | Copy | Should be identical |

## Implementation order

1. **Copy CAN tree** to OAN (excluding `.git/`, `.claude/`, `__pycache__/`)
2. **Delete** `docs/TODO.md`
3. **Rename** `CLAUDE.md` → `AGENTS.md`, `claude-md-block/` → `agents-md-block/`
4. **Global find-replace** for all CC→OC path/branding strings
5. **Add** OP-only structural files (`docs/architecture-decisions.md`, `.gitignore`)
6. **Rewrite** `README.md` in OP style but with non-Anthropic model table
7. **Verify** — run `grep -r` for residual `~/.claude/`, `CLAUDE_PROJECT_DIR`, `Claude Code` references
8. **Git commit** — single commit with message describing the porting pass

<!-- Opus-4.7> Implementation order issues:
       - Step 3 is a no-op (renames already done in CAN).
       - Step 4 "Global find-replace" is dangerous: a sed sweep for `Claude Code` would
         corrupt design-history.md historical narrative; a sed sweep for
         `CLAUDE_SESSION_ID` is fine only because no current variable should retain
         that name; a sed sweep for `~/.opencode/` would mistakenly touch
         agents-md-block/orchestra-guard.md and the BASH_ENV path in AGENTS.md but
         could also touch unrelated strings. Better: line-by-line as Plan A does.
       - Step 5: `.gitignore` is not "OP-only" — CAN ships .gitignore too. The change
         is adding the `.claude/` entry (one line).
       - Step 6 "Rewrite README" is overkill. CAN's README is fine; just fix the broken
         links (line 3, 46) and the repo-name references (lines 54, 55, 137, 162).
     Net: this implementation order, executed naively, would corrupt several files. -->

<!-- Opus-4.7> Final summary of Plan C (GLM):
     STRENGTHS — best framing of the three plans on "what to preserve from CAN" (Phase 3
     is the most detailed) and "what NOT to port from OP" (Phase 4 is the only one to
     make this list explicit). The file-affected list in Phase 1 is the most complete.
     Correctly identifies all three projects and the "start from CAN" strategy.

     WEAKNESSES:
       1. CRITICAL: Multiple factual errors about CAN's contents — claims CAN has
          claude-md-block/, CLAUDE.md (file), and agents/planner-long.md, none of
          which are true. These errors trigger a phantom-rename phase that does nothing
          and obscures the real work.
       2. Relies on "global find-replace" / sed sweeps without enumerating line numbers,
          which is risky for design-history.md (historical passages) and dangerous for
          the OPENCODE_ORCHESTRA_SESSION_DIR vs CLAUDE_ORCHESTRA_SESSION_DIR mismatch
          (would silently downgrade CAN's correct name to OP's stale name).
       3. Verification is high-level prose, no executable greps or deploy --dry-run.
       4. README.md "full rewrite" recommendation is overkill — would discard CAN's
          working README content.

     RECOMMENDATION — Phases 3 and 4 are valuable; folding them into Plan A as preserved
     lists is the right move. The mechanical rename pass approach (Phase 1) should be
     discarded in favour of Plan A's line-numbered surgical edits. -->