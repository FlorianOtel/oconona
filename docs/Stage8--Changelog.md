---
title: "Stage 8 — Changelog"
created_at: 2026-06-05--13-00
created_by: Actor (Claude Haiku 4.5 — via oconona /brain Stage 8 dispatch)
updated_by: Claude Code (Claude Opus 5) — v8.5.0 Actor remap + Check 4
updated_at: 2026-09-18--22-58
context: >
  Per-version changelog for Stage 8 of the oconona orchestra
  (Researcher tier + Brain Phase 0 hardening + telemetry counter).
  Mirrors the Stage 7 changelog format. Each entry references the
  shipping commit hash and a short summary; deeper context lives in
  docs/Stage8.md.
---

# Stage 8 — Changelog

## v8.5.0 — Actor tier remap to glm-5.3-flash; OC-availability audit gate; Anthropic rate corrections

**Commit:** `0beb378` (code), this changelog (docs)

### Change

`sohoai/qwen3-4b-q6` — the default Actor tier since v7.5.1 — was retired
upstream: removed from `~/.config/opencode/opencode.json` on 2026-09-17 and
from SoHoAI's llama-swap config on 2026-09-18. OpenCode hard-errors on an
unknown model key rather than falling back (`Provider.getModel` raises
`ProviderModelNotFoundError`; `SessionPrompt.getModel` publishes an error event
then dies with no model substitution), so the next Actor dispatch would have
failed outright. No Actor dispatch had occurred since the key vanished — the
last was 2026-09-14 — so no telemetry was misattributed and no historical data
needed repair.

- `config/orchestra-tiers.yaml`, `agents/actor.md` — `actor` tier →
  `sohoai/glm-5.3-flash`. Chosen over `sohoai/deepseek-v4.1-flash` because it
  is the only candidate with a configured fallback in SoHoAI's
  `router_settings.fallbacks` (→ `anthropic/claude-sonnet-5`), and because
  sharing a family with `actor-heavy` (`sohoai/glm-5.3`) makes the
  default→heavy escalation a predictable step rather than a model-family
  change. `sohoai/qwen3.5-9b-q4` was rejected: 8192 max output tokens, no
  fallback entry, and llama-swap records that configuration scoring 0/150 on
  AYA Gate G0.
- `scripts/model-rates.yaml`, `config/context-windows.yaml` — pruned seven
  retired SoHoAI keys (`qwen3-4b-q6`, `qwen3-9b-q4`, `glm-5.2`, `kimi-k2.7`,
  `qwen3-coder-next`, `deepseek-v4-flash`, `minimax-m2.5`); added
  `deepseek-v4.1-flash`, `glm-5.3-flash`, `qwen3.5-9b-q4`, `claude-haiku-4-5`
  and `kimi-k3` so both files mirror what OpenCode can actually dispatch.
  Departs from the glm-5.2-era convention of retaining superseded keys for
  historical telemetry: verification found exactly one session referencing any
  pruned key, and every runtime consumer degrades gracefully on an unknown ID
  (`ctx-segment.sh` falls back to the caller-supplied size; `oc-db.py` and
  `verify-cost-rates.py` return `None`/`WARN`; `session-report.py` reads
  `telemetry.json` only). Anthropic keys were NOT pruned —
  `context-windows.yaml` is also consumed Claude-Code-side.
- `scripts/model-rates.yaml` — `sohoai/kimi-k3` carries a warning comment: it
  returns HTTP 402 at Ollama Cloud until extra-usage billing is enabled and
  silently falls back to **paid** `anthropic/claude-sonnet-5`. Not to be
  assigned to a tier until resolved.
- `scripts/model-rates.yaml` — **rate corrections.** `anthropic/claude-sonnet-5`
  was carrying Sonnet 4.6's rate (3.00/15.00, cache_read 0.30, cache_write 5m
  3.75); corrected to 2.00/10.00, 0.20, 2.50. Sonnet 5 backs both Reviewer and
  Researcher-deep, so every cost report since v8.4.4 (2026-08-24) overstated
  the dominant Anthropic line item by 50%. Added `anthropic/claude-fable-5-1`
  at 10.00/50.00 with **cache_read 0.25** — Fable 5.1 caches at 2.5% of input,
  not the standard 10%, so copying Fable 5's block would have been 4x too high.
  Both verified against Anthropic's published pricing on 2026-09-18.
  `anthropic/claude-sonnet-4-6` deliberately left at 3.00/15.00 — that row is
  correct for Sonnet 4.6; the two rows were identical only because Sonnet 5's
  was wrong.
