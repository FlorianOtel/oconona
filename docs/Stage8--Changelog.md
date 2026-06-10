---
title: "Stage 8 — Changelog"
created_at: 2026-06-05--13-00
created_by: Actor (Claude Haiku 4.5 — via oconona /brain Stage 8 dispatch)
updated_by: Claude Opus 4.7 (1M context) — via oconona em-dash tier sweep (v8.4.1)
updated_at: 2026-06-08--09-00
context: >
  Per-version changelog for Stage 8 of the oconona orchestra
  (Researcher tier + Brain Phase 0 hardening + telemetry counter).
  Mirrors the Stage 7 changelog format. Each entry references the
  shipping commit hash and a short summary; deeper context lives in
  docs/Stage8.md.
---

# Stage 8 — Changelog

## v8.4.2 — SNAPEOF heredoc extraction — model-parse robustness

**Shipped:** 2026-06-10
**Code commit:** `135cc3ee2d3216623730a4417ba25368dbba1eef` (short: `135cc3e`)

### What shipped

- **Extract Python snippet from inline heredocs to `scripts/oc-snapshot.py`:** Less-capable models (minimax-m3) mis-parsed the `<<'SNAPEOF'` heredoc pattern in `commands/duo-plan.md` and `commands/brain.md` setup blocks, seeing a conflict with nearby while-loop `done` keywords. Root cause: raw `SNAPEOF` terminator in an unquoted context triggers false conflict detection in syntactically-naive parsers. Fixed by extracting the 5-line Python snippet (`import os, json, importlib.util` through `if snap: print(...)`) to a dedicated `scripts/oc-snapshot.py` file.

- **Four call-sites refactored:** `commands/duo-plan.md` (line 137), `commands/brain.md` (line 174), `scripts/orchestra-hook.sh` (line 274), `scripts/orchestra-cleanup.sh` (line 57). All now use plain file-based invocation (`python3 "${HOME}/.config/opencode/scripts/oc-snapshot.py"`) instead of inline heredocs. Pipeline semantics unchanged; heredoc replaced with explicit file reference.

- **`deploy.sh` updated:** Added `oc-snapshot.py` to the Python files loop (section 5) so the script is copied to `~/.config/opencode/scripts/` on every deploy.

### Why

The heredoc pattern is syntactically valid bash and runs correctly in all real shells. However, less-capable LLMs running in octmux (e.g., minimax-m3 dispatched as Planner) don't parse bash heredocs reliably — they see the `SNAPEOF` terminator and surrounding context and infer a structural conflict rather than recognizing the heredoc as a single atom. Extracting the Python code to a file removes the pattern entirely, making the call-site a straightforward file invocation that all parsers handle identically. Signal value: if a future octmux agent mis-parses this simpler form, the problem is not bash syntax but a more fundamental model limitation.

### Files changed

- `scripts/oc-snapshot.py` (new file, 5 lines)
- `commands/duo-plan.md`, `commands/brain.md`, `scripts/orchestra-hook.sh`, `scripts/orchestra-cleanup.sh` (code commit `135cc3e`)
- `deploy.sh` (code commit `135cc3e`)

---

## v8.4.1 — em-dash tier-tag convention + Known platform issues capture

**Shipped:** 2026-06-08
**Code commit:** `6fc848119a7fbdc65e93de15a3cee30082bcf407` (short: `6fc8481`)

### What shipped

- **Repo-wide tier-tag convention change — `[tier: X]` → `[tier — X]` (em-dash U+2014 with spaces):** Active code references updated in `agents/planner.md` (schema + example plan), `agents/actor-heavy.md` (frontmatter description + body), `commands/brain.md` (dispatch instructions), `agents-md-block/orchestra-guard.md` (in-pipeline guard), `README.md` (model tiers table). The em-dash separator is YAML-safe in any context (no `:` to trigger a flow-context mapping interpretation) and reads naturally in prose. The legacy colon-space form is retained verbatim only in (a) one labelled historical example in brain.md, (b) the v8.4.0 changelog entry below describing the original poison.

- **`docs/design.md` § "Known platform issues" (new section)** — captures KP-1 (silent agent-frontmatter parse failure / `model: null` fallback) and KP-2 (`main` vs `git_worktree` `project_directory` divergence) as named platform-level issues, with symptoms, root causes, mitigations, and author-time discipline. Forward-pointer from `agents/planner.md` and `commands/brain.md` Tier-aware dispatch sections so the convention is self-documenting from inside the agent files. Author-time discipline statement: no unquoted `[key: value]` substrings in agent-frontmatter scalars.

