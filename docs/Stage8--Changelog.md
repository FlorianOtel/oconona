---
title: "Stage 8 — Changelog"
created_at: 2026-06-05--13-00
created_by: Actor (Claude Haiku 4.5 — via oconona /brain Stage 8 dispatch)
updated_by: Claude Code (Claude Sonnet 4.6)
updated_at: 2026-06-05--16-38
context: >
  Per-version changelog for Stage 8 of the oconona orchestra
  (Researcher tier + Brain Phase 0 hardening + telemetry counter).
  Mirrors the Stage 7 changelog format. Each entry references the
  shipping commit hash and a short summary; deeper context lives in
  docs/Stage8.md.
---

# Stage 8 — Changelog

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
- Per-step verification annotation in `PLAN.md` (mirror of `[tier: heavy]`) — possible v8.3 extension.

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