- `scripts/check-tiers.py` — **new hard-fail Check 4.** Every tier and
  recommendation model must exist under `provider.<name>.models` in
  `opencode.json`. Soft-warns (does not hard-fail) when that file is absent or
  unparseable, since it is outside oconona's ownership. Splits each model ID on
  the first `/` for all providers — `opencode.json` stores bare keys uniformly,
  unlike `context-windows.yaml`'s asymmetric convention, so Check 3's
  normalisation must NOT be reused here. Adds `--opencode-json PATH` to
  override the default location.
- `README.md`, `AGENTS.md`, `commands/brain.md`, `docs/design.md` — living-doc
  sync, including `commands/brain.md`'s stale advisory text (Opus 4.7 → Opus 5,
  GLM-5.2 → GLM-5.3). Historical records deliberately unchanged:
  `docs/design-history.md`, `docs/Stage7--Changelog.md`, the `--tier`
  sample-output block in `docs/design.md`, and the line-74 Reviewer-model
  history note.

### Rationale

Check 4 is the substantive addition. Before it, `check-tiers.py` verified only
that a tier's model appeared in two local YAML files — never that OpenCode could
dispatch it. That is why `./deploy.sh` passed green while the Actor tier pointed
at a model that no longer existed, and why the same class of breakage in v8.4.3
(`glm-5.2`) was also found by hand rather than by the audit. The gate now fails
the deploy instead.

A residual gap remains: Check 4 guards models a *tier* references. Model names
cited as illustrative examples in prose, comments and docstrings stay unguarded,
and that class produced five separate defects during this session's review
rounds — including one missed by a repo-wide sweep because it named
`qwen3-coder-next` rather than the model being retired. A doc-lint would close
it; not scheduled.

### Verification

`scripts/check-tiers.py`: 0 hard-fail(s), 0 soft-warn(s). Check 4's failure path
exercised against a tampered scratch copy of `opencode.json` (exit 1, correct
`[HARD-FAIL]` message), re-run independently by Brain. Post-deploy, the running
OpenCode server's `/agent` endpoint reports `actor → sohoai/glm-5.3-flash`.
Reviewer verdict: PASS.

Known, pre-existing and NOT introduced here: `scripts/smoke-test.sh` Check D
greps for `^  (OK|WARN|STALE):` but `verify-cost-rates.py` emits the verdict in
a pipe-separated third column, so the pattern never matches; under
`set -euo pipefail` this aborts the smoke run. Independent of this change.

---

## v8.4.4 — model sync: Reviewer/Researcher-deep → Sonnet 5, Brain/duo advisory → Opus 5/Sonnet 5

**Commit:** `52b6a23` (code), this changelog (docs)

### Change

Part of a cross-project session syncing Anthropic model references in
SoHoAI, claude-orchestra, and oconona to the current generation (Opus 5 /
Sonnet 5 / Fable 5 / Haiku 4.5). oconona had not been migrated — Reviewer and
Researcher-deep were still pinned to `anthropic/claude-sonnet-4-6` (from the
v7.3.5/v8.2.0 cutovers), and Brain/`/duo`'s advisory recommendations were
still `anthropic/claude-opus-4-7`/`anthropic/claude-sonnet-4-6`.
claude-orchestra's equivalent tiers had already been migrated in a prior
session (commit `625976f`).

- `agents/reviewer.md`, `agents/researcher-deep.md` — `model:` →
  `anthropic/claude-sonnet-5`.
- `agents/researcher.md`, `agents/researcher-deep.md` — escalation-pointer
  prose updated to reference `-sonnet-5`. Researcher's own model
  (`anthropic/claude-haiku-4-5`) is unchanged — no dated-snapshot ID is used
  anywhere in `opencode.json`, so the bare alias is already correct.
