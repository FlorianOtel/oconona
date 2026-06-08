---
title: "Stage 8 — Prudent Brain: Researcher tier + Phase 0 hardening"
created_at: 2026-06-05--12-57
created_by: Actor (Claude Haiku 4.5 — via oconona /brain Stage 8 dispatch)
updated_by: Claude Opus 4.7 (1M context) — via oconona em-dash tier sweep (v8.4.1)
updated_at: 2026-06-08--09-00
context: >
  Stage 8 of the oconona orchestra introduces a new subagent role —
  Researcher — with two tiers (researcher / researcher-deep) dispatched
  by Brain during Phase 0 to verify load-bearing factual claims before
  any plan is drafted. Concurrently replaces commands/brain.md with a
  hardened version that integrates the researcher dispatch contract,
  verdict synthesis rules, escalation guidance, and a soft verification
  budget. The motivation is the v8.1.5.1-8.1.5.4 failure mode (Brain
  iterating four times against a wrong load-bearing assumption);
  Stage 8 is the structural fix.
---

# Stage 8 — Prudent Brain: Researcher tier + Phase 0 hardening

## One-line intent

`/brain` Phase 0 now dispatches `researcher` and `researcher-deep` subagents to verify load-bearing factual claims before any plan is drafted. Hypotheses are verified TRUE / FALSE / UNCLEAR with `file:line` evidence; Brain synthesises verdicts and updates RESEARCH.md before proceeding to Phase 1.

## Motivation — the failure mode being fixed

Multiple sessions in the octmux project (v8.1.5.1 through v8.1.5.4) consumed Brain cycles iterating on implementations built on a wrong load-bearing assumption discovered three sessions later. The reactive cost — scaffold built, scaffold torn down, scaffold rebuilt — exceeded the proactive cost of verification by an order of magnitude. The pattern repeated across distinct sessions because Brain's Phase 0 had no contract for *grounding facts before planning*.