- **Memory captures (operator workspace, not in repo):** `[[v8.4-yaml-poison]]` (the KP-1+KP-2 case study + first-line debug recipe) and `[[oc-agent-endpoint-builtin-null]]` (why `deploy.sh` § H2 warns every deploy on built-in OC agents, and the Approach-A filter-to-user-agents recipe saved as a signal for future regressions — NOT shipped per operator decision after the em-dash sweep eliminated the only known YAML poison in user-authored frontmatter).

### Why

The v8.4.0 fix addressed `agents/actor-heavy.md`'s specific YAML poison and added pre-deploy linting, but the toxic colon-space form survived elsewhere as a literal tag in agent dispatch instructions, planner schema, and docs. Future authoring of similar tag-like syntax (`[Researcher: deep]`, `[Reviewer: strict]`, etc.) would silently re-introduce the same class of bug. Em-dash convention plus a named "Known platform issues" section in `design.md` together eliminate both the immediate residue AND the recurrence vector. Historical porting docs (`docs/Opus-porting-plan.md`, `docs/Sonnet-porting-plan.md`, `docs/Glm--oc-non-A-porting.plan.md`, `docs/Kimi-oc-non-A-porting.plan.md`, `docs/Consolidated-migration-plan.md`, `docs/design-history.md`) are intentionally untouched — they document past plans accurately and should not be rewritten.

### Files changed

- `agents/planner.md`, `agents/actor-heavy.md`, `commands/brain.md`, `agents-md-block/orchestra-guard.md`, `README.md` (code commit `6fc8481`)
- `docs/design.md` (em-dash references updated; new § "Known platform issues" appended), `docs/Stage8.md`, `docs/Stage8--Changelog.md` (this entry)

---

## v8.4.0 — YAML poison + deploy.sh frontmatter lint + agent verify

**Shipped:** 2026-06-08
**Code commit:** `ad154045ce23a82de56268e19ef45e294cb1a0bc` (short: `ad15404`)

### What shipped

- **`agents/actor-heavy.md` line 3 — description value wrapped in double quotes and `[tier: heavy]` rephrased to `tier-heavy`:** Root cause: unquoted `[` at the start of a value triggers YAML flow-sequence parsing in both js-yaml (OpenCode) and PyYAML (Python tooling). OC silently nulls the affected fields (`model`, `description`, `tools`) when the parse fails. Fixed with double quotes around the entire value (outer quotes protect the content) and rephrased substring (removes latent poison even without quotes). Belt-and-suspenders approach ensures compatibility with both parsers.

- **`deploy.sh` § H1 — pre-deploy YAML frontmatter lint (new section 0b):** Iterates over `agents/*.md` files; extracts YAML frontmatter; uses PyYAML `safe_load` to parse; `die`s on parse exception or if any of `name`, `description`, `model`, `tools` fields are null. Runs unconditionally (including `--dry-run`); fails the deploy before any file is copied.

- **`deploy.sh` § H2 — post-restart `/agent` endpoint verification (new section 12):** After successful restart, polls `http://localhost:4096/agent` for up to 10 seconds to fetch the live agent inventory. For each agent, warns loudly (does not abort) if `model` or `description` is null. Skipped on `--no-restart`.

### Why