- `config/orchestra-tiers.yaml` — `reviewer`/`researcher-deep` tiers and the
  `brain`/`duo` advisory recommendations updated to Sonnet 5 / Opus 5.
- `config/context-windows.yaml`, `scripts/model-rates.yaml` — added
  `claude-opus-5` ($5/$25 per 1M tokens), `claude-sonnet-5` ($3/$15),
  `claude-fable-5` ($10/$50) rows; kept the superseded `claude-opus-4-7`/
  `claude-sonnet-4-6` rows (needed for historical telemetry lookups on past
  sessions, not deleted).
- `scripts/model-rates.yaml` — corrected `anthropic/claude-haiku-4-5` from a
  stale rate (0.80/4.00) to the current one (1.00/5.00), matching
  claude-orchestra's already-current `pricing.yaml` and confirmed current
  Anthropic pricing.
- `AGENTS.md`, `README.md`, `commands/brain.md`, `docs/design.md` — all
  live/current-state prose and tables updated (Opus 4.7 → Opus 5, Sonnet
  4.6 → Sonnet 5). Historical/closed docs (`docs/Stage7.md`, `docs/Stage8.md`,
  prior changelog entries, `docs/TODO.md`'s old illustrative pipeline
  diagram) deliberately left untouched — they're accurate records of what
  was true at the time, not live specs.

### Rationale

Operator-initiated cross-project audit session ("update-octmux-oconona-models")
to confirm all four related setups (SoHoAI, opencode.json, claude-orchestra,
oconona) track the latest Anthropic model generation. SoHoAI-config.yaml and
opencode.json were already current; claude-orchestra's agent frontmatter was
already current but its pricing/context-window tables and a few doc
mentions were missed in that migration (fixed in a companion commit in that
repo); oconona had not been touched at all.

### Out of scope

- `agents/planner.md`, `agents/actor.md`, `agents/actor-heavy.md` — these run
  on SoHoAI models (`sohoai/minimax-m3`, `sohoai/qwen3-4b-q6`,
  `sohoai/glm-5.2`), unaffected by the Anthropic model generation.
- `docs/TODO.md`'s pipeline flowchart — already stale in unrelated ways
  (references `sohoai/glm-5.1`/`sohoai/qwen3-coder-next`, neither matching
  current tier assignments); fixing only the Reviewer mention there would
  have been inconsistent partial editing of an already-outdated diagram.
- The hardcoded plaintext Anthropic API key found in
  `~/.config/opencode/opencode.json` during this session's survey — not
  committed to any git history (verified), but flagged to the operator as a
  cleartext-secrets hygiene item. Not part of this change.

### Verification

- `python scripts/check-tiers.py` → 0 hard-fails, 0 soft-warns.
- `grep -rn "claude-opus-4-7\|claude-sonnet-4-6" agents/ config/ scripts/
  AGENTS.md README.md commands/ docs/design.md` → only legacy rate/
  context-window table rows remain.
- Per-session procedure followed: code-first commit (`52b6a23`) → this doc
  commit → deploy → restart-timestamp verify → `/duo-plan "noop"` smoke test
  → memory update.

### Related references

- `~/Gin-AI/projects/claude-orchestra` commit `b0fd737` — companion fix in
  the sibling project (pricing.yaml, context-windows.yaml, CLAUDE.md,
  commands/brain.md, status-line/orchestra-block.sh).
- `docs/design.md` §"Reviewer is now Claude Sonnet" — updated in this
  commit to record the Sonnet 4.6 → Sonnet 5 move without rewriting the
  v7.3.5 historical rationale.

---

## v8.4.3 — brain: explicit operator gate before Planner dispatch

**Commit:** `45b0d74`

### Change

`commands/brain.md` § "What to do when ending (proceed branch)" — the single
sentence "Then proceed to Phase 1" is replaced with a three-step pause block:

1. After writing RESEARCH.md, Brain prints a compact summary (goal, approach,
   scope, open questions) to the operator.
2. Brain asks explicitly: *"Ready to dispatch Planner? Add any constraints for
   the planning phase, or just say 'go'."*
3. Brain stops and waits. Planner is not dispatched until the operator
   responds with an affirmative ("go", "proceed", "yes", "dispatch", etc.)