Brain's job (interrogation, design synthesis, dispatch) remains unchanged. What changes is the assumption it operates under: Phase 0 is now expected to verify load-bearing premises via dispatched researchers, not to rely on Brain's own (or the operator's) recall.

## Decisions (confirmed during the Stage 8 opening /brain Phase 0)

| Topic | Decision | Rationale |
|---|---|---|
| Default researcher model | `anthropic/claude-haiku-4-5` | Calibrated UNCLEAR discipline (Haiku 4.5 is more willing to default to "I don't know" than equivalently-priced SoHoAI tiers); per-call cost bounded. |
| Escalation researcher model | `anthropic/claude-sonnet-4-6` | Hard hypotheses raise (not lower) the stakes for honesty about unknowns; rare dispatch. Operator override of the research brief's `sohoai/glm-5.1`. |
| Naming | `researcher-deep` (not `-heavy`) | "Deep" matches the differentiator (verification depth, not workload weight). |
| Verdict alphabet | TRUE / FALSE / UNCLEAR (no PARTIAL) | Binary discipline; UNCLEAR with caveats covers the partial case. |
| Verification budget | Soft check-in after ~3 dispatch rounds | Prevents unbounded interrogation without capping legitimate deep-dives. |
| Telemetry | `researcher_dispatches: int` field in `telemetry.json` | Measurable proof the design is firing; surfaced in `telemetry-report.sh`. |
| Project boundary | This Stage 8 ships oconona only; claude-orchestra port is deferred | The port is captured as a design memo at `~/Gin-AI/tmp/CC--prudent.md` (scratch, not committed). |

## Surface inventory

### New files
- `agents/researcher.md` — `anthropic/claude-haiku-4-5`, read-only-plus-Bash, system prompt enforces VERDICT/EVIDENCE/CAVEATS contract.
- `agents/researcher-deep.md` — `anthropic/claude-sonnet-4-6`, identical system prompt body to `researcher.md` (post-preamble, byte-identical per the actor/actor-heavy convention).
- `docs/Stage8.md` — this file.
- `docs/Stage8--Changelog.md` — first entry referencing the code-first commit hash.

### Modified files
- `commands/brain.md` — v8.3.1: inserted per-project `.brain-inflight` refusal check in Setup bash block (between lazy-cleanup close and session-ID creation); filters active sessions by `.project-dir` realpath comparison; absent `.project-dir` treated as unknown (skip); uses `head -1` to read sidecar (avoids `tr -d ' '` corruption for paths with spaces). Also: fully replaced from operator's `~/Gin-AI/tmp/brain-prudent.md` draft in v8.2.0; gaps closed (Researcher dispatch sub-section with Task-tool template, verdict synthesis, escalation guidance, soft verification budget; updated RESEARCH.md template with `## Verified hypotheses` section; updated Phase 0 end-gate; updated negative-examples list; 7 mechanical fixes).
- `commands/duo-plan.md` — v8.3.1: replaced global `.duo-inflight` refusal block with per-project filter matching brain.md; iterates over active markers, reads `.project-dir` sidecars, normalises paths with `realpath`, compares project identity. Updated prose to emphasise **"for this project"** scope. Cross-mode and cross-project coexistence now allowed.
- `scripts/orchestra-cleanup.sh` — v8.3.0: corrected execution order (sidecar write before telemetry summarise, marker removal after post-verify); added `.cleanup-in-progress` sidecar (atomic write/removal); added EXIT trap for crash cleanup. Fixes HIGH#1 (marker-before-telemetry race) + MEDIUM#2 (no cleanup-in-progress sidecar).
- `config/orchestra-tiers.yaml` — added `researcher` and `researcher-deep` tier entries.
- `config/context-windows.yaml` — metadata refresh; `claude-haiku-4-5: 200000` already present.
- `scripts/check-tiers.py` — soft-warn for missing `anthropic/claude-haiku-4-5` mention in `commands/brain.md`.
- `scripts/telemetry-summarize.py` — `researcher_dispatches` counter (filters `subagents` by `agent in ("researcher","researcher-deep")`); fallback path also returns 0 for schema consistency.
- `scripts/telemetry-report.sh` — surfaces counter in default view (`r=<N>` annotation when non-zero) + `--tier` mode + aggregate block.
- `deploy.sh` — removed the orphan-cleanup block that deleted `researcher.md`; extended variant-check pair list to `actor:actor-heavy, researcher:researcher-deep`.
- `AGENTS.md` — extended agent inventory; added Phase 0 verification paragraph.
- `README.md` — added Researcher and Researcher-deep rows to Model tiers table; extended subagent prose.
- `agents-md-block/orchestra-guard.md` — added researcher-dispatch obligation bullet.
- `docs/design.md` — extended agent table; updated Phase 0 prose; extended cost model with researcher tiers; frontmatter metadata refresh.
- `docs/oconona--provider-contract-details.md` — added `researcher_dispatches` to telemetry.json schema; added `### New fields (v8.2.0)` section.
- `agents/actor-heavy.md` — v8.4.0: description frontmatter value double-quoted; `[tier: heavy]` rephrased to `tier-heavy` to eliminate YAML flow-sequence parse error (js-yaml / PyYAML ScannerError) that OC silently swallows, nulling model + description + tools in git_worktree sessions. v8.4.1: tag re-normalised to canonical em-dash form `[tier — heavy]` (description and body); matches repo-wide convention.
- `deploy.sh` — v8.4.0: added H1 pre-deploy YAML frontmatter lint (section 0b) and H2 post-restart /agent endpoint verification (section 12).
- `agents/planner.md` — v8.4.1: tier-tag schema and example plan converted to em-dash form `[tier — fast|default|heavy]`; added one-line statement of WHY (em-dash separator is YAML-safe; forward-pointer to `docs/design.md` § "Known platform issues").
- `commands/brain.md` — v8.4.1: tier-aware dispatch instructions updated to `[tier — heavy]`; the legacy colon form `[tier: heavy]` is retained verbatim in one labelled historical example only.
- `agents-md-block/orchestra-guard.md` — v8.4.1: two `[tier: heavy]` references updated to `[tier — heavy]`.
- `README.md` — v8.4.1: model tiers table heavy-tier annotation updated to `[tier — heavy]`.
- `docs/design.md` — v8.4.1: model-assignments and step-level annotation sections updated to em-dash form; new § "Known platform issues" appended documenting KP-1 (silent agent-frontmatter parse failure / `model: null` fallback) and KP-2 (`main` vs `git_worktree` `project_directory` divergence).

### External (not committed)
- `~/Gin-AI/tmp/CC--prudent.md` — design memo for the future `claude-orchestra` port. Scratch file. Captures verbatim-carry plus OC ↔ CC surface adjustments.

## Phase 0 hardening — design specifics

(Cross-reference to `commands/brain.md` § Phase 0 § Researcher dispatch for the full operational contract.)

The Researcher subagent verifies one binary-answerable factual claim per dispatch. Output is structured: `VERDICT:` (TRUE | FALSE | UNCLEAR) + `EVIDENCE:` (file:line bullets) + `CAVEATS:` (bullets). The system prompt aggressively enforces: default to UNCLEAR if not directly observed; cite file:line for every TRUE/FALSE; no recommendations; no silent disambiguation.

Brain phrases the question, injects context (file paths, code excerpt, scope fence), dispatches via `Task` (`subagent_type: researcher` or `researcher-deep`), and synthesises the verdict. Multiple researchers in parallel for independent hypotheses. Soft check-in with operator after ~3 dispatch rounds.

The Phase 0 end gate now has 3 conditions (was 2). Phase 0 ends only when: (1) all load-bearing hypotheses are verified TRUE (with file:line evidence in RESEARCH.md § Verified hypotheses), explicitly accepted as TRUE-without-verification (with caveat), or known FALSE with the design adjusted; (2) the approach is well-formed (definition of done clear, scope fenced, alternatives considered); (3) the operator has signalled readiness.

## Telemetry — proving the design fires

`telemetry.json` gains a top-level field `researcher_dispatches: int`. Computed from the `subagents` list: `sum(1 for s in subagents if s.get("agent") in ("researcher","researcher-deep"))`. Present even in the fallback (no OC session ID) path with value 0. Surfaced in `telemetry-report.sh` default tabular view as `r=<N>` annotation when non-zero, in `--tier` mode as separate rows ordered after Reviewer, and in the aggregate block as a summed total across the report window.

This enables, after rollout, a measurable answer to "is Stage 8 firing as intended?" — track the per-session counter across 5-10 sessions, then assess whether dispatch frequency correlates with reduced multi-iteration failures.

## Open items deferred to future work

- "False-premise catch rate" metric — qualitative for now; may be measurable from session transcripts after a few weeks.
- Per-step verification annotation in `PLAN.md` (mirror of `[tier — heavy]`) so verifications can also fire between Plan and Act phases for newly-introduced premises — possible v8.3 extension.
- claude-orchestra port — captured as design memo at `~/Gin-AI/tmp/CC--prudent.md`; distinct future session.

## References

- `docs/Stage7.md` — closing context (Stage 7 sealed at v8.1.6; forward pointer to Stage 8 added in `docs/Stage7--Changelog.md`).
- `docs/Stage8--Changelog.md` — per-version changelog for Stage 8.
- `docs/design.md` — extended with Researcher tier in this session.
- `docs/oconona--provider-contract-details.md` — extended with v8.2.0 telemetry schema additions.
- `~/Gin-AI/tmp/researcher-agents.md` — research brief that drafted the Researcher contract (the brief's `sohoai/glm-5.1` for deep was overridden to `anthropic/claude-sonnet-4-6` by operator decision).
- `~/Gin-AI/tmp/brain-prudent.md` — operator's hardening draft for `commands/brain.md` (consumed into `commands/brain.md` with gaps closed; the draft file is preserved unchanged for forensics).