**OC main-vs-git_worktree platform note:** The latent YAML poison was tolerated in `project_directory.type='main'` (js-yaml's lax parsing accepted malformed flow-sequences) but fatal in `type='git_worktree'` (stricter YAML parsing). Trigger: on 2026-06-07 23:48:26 OC registered octmux's block-renderer worktree as `type='git_worktree'`. Subsequent actor-heavy dispatches in that worktree silently fell back to Brain's model because `description` and `model` nulled out. Latent for 19 days before becoming visible. The frontmatter lint and post-restart verification catch both the latent poison and any future parse failures, surfacing them at deploy time or immediately post-restart.

### Files changed

- `agents/actor-heavy.md`
- `deploy.sh`

---

## v8.3.1 — per-project `.brain-inflight` / `.duo-inflight` refusal check

**Shipped:** 2026-06-06
**Code commit:** `2045ab3bafe163ee6786cdf776b61ae76a2cf1cc` (short: `2045ab3`)

### What shipped

- **Per-project refusal check in `commands/brain.md`:** Inserted new refusal logic in Setup bash block (between lazy-cleanup close and session-ID creation). Iterates over active `.brain-inflight` markers via `find`, reads each candidate's `.project-dir` sidecar (written by Setup), normalises both paths with `realpath`, and compares project identity. Refuses with clear path if an active session is found in the same project. Missing `.project-dir` treated as unknown (skip, conservative default).

- **Per-project refusal check in `commands/duo-plan.md`:** Replaced previous global refusal block (lines 37-50) with per-project equivalent. Logic mirrors brain.md exactly, only differing in marker name (`.duo-inflight`) and suggested abandon command (`/duo-abandon` or `/duo-act`). Updated prose to emphasise "**for this project**" scope.

- **Path normalisation with `realpath`:** Both checks use `realpath` to normalise candidate and current project paths, handling symlinks and relative-path edge cases. Fallback `echo` provides safe identity if `realpath` fails.

- **`head -1` read of `.project-dir`:** Uses `head -1` to read the sidecar (written by Setup at line `printf '%s\n' ...`), avoiding `tr -d ' \n'` corruption for paths containing spaces. Planner R4 concern addressed.

### Why

Race 1 (Setup-time selection in `commands/brain.md:125-130`) can cascade into Race 2 (parent_delta cumulative subtraction in `scripts/telemetry-summarize.py:93`) when two same-mode pipelines run concurrently. Per-project scope (not global) respects the documented exclusivity intent without blocking legitimate cross-project work (e.g., orchestrating two separate project folders). /duo-plan's previous global behavior was over-restrictive — corrected symmetrically. Both checks now use the same `.project-dir` sidecar written at Setup time, creating a unified project-identity mechanism.

### Files changed

- `commands/brain.md`
- `commands/duo-plan.md`

---

## v8.3.0 — orchestra-cleanup.sh — safe-order + .cleanup-in-progress sidecar + trap

**Shipped:** 2026-06-05
**Code commit:** `f8bdd2dcb893765b6b801e0fd3d5ef7e9c48d75b` (short: `f8bdd2d`)

### What shipped

- **Corrected cleanup order:** `scripts/orchestra-cleanup.sh` now executes steps in correct order: `.outcome` write → `.parent-snapshot-end` capture → `.cleanup-in-progress` sidecar write (NEW) → `telemetry-summarize.sh` invocation → post-verify retry block → inflight marker removal (MOVED DOWN to last state-change op) → sidecar removal (NEW).

- **New `.cleanup-in-progress` sidecar:** Written atomically as `cleanup_pid=<$$>\ntimestamp=<ISO8601Z>` after parent-snapshot-end capture, before telemetry summarise. Marks cleanup as in-flight. Removed explicitly after inflight marker removal. Also protected by EXIT trap on script crash.

- **EXIT trap:** `trap 'rm -f "${CLEANUP_SIDECAR}"' EXIT` defined immediately after variable setup, before any state change. Ensures sidecar cleanup on abnormal exit (e.g. OC kill-9, SIGTERM during telemetry wait). Does not swallow exit code.

- **Moved `.cleanup-error` block:** Now written as part of the post-verify retry logic (step 5, unchanged semantically). Telemetry summarise happens before marker removal, fixing the HIGH#1 race condition where inflight marker was cleared before telemetry summarise began.

### Why

**HIGH#1 — marker-before-telemetry race:** Previous ordering cleared the inflight marker (step 3) before invoking telemetry-summarize.sh (step 4). Consequence: if telemetry-summarize.sh crashed or the daemon died in that window, the session was left with no marker AND no `telemetry.json`. The stop-hook orphan finalizer at `orchestra-hook.sh:241-251` would correctly reap this state — but only on the *next* OC Stop event. If the operator exited OC before that Stop fired, the telemetry record was permanently lost (until the 30-day reaper). By moving marker removal to step 6 (after post-verify), we keep the inflight marker present while telemetry-summarize.sh runs, so any crash mid-cleanup leaves the marker in place — the stop-hook then sees an in-progress marker and waits for the next attempt instead of reaping.

**MEDIUM#2 — no cleanup-in-progress sidecar:** Previous versions had no way to distinguish "cleanup did not run" from "cleanup ran and finished." The sidecar (.cleanup-in-progress) marks the middle ground: cleanup started, telemetry summarise in progress. This is a safety hook for future escalation (e.g. monitoring dashboards, manual intervention triggers) and enables the trap to clean up the sidecar on crash.

### Files changed

- `scripts/orchestra-cleanup.sh`

---

## v8.2.1 — orchestra-cleanup.sh — non-shortcuttable end-of-session cleanup

**Shipped:** 2026-06-05
**Code commit:** `fdbd2ebac25e30700f99b0e2b4e79e11f2621013` (short: `fdbd2eb`)

### What shipped

- **New script:** `scripts/orchestra-cleanup.sh` — single-entry shell script that owns the complete end-of-session cleanup sequence: `.outcome` (atomic write) → `.parent-snapshot-end` (oc-db.py snapshot with `{}` fallback) → inflight marker removal (badge-clear) → `telemetry-summarize.sh` → post-verify retry loop. Always exits 0 (best-effort; never blocks pipeline). Final stdout: `cleanup ok: outcome=<outcome> telemetry=<exists|MISSING>`.

- **Simplified command cleanup blocks:** `commands/brain.md`, `commands/brain-abandon.md`, `commands/duo-act.md`, `commands/duo-abandon.md` — each had a 30-line multi-step bash block replaced by a single `orchestra-cleanup.sh` call. The multi-step surface is gone; the LLM can no longer satisfy the visible state transition by running a subset.

- **Deploy wired:** `deploy.sh` script list extended with `orchestra-cleanup.sh` (auto chmod +x on deploy) and matching comment entry.

### Why

Brain (Opus 4.7) in session `20260605T133246Z-1909420` (v8.2.0) shortcut the cleanup block: ran 8 of 30 lines, clearing the badge but skipping `.parent-snapshot-end` capture and `telemetry-summarize.sh`. Result: `telemetry.json` absent, global `telemetry.jsonl` missing entry, A1-attribution snapshot pair gone. The multi-step inline block is the mechanism the model exploits — replacing it with a single opaque script call removes that surface. Investigated and planned in `~/Gin-AI/tmp/brain-telemetry-cleanup.md`.

### Files changed

- `scripts/orchestra-cleanup.sh` (new, +x)
- `commands/brain.md`
- `commands/brain-abandon.md`
- `commands/duo-act.md`
- `commands/duo-abandon.md`
- `deploy.sh`

---

## v8.2.0 — Researcher tier + Brain Phase 0 hardening + telemetry counter

**Shipped:** 2026-06-05
**Code commit:** `233c83b6b0ede8ee6d3258b19253d587cc802858` (short: `233c83b`)
**Doc commit:** (this commit — see git log after this changelog commits)

### What shipped

- **New subagents:** `agents/researcher.md` (`anthropic/claude-haiku-4-5`, Phase 0 verifier, read-only + Bash for probes) and `agents/researcher-deep.md` (`anthropic/claude-sonnet-4-6`, escalation tier for multi-file reasoning / subtle event interleaving / runtime probes). System prompts identical post-preamble (mirrors `actor`/`actor-heavy` convention). Hard rules: default UNCLEAR if not directly observed; every TRUE/FALSE cites `file:line`; no recommendations; no silent disambiguation; verbatim return structure `VERDICT:` / `EVIDENCE:` / `CAVEATS:`.

- **Hardened `commands/brain.md`:** new "Researcher dispatch" sub-section in Phase 0 with `Task`-tool template, escalation guidance, verdict synthesis (FALSE → re-think; UNCLEAR → escalate or accept with caveat; TRUE → record in RESEARCH.md), and soft verification budget (operator check-in after ~3 dispatch rounds). Updated RESEARCH.md template with `## Verified hypotheses` section. Updated Phase 0 end-gate (3 conditions; condition #1 requires hypotheses verified TRUE, accepted with caveat, or known FALSE with design adjusted). Added researcher-skip to negative-examples list (now first entry). Seven mechanical fixes to the operator's draft (typos, plural forms, fragment expansions, `--`→`---` frontmatter delimiter).

- **Telemetry counter:** `researcher_dispatches: int` field in `telemetry.json` (top-level), computed by `scripts/telemetry-summarize.py` as `sum(1 for s in subagents if s.get("agent") in ("researcher","researcher-deep"))`. Present in fallback `_zero_struct()` path too for schema consistency. Surfaced in `scripts/telemetry-report.sh` default view (`r=<N>` annotation when non-zero), `--tier` mode (researcher/researcher-deep rows ordered after Reviewer), and aggregate block (summed across the report window).

- **SSOT updates:** `config/orchestra-tiers.yaml` adds `researcher: { model: anthropic/claude-haiku-4-5 }` and `researcher-deep: { model: anthropic/claude-sonnet-4-6 }`. `scripts/check-tiers.py` extended with soft-warn for missing `anthropic/claude-haiku-4-5` mention in `commands/brain.md` first 20 lines. `config/context-windows.yaml` metadata refresh (`claude-haiku-4-5: 200000` was already present).

- **Deploy hardening:** `deploy.sh` orphan-cleanup block that deleted `~/.config/opencode/agent/researcher.md` on every deploy is removed (would have silently culled the new agent file). Variant-check pair list extended to `actor:actor-heavy, researcher:researcher-deep` so the deploy verifies researcher body parity.

- **Audit-surface refresh:** `AGENTS.md` (agent inventory + Phase 0 verification paragraph), `README.md` (Model tiers table extended with Researcher rows; subagent prose updated), `agents-md-block/orchestra-guard.md` (researcher-dispatch obligation bullet), `docs/design.md` (agent table + Phase 0 prose + cost model entries for researcher tiers; frontmatter metadata refresh), `docs/oconona--provider-contract-details.md` (added `researcher_dispatches` to telemetry.json schema; new `### New fields (v8.2.0)` sub-section). The deleted `docs/Stage7.5--implementation-details.md` (superseded by `oconona--provider-contract-details.md` in an earlier session) is committed in this changelog's accompanying doc commit.

### Why

Multiple sessions in the octmux project (v8.1.5.1 through v8.1.5.4) iterated against a wrong load-bearing assumption discovered three sessions later. Reactive cost — scaffold built, torn down, rebuilt — exceeded proactive cost of verification by an order of magnitude. Stage 8 is the structural fix: Phase 0 now expects load-bearing premises to be verified by dispatched researchers before any plan is drafted. See `docs/Stage8.md` § Motivation for the failure-mode analysis.

### Decisions confirmed (Phase 0)

| Topic | Decision | Rationale |
|---|---|---|
| Default researcher model | `anthropic/claude-haiku-4-5` | Calibrated UNCLEAR discipline; bounded per-call cost. |
| Escalation researcher model | `anthropic/claude-sonnet-4-6` | Operator override of the brief's `sohoai/glm-5.1`; harder hypotheses raise (not lower) the stakes for honesty about unknowns. |
| Naming | `-deep` (not `-heavy`) | Verification depth ≠ workload weight. |
| Verdict alphabet | TRUE / FALSE / UNCLEAR (no PARTIAL) | Binary discipline; UNCLEAR with caveats covers the partial case. |
| Verification budget | Soft check-in after ~3 dispatch rounds | No hard cap. |
| Project boundary | oconona only this session; claude-orchestra port deferred | Memo at `~/Gin-AI/tmp/CC--prudent.md`. |

### Out of scope (deliberately deferred)

- claude-orchestra port (captured as design memo at `~/Gin-AI/tmp/CC--prudent.md`; distinct future session).
- "False-premise catch rate" telemetry — qualitative for now; may be measurable after 5–10 sessions.
- Per-step verification annotation in `PLAN.md` (mirror of `[tier — heavy]`) — possible v8.3 extension.

### Verification

- `python scripts/check-tiers.py` → 0 hard-fails, soft-warns acceptable.
- Per-session procedure followed: code-first commit (`233c83b`) → doc commit (this changelog) → deploy → smoke `/duo-plan "noop"` → memory update.
- Both `agents/researcher.md` and `agents/researcher-deep.md` survive `./deploy.sh` (orphan-cleanup block was removed); both appear in `~/.config/opencode/agents/` post-deploy.

### Related references

- `docs/Stage8.md` — stage opening doc.
- `docs/Stage7--Changelog.md` — Stage 7 sealed at v8.1.6; forward pointer to Stage 8 added in this commit.
- `docs/oconona--provider-contract-details.md` — v8.2.0 telemetry schema additions.
- `~/Gin-AI/tmp/researcher-agents.md` — research brief that drafted the Researcher contract.
- `~/Gin-AI/tmp/brain-prudent.md` — operator's draft for `commands/brain.md` (consumed and preserved unchanged).
- `~/Gin-AI/tmp/CC--prudent.md` — design memo for the future claude-orchestra port.