The operator's Phase 0 "proceed" signal previously served double duty: it ended
interrogation **and** triggered Planner dispatch. This decouples those two
moments, giving the operator a review beat and a chance to inject planning
constraints before the Planner subagent is invoked.

### Unchanged

Phase 0 end-conditions, Phase 1 Planner Task template, PLAN.md persistence,
plan approval gate (line 385), Phase 2 Actor dispatch, all other commands.

### Rationale

Operator feedback: Planner was silently dispatched as a side-effect of the
Phase 0 go-ahead. The intent was to require an *additional* explicit gate
specifically for planning authorisation.

### Out of scope

`/duo-plan` (no Planner dispatch in duo), `reviewer.md`, `actor.md`,
`actor-heavy.md` — all unchanged.

### Verification

1. `./deploy.sh` (no restart requested this session — verify manually).
2. `/brain` → complete Phase 0 → say "proceed".
3. Confirm Brain pauses at RESEARCH.md summary, does NOT fire Planner Task tool.
4. Reply "go" → confirm Planner dispatched, Phase 1 proceeds normally.

### Per-session procedure

Code-first commit (`45b0d74`) → this doc commit → deploy (no restart) → smoke deferred.

---

## v8.4.2.2 — deploy.sh — status-line warn → info

**Shipped:** 2026-06-10
**Code commit:** `a88ddda` (short: `a88ddda`)

### What shipped

- **`deploy.sh` § 8 — downgrade missing-status-line from `warn` to `info`:** `status-line.sh` is absent on this machine; OC renders the status line without it, so the orchestra-block patch is not needed. The previous `warn` (yellow `!`) implied something was broken on every deploy. Changed to `info` (cyan `•`) so the message is purely informational.

### Why

`status-line.sh` is an OC-generated file on some installations but absent on others. The orchestra-block patch is optional enhancement (injects ctx bar + cost + badge into the status line); when the file doesn't exist the status line still works. A `warn` on every deploy produced false noise that obscured real issues.

### Files changed

- `deploy.sh` (code commit `a88ddda`)

---

## v8.4.2.1 — deploy.sh § 12 — filter built-in agents, fix model isinstance check

**Shipped:** 2026-06-10
**Code commit:** `dd351c172b68fc4e0bd01ad48e22e7f0519e8b76` (short: `dd351c1`)

### What shipped

- **`deploy.sh` § 12 (H2) — filter `/agent` response to user-defined agents only:** The OC `/agent` endpoint returns all 13 registered agents: 6 user-defined (`actor`, `actor-heavy`, `planner`, `researcher`, `researcher-deep`, `reviewer`) plus 7 OC built-ins (`build`, `compaction`, `explore`, `general`, `plan`, `summary`, `title`). Built-ins have `model=null` and some have empty `description` by OC design. The prior verification iterated all entries; the first agent in the list (`build`, `model=null`) tripped the `not model` check immediately on every attempt, causing a false warn on every successful deploy.

- **Fix 1 — derive expected name set from `agents/*.md`:** `_EXPECTED_NAMES` is built by iterating `$REPO/agents/*.md` and stripping `.md` suffixes. Python filters the `/agent` response to those names, ignoring all built-ins. The set is self-maintaining — adding a new agent file automatically includes it in verification.

- **Fix 2 — replace `isinstance(model, str)` with truthy check:** User-defined agents carry `model` as a JSON object `{modelID, providerID}`, not a string. The prior `isinstance(model, str)` check would reject every valid user agent even if built-ins were filtered out. The new check uses `not a.get('model')` (falsy/null detection only).

- **Updated warn message** to point at `curl http://localhost:4096/agent | jq` for diagnostics instead of mentioning `actor-heavy` specifically.

### Why

False warn on every deploy produced noise that obscured real failures. The prior design (v8.4.0 H2) was documented as "cosmetic noise — revisit if a real regression resurfaces" (see `oc-agent-endpoint-builtin-null` memory). The v8.4.2 SNAPEOF deploy triggered the question, making this the right moment to apply the already-designed fix.

### Files changed

- `deploy.sh` (code commit `dd351c1`)

---

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
