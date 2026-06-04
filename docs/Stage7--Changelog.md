---
title: "Stage 7 Changelog — oconona"
created_at: 2026-05-28--18-16
created_by: Actor (Claude Haiku 4.5)
updated_by: Claude Code (Claude Opus 4.7 — 1M context)
updated_at: 2026-06-04--21-22
context: >
  Reverse-chronological implementation log for Stage 7 OC-native telemetry
  redesign. Carries forward Stage 6 entries with status annotations. Newest
  entries at top.
---

# Stage 7 Changelog

Entries are reverse-chronological. Newest at the top.

---

## 2026-06-04--21-21 — v8.1.4 /brain model-advisory live source

**Implemented by:** Claude Code (Claude Opus 4.7 — 1M context) — 2026-06-04--21-21
**Commit(s):** `a4e63d4`

`/brain` Prerequisites #1 (model-recommendation advisory) was reading the model id from Brain's system context — specifically the `The exact model ID is …` line OpenCode injects at session-prompt assembly time. That line is a **snapshot**, not a live value: OC's `/model` slash command re-routes subsequent API calls but does **not** re-render the system prompt, so after a mid-session model swap the advisory reported the model active at session creation, not the current routing. Reported live by operator in octmux session `ses_16bf7d846ffe7zFzlCAPjnpqxd`: `/model claude-sonnet-4-6` → `/model claude-opus-4-7` → `/brain` falsely warned "you are on claude-sonnet-4-6" while OC was correctly routing to Opus 4.7.

Fix: Setup Bash now pulls `.model.providerID` + `.model.id` from the same `/session` query that already resolves `.oc-session-id`, and writes `<providerID>/<model.id>` to `${SESSION_DIR}/.oc-current-model`. Prerequisites #1 reads that file and decides on the live value. Empty file (HTTP unreachable) falls back to the legacy system-context read so the check is never silently dropped. Decision logic now matches `providerID == "anthropic"` + `model.id` starts with `claude-opus-4-7` (clearer than the prior raw-string match) and emits the advisory with the real `<provider>/<model>` substituted for `[MODEL-ID]`. Advisory remains advisory-only — wording, posture, and "operator's choice is final" rationale unchanged.

Scope: single-file source change (`commands/brain.md`). `/duo-plan`, `/duo-act`, `/duo-abandon`, `/brain-abandon` carry no equivalent check (grep-verified). Cross-project authorisation: operator-approved one-time exception (reported from octmux, fixed in oconona).

---

## 2026-06-04--17-15 — v8.1.3 revert v8.1.2 subagents.jsonl sidecar

**Implemented by:** Claude Code (Claude Opus 4.7 — 1M context) — 2026-06-04--17-15
**Commit(s):** `3b4511c`

Upstream OpenCode fix (fork `FlorianOtel/opencode` commit `98a4907c9`) restores OC-native `agent`/`model` column population on Task-tool child sessions, so the v8.1.2 oconona sidecar layer is no longer needed. Reverted: four `subagents.jsonl` write blocks in `commands/brain.md` (Planner / Actor / Actor-heavy / Reviewer phases) and the two sidecar-merge blocks in `scripts/telemetry-summarize.py`. Kept (unrelated correctness): `scripts/oc-db.py` line 378 default `or ""` (still distinguishes NULL DB column from a real "brain" agent). Verified before commit: deployed daemon `0.0.0-dev-202606041432` populates `agent`/`model` natively on post-deploy child sessions in `opencode.db`. **If the daemon is ever rebuilt from canonical `sst/opencode` without the upstream fix, attribution will return to NULL — see the v8.1.2 entry for the workaround pattern**, which can be restored from git history at this commit.

---

## 2026-06-04--10-04 — v8.1.2 attribution fixes

**Implemented by:** Actor (Claude Haiku 4.5) via /brain pipeline — 2026-06-04--10-04
**Commit(s):** `382dd4f`

Summary: misleading `agent: "brain"` default removed from oc-db.py (NULL agent column now surfaces as `""`); attribution fix (Branch B — sidecar fallback) implemented. Cross-project: fix triggered from octmux Stage 8.1.2 telemetry investigation (ref `c73e354`).

---

## 2026-06-03 — v7.5.1: SoHoAI tier-model remap (Planner→minimax-m3, Actor→qwen3-4b-q6, Actor-heavy→glm-5.1)

**Commit:** `4184f4b` (full: `4184f4b329d25f49dc8baabc3be5df94d3657dab`)

### Delivered

- **Tier-to-model remap:** All three SoHoAI worker tiers remapped per operator-directed SoHoAI model rebalance (session 20260603T213230Z-814278):
  - Planner: `sohoai/glm-5.1` → `sohoai/minimax-m3`
  - Actor: `sohoai/qwen3-coder-next` → `sohoai/qwen3-4b-q6`
  - Actor-Heavy: `sohoai/kimi-k2.6` → `sohoai/glm-5.1`
- **Configuration SSOT updates:** `config/orchestra-tiers.yaml` (tiers block), `scripts/model-rates.yaml` (new `sohoai/minimax-m3` entry, 0-cost flat-rate), `config/context-windows.yaml` (new `sohoai/minimax-m3: 1000000` entry).
- **Agent frontmatter updates:** `agents/planner.md`, `agents/actor.md`, `agents/actor-heavy.md` (model field + description/role prose).
- **User-facing documentation sync:** `README.md` (tier-model table), `AGENTS.md` (file tree + example command), `commands/brain.md` (prose mentions), `docs/design.md` (live-state lines 34, 71–74, 277–278, 310, 324, 371, 433–435, 451; frozen-in-time blocks left as-is per audit convention).
- **Pre-deploy verification:** `scripts/check-tiers.py` audit passes cleanly (0 hard-fails, 0 soft-warns).

### Scope notes

- Configuration-only change: no new mechanism, no telemetry shape change, no audit script updates.
- Frozen-in-time blocks in `docs/design.md` (lines 379, 385–398, 457) preserved as historical record.
- No changes to Brain (Opus 4.7), Reviewer (Sonnet 4.6), or `/duo` recommendation.

### Verification

- `check-tiers.py`: 0 hard-fail(s), 0 soft-warn(s) ✓
- Post-deploy systemd restart confirmed (see `ActiveEnterTimestamp ≥ deployed-file-mtimes`).
- Smoke-test expected to pass: `/duo-plan "noop"` should show `cost_source: oc_sqlite` and valid telemetry.

---

## 2026-06-03 — v7.5: per-OC-session-segment attribution + hierarchical badge + harness contract doc

**Commit:** `eb540aa` (full: `eb540aa...`)

### Delivered

- **Snapshot sidecars (v7.5 attribution mechanism):** `.parent-snapshot-start` (setup) + `.parent-snapshot-end` (every cleanup path: brain.md, duo-act.md, duo-abandon.md, brain-abandon.md, orchestra-hook.sh stop mode). Captures OC parent cumulative cost/tokens at session start and cleanup time. Atomic writes. Enables per-segment attribution via delta (end - start).
- **`scripts/oc-db.py` enhancements:** New public functions `get_session_snapshot()` (lightweight point-in-time snapshot; six fields: cost, tokens_*) and `get_child_sessions_in_window()` (time-window filter for child sessions, with -1000 ms tolerance for s/ms precision skew).
- **`scripts/telemetry-summarize.py` rewrite:** Segment-attribution path. Reads `.parent-snapshot-start` and `.parent-snapshot-end`; computes `parent_delta = end - start` (floored at 0); filters children by time window if both snapshots present; falls back to whole-parent cumulative if snapshots are missing (`{}` sentinel). New top-level `telemetry.json` fields: `parent_delta`, `parent_total`, `started_at_oc_ms`, `ended_at_oc_ms`, `parent_snapshot_start`, `parent_snapshot_end`, `parser_warnings` (list of `{code, message}` dicts; includes `snapshot_missing` warning when sidecars are absent/invalid). Semantic change: `parent.cost` and `parent.tokens_*` now hold **segment-delta values** (was cumulative pre-v7.5); `parent_total` carries the cumulative parent row for forensics. `cost_usd_estimate = parent_delta.cost + sum(child costs)`.
- **`status-line/orchestra-block.sh` symmetric badge.** New format: `♪ orchestra -> <title> -> <mode> [-> <subagent>]`. Mode segment always present (symmetry: both brain and duo include it). Old `▶ stage` indicator merged into the chain as `-> <subagent>` (role from `invocations.log` `subagent` field, canonical values: planner, actor, actor-heavy, reviewer). Removed: `ACTIVE_COLOR` variable, stage label display logic. Updated active-subagent extraction to use `subagent` field (not deprecated `stage`).
- **`scripts/session-report.py` enhancements:** `--hybrid-detail` flag (or integrated into `--hybrid-detail`) surfaces `parent_delta.cost`, `parent_total.cost`, and `parser_warnings`. Backward-compat: gracefully handles pre-v7.5 telemetry.json (missing new fields default to 0 / `[]`).
- **`scripts/telemetry-report.sh --tier` latent bug fix:** Was referencing non-existent nested `t["parent"]["tokens"]` sub-dict; now correctly reads flat `tokens_input`, `tokens_output`, `tokens_cache_read`, `tokens_cache_write` fields. Bundled with v7.5 shape update.
- **`scripts/smoke-test.sh` Check E:** Verifies `.parent-snapshot-start` and `.parent-snapshot-end` exist in session_dir, both parse as valid JSON, both contain `cost` field (or `{}` fallback). Sanity: if both non-empty, `snap_end.cost >= snap_start.cost`. Pre-v7.5 sessions skipped (⊘ output). Banner updated from `(v7.3.5+)` to `(v7.5+)`. `TOTAL_CHECKS=5`.
- **NEW `docs/Stage7.5--implementation-details.md`.** 14-section authoritative reference for OC harness consumers (octmux + future TUIs). Documents logical-part markers (`.brain-inflight` / `.duo-inflight`), per-session sidecar files (`.oc-session-id`, `.project-dir` [deprecated], `.parent-snapshot-start`, `.parent-snapshot-end`, `.outcome`, `.last-logfile`, `.transcript-uuid`, `state.env`), `invocations.log` schema + consumer recipe, `telemetry.json` v7.5 shape (full schema, new fields, semantic changes, fallback behaviour), sidecar match key (`.oc-session-id` authoritative; `.project-dir` deprecated), symmetric badge format spec (four canonical states), what each consumer reads (standalone orchestra-block.sh vs harness renderer), write-order invariants (7 items including v7.5 additions), atomic-rename pattern, crash-recovery behaviour, deprecation notices (`.project-dir` discovery, `ORCHESTRA_MODE` prefix matching, Z2c, C-γ, `stage` field), harness implementation checklist (step-by-step recipe), cross-references. Supersedes octmux Stage8.md §C-α contract and §Stage indicator. Companion to code commit eb540aa.

### Scope notes

- This release is the **v7.5 formal delivery**: per-segment cost/tokens attribution, hierarchical badge, harness contract.
- **Octmux refactor deferred to separate /brain cycle (unnumbered).** A future octmux-repo `/brain` session will consume `docs/Stage7.5--implementation-details.md` and revise/replace/refactor octmux's stale `docs/Stage8.md`. No octmux files touched in this `/brain`.

### Verification

- Deploy verified (ActiveEnterTimestamp ≥ deployed-file mtimes).
- Smoke-test 5/5 PASS.
- `/duo-plan` + `/duo-act` smoke shows segment-correct `telemetry.json` with new fields (`parent_delta`, `parent_total`, `started_at_oc_ms`, `ended_at_oc_ms`, `parent_snapshot_*`, `parser_warnings`).
- Badge renders symmetric format during `/duo-plan` (`♪ orchestra -> noop -> duo`) and Actor dispatch (`♪ orchestra -> noop -> duo -> actor`).

---

## 2026-06-03 — v7.5beta: SSOT tier config + audit script + arch sweep

**Commit:** `4c1e292` (full: `4c1e2923743fa1f190680ffb58066922239abfa6`)

### Delivered

- **New `config/orchestra-tiers.yaml`** — declarative tier→model SSOT for planner / actor / actor-heavy / reviewer + recommendations for brain / duo.
- **New `scripts/check-tiers.py`** — deploy-time audit:
  - Hard-fail on drift in `agents/*.md` frontmatter, `scripts/model-rates.yaml`, `config/context-windows.yaml`.
  - Soft-warn on drift in `README.md`, `AGENTS.md`, `commands/brain.md`, `docs/design.md`.
  - Self-verifies green at land: 25/25 [OK], 0 fails, 0 warns.
- **`deploy.sh`** — new section 0 (Tier-config audit) runs `check-tiers.py` before any file operations; refuses to deploy on hard-fail. Dead `.opencode/orchestra/` gitignore block (section 10) replaced with a removed-comment marker.
- **`scripts/session-report.py`** — legacy fallback path-inference block (10 lines) removed; docstring updated to reflect the global SESSIONS_ROOT.
- **`docs/design.md`** — first paragraph rewritten to strip all literal model strings (now references the SSOT yaml); line-83 paragraph corrected so Reviewer is no longer claimed as "non-Anthropic"; tier table annotated as a summary of the SSOT.
- **`AGENTS.md`** — SSOT pointer bullet added under the layout section; Brain model id (`anthropic/claude-opus-4-7`) inlined in the recommendation paragraph.
- **`README.md`** — SSOT pointer blockquote added under the model-tiers table; line-88 stale gitignore narrative replaced.

### Scope notes

- This release is the SSOT *mechanism*, not new model assignments. The yaml mirrors current state byte-for-byte; no tier model changes.
- Generated agent frontmatter (Alt B) — deferred.
- Archival porting plans — left as historical record.
- Octmux integration (originally slotted for v7.5) — deferred to a separate /brain cycle (unnumbered).

### Out of scope (flagged for future)

- `/duo-abandon` status-line badge persistence — separate.
- Adding `config/orchestra-tiers.yaml` to `collect.sh` — separate.

---

## 2026-06-02 — v7.3.5 hotfix #3: /duo-plan sessions root unified to GLOBAL path

**Commit:** `a0d5151`

### Delivered

- **commands/duo-plan.md line 69:** `SESSIONS_ROOT="${OPENCODE_PROJECT_DIR}/.opencode/orchestra/sessions"` → `SESSIONS_ROOT="${HOME}/.config/opencode/orchestra/sessions"`. Load-bearing fix. Brings `/duo-plan` Setup block in line with the refusal-check block (already global, lines 38-50), `commands/brain.md`, `commands/duo-abandon.md`, and the deployed orchestra-guard.
- **commands/brain.md line 25 (prose):** `${OPENCODE_PROJECT_DIR}/.opencode/orchestra/sessions/*/` → `${HOME}/.config/opencode/orchestra/sessions/*/`. Hygiene-only; brain.md's actual session creation at line 68 was already on the global path.

### Scope

Two-file edit. No runtime logic changed beyond the sessions-root path. No other commands, scripts, docs, or config files touched. Migration leftovers in `scripts/session-report.py` (docstring + "Legacy fallback" path-inference, still working via telemetry.json primary read), `deploy.sh` (gitignore entry `.opencode/orchestra/`), and `README.md` (obsolete project-local narrative) are back-compat/cosmetic only and deliberately left for a future "v7.5 architecture sweep".

### Verification

```bash
# 1. Deployed duo-plan.md Setup block uses global path
grep 'SESSIONS_ROOT' ~/.config/opencode/commands/duo-plan.md
# expected: two lines, both ${HOME}/.config/opencode/orchestra/sessions

# 2. No project-local path remains
grep 'OPENCODE_PROJECT_DIR.*opencode/orchestra' ~/.config/opencode/commands/duo-plan.md ~/.config/opencode/commands/brain.md
# expected: no output

# 3. Smoke: /duo-plan "noop" then /duo-abandon
#    - new session at ~/.config/opencode/orchestra/sessions/<timestamp>/ (GLOBAL)
#    - NOT at ${OPENCODE_PROJECT_DIR}/.opencode/orchestra/sessions/
#    - /duo-abandon finds and removes the session cleanly
```

### Why

The hotfix #2 smoke session (`20260602T192923Z-368859`, left orphaned in the octmux project tree) surfaced the mismatch: `/duo-plan` created the session at `${OPENCODE_PROJECT_DIR}/.opencode/orchestra/sessions/…` while `/duo-abandon` looked in `${HOME}/.config/opencode/orchestra/sessions/…` — producing "No active /duo session to abandon — nothing to clean up". The deployed orchestra-guard block in `~/.config/opencode/AGENTS.md` (which checks `${HOME}/.config/opencode/orchestra/sessions/*/.brain-inflight` etc. each turn) and the status-line badge renderer (`status-line/orchestra-block.sh:49`) also look at the global path. Migration origin: commit `64f163b` (2026-05-20) set everything project-local; later commits moved most paths global; duo-plan.md line 69 and brain.md line 25 were missed. This hotfix completes the migration for the load-bearing references; the back-compat leftovers stay for a future v7.5 sweep.

---

## 2026-06-02 — v7.3.5 hotfix #2: Reviewer/Brain/duo model documentation sweep

**Commit:** `02d727e`

### Delivered

- **commands/brain.md:** Line 13 `Reviewer (sohoai/kimi-k2.6)` → `Reviewer (anthropic/claude-sonnet-4-6)`. Actor-Heavy parenthetical preserved (still uses `sohoai/kimi-k2.6`).
- **README.md:** Reviewer model-tiers table row updated to `anthropic/claude-sonnet-4-6`.
- **docs/TODO.md:** Flow diagram line 144 Reviewer model updated; frontmatter refreshed.
- **docs/design.md:** `/duo` advisory updated from `sohoai/kimi-k2.6` to `anthropic/claude-sonnet-4-6` at lines 52, 79, 428. Pre-v7.3.5 example-output blocks annotated as historical (Q1b — authentic numbers preserved, blockquote prepended noting model assignments at the time vs. current v7.3.5+ assignments). Frontmatter refreshed. Also picks up prior-session uncommitted v7.4 / hotfix #1 carry-forward in this file (per operator Q4).
- **AGENTS.md:** Section `## Brain model` renamed `## Brain and /duo model recommendations`; single advisory paragraph split into two — `/brain` recommends Opus 4.7, `/duo` recommends `anthropic/claude-sonnet-4-6` (v7.3.5+, advisory only).

### Scope

Prose-only sweep. No runtime code changed. Source of truth (`agents/reviewer.md`) was already correct at `anthropic/claude-sonnet-4-6` since v7.3.5.

### Verification

```bash
grep 'Reviewer' commands/brain.md | grep -v 'kimi-k2.6'
grep 'Reviewer' README.md | grep -v 'kimi-k2.6'
grep 'Phase 3' docs/TODO.md | grep -v 'kimi-k2.6'
grep '/duo' docs/design.md | grep -i 'anthropic/claude-sonnet-4-6'
grep 'anthropic/claude-sonnet-4-6' AGENTS.md | grep -i duo
```

### Why

The octmux smoke session `20260602T093049Z-215608` surfaced a discrepancy: Reviewer subagent self-reported `anthropic/claude-sonnet-4-6` (correct, per `agents/reviewer.md`), but the deployed `commands/brain.md` still read `Reviewer (sohoai/kimi-k2.6)`. The octmux Brain consulted that deployed doc to set its `expected_model`, producing a `reviewer-noop.txt` that recorded `expected_model: sohoai/kimi-k2.6` even though the actual Reviewer ran on `anthropic/claude-sonnet-4-6`. This hotfix aligns all documentation with the v7.3.5 source of truth and additionally unifies the `/duo` model advisory recommendation to `anthropic/claude-sonnet-4-6` per operator directive (Q2a).

---

## 2026-06-02 — v7.3.5 hotfix #1: /session header missing in .oc-session-id capture

**Commit:** `4293ff8`

### Delivered

- **Header fix (brain.md):** Added `-H "x-opencode-directory: ${_OC_DIR}"` to the `/session` curl in `commands/brain.md` (line 115). Without this header the OC `/session` endpoint silently returns `[]`; the jq filter over an empty array yields `""`; the `.oc-session-id` sidecar is written empty; `telemetry-summarize.py` falls through to all-zeros output.
- **Header fix (duo-plan.md):** Identical fix applied to `commands/duo-plan.md` (line 110). Same bug, same causal chain.
- **Smoke check (S3):** Added `[ -z "$_OC_SESSION_ID" ] && echo "WARN: …" >&2` immediately after the sidecar write in both files. Surfaces an empty result in the operator's terminal instead of silent zero-cost telemetry hours later.

Root cause documented in cross-repo investigation report:
`../octmux/docs/cost-telemetry-investigation.md`

### Verification

```bash
# 1. Header present in deployed brain.md
grep 'x-opencode-directory' ~/.config/opencode/commands/brain.md

# 2. Header present in deployed duo-plan.md
grep 'x-opencode-directory' ~/.config/opencode/commands/duo-plan.md

# 3. Smoke check line present in both
grep 'WARN: telemetry-summarize' ~/.config/opencode/commands/brain.md
grep 'WARN: telemetry-summarize' ~/.config/opencode/commands/duo-plan.md

# 4. After a /duo-plan "noop" round-trip:
#    .oc-session-id is non-empty
cat ~/.config/opencode/orchestra/sessions/<latest>/.oc-session-id

#    telemetry.json shows oc_sqlite source and non-zero cost
jq '.cost_source,.cost_usd_estimate' ~/.config/opencode/orchestra/sessions/<latest>/telemetry.json
# expected: "oc_sqlite"
# expected: <number > 0>
```

---

## 2026-05-31 — v7.4: oconona-config.yaml rename + dead-key purge + CC-ism sweep + parked-file deletion

**Commit:** `f4e06f1`

### Delivered

- **Config rename:** `config/config.yaml` → `config/oconona-config.yaml` (git rename, records history).
- **Dead-key purge:** Strip `orchestra_mode`, `gates`, `approval_method`, `review_loop_max`, `commit`, `crosscheck_loop_max`, `token_budget_usd`, `commit_auto`, `test_gate`, `sohoai` blocks — keep only header + `housekeeping:` block.
- **CC-ism sweep:** Replace all `ExitPlanMode`, `exit_plan_mode`, `bypassPermissions`, `Shift+Tab`, `plan-mode`, `claude-code-*` references in non-historical files with OC-native equivalents.
- **Parked-file deletion:** `to-be-reviewed--AGENTS.md` removed from repo.

### Verification

```bash
# A. Config rename + content
cat config/oconona-config.yaml
! grep -E 'orchestra_mode|gates:|approval_method|sohoai:|ExitPlanMode|exit_plan_mode' config/oconona-config.yaml
test ! -e config/config.yaml

# B. No stale 'config.yaml' references in live files (only 'oconona-config.yaml' should appear)
grep -rn 'config\.yaml' --include='*.md' --include='*.sh' --include='*.py' --include='*.yaml' . \
  | grep -v 'docs/design-history\|docs/Sonnet\|docs/Opus\|docs/Kimi\|docs/Glm\|docs/Consolidated\|docs/architecture\|docs/pre-Stage7\|^\.git/\|^\.claude/' \
  | grep -v 'oconona-config\.yaml'

# C. No CC-isms in live files
grep -rnE 'ExitPlanMode|exit_plan_mode|bypassPermissions|--dangerously|Shift\+Tab|plan.mode|claude-code-' \
  --include='*.md' --include='*.sh' --include='*.py' --include='*.yaml' . \
  | grep -v 'docs/design-history\|docs/Sonnet\|docs/Opus\|docs/Kimi\|docs/Glm\|docs/Consolidated\|docs/architecture\|docs/pre-Stage7\|^\.git/\|^\.claude/\|docs/Stage7--Changelog\|docs/Stage7\.md'

# D. Parked file gone
test ! -e to-be-reviewed--AGENTS.md

# E. Syntax checks
bash -n deploy.sh
bash -n collect.sh
bash -n status-line/orchestra-block.sh
python3 -c "import ast; ast.parse(open('utils/snapshot_codebase.py').read())"

# F. Stage7 docs updated
grep -E '^\| \*\*v7\.4\*\' docs/Stage7.md
head -25 docs/Stage7--Changelog.md | grep -E '^## 2026-05-31 — v7.4'
```

---

## 2026-05-31 — v7.3.5: Token accounting for hybrid orchestra
**Commit:** `ba998ee`

### Delivered

- **Reviewer revert to Anthropic**: `agents/reviewer.md` model field restored from `sohoai/kimi-k2.6` to `anthropic/claude-sonnet-4-6`, enabling measurable per-tier costs for marginal-attribution calculation.
- **`scripts/model-rates.yaml`**: central source of truth for model costs. Provider-qualified keys (`"anthropic/claude-opus-4-7"`, etc.). Cache write costs are TTL-keyed sub-maps; default TTL is `5m` (future: switch to `1h` via config edit). Anthropic rates derived from public pricing (2026-05-31). SoHoAI: free-tier ($0).
- **`_parse_model_full()` + `_load_model_rates()` + `_get_rate()` in `oc-db.py`**: new helpers for rate lookup and model normalization. `_parse_model_full()` extracts provider-qualified key from OC's model JSON; defensive fallback for missing providerID. `_get_rate()` resolves TTL-keyed cache_write with fallback to default_cache_ttl.
- **`_compute_hybrid_attribution()` in `oc-db.py`**: computes marginal cost per subagent (subagent.tokens_output × brain's cache_write rate / 1e6). Returns `hybrid_attribution` dict with per-subagent costs and hidden_hybrid_cost_usd. Wired into `get_session_telemetry()`.
- **`telemetry.json` schema**: added `hybrid_attribution` field with subagent_marginal_costs, hidden_hybrid_cost_usd, parent_cache_efficiency_pct (reserved), ttl_lapse_flag (advisory). Backward-compat: pre-v7.3.5 sessions render unchanged.
- **`session-report.py` enhancements**: per-agent cost delineation; Brain row shows `(+$Y.YY hidden)` when hidden_hybrid_cost > 0 and `[TTL-lapse?]` when ttl_lapse_flag is True. New `--hybrid-detail` flag prints per-subagent marginal-cost breakdown.
- **`verify-cost-rates.py`**: standalone rate-drift detector. CLI: `verify-cost-rates.py <session_dir>` or `--session-id <id>`. Per-tier status: OK / WARN (unknown model) / OK: free-tier / STALE (drift > 1% tolerance). Exit 0 on OK/WARN, exit 1 on STALE.
- **Check D in `smoke-test.sh`**: integrated `verify-cost-rates.py` as 4th check. Pass threshold increased from 3/3 to 4/4.
- **`deploy.sh` update**: added `model-rates.yaml` (data files loop) and `verify-cost-rates.py` (Python implementations loop). Python script NOT `+x` per hotfix #8 convention.

### Verification

- `opencode agent list 2>&1 | grep reviewer` shows `reviewer ... anthropic/claude-sonnet-4-6`.
- `~/.config/opencode/scripts/verify-cost-rates.py <session_dir>` exits 0; per-tier output shows OK lines.
- `~/.config/opencode/scripts/smoke-test.sh <session_dir>` reports 4/4 PASS with Check D output.
- `~/.config/opencode/scripts/session-report.sh --last 1 --hybrid-detail` shows per-agent table + marginal breakdown.
- `jq '.hybrid_attribution' <session_dir>/telemetry.json` returns full hybrid object.

---

## 2026-05-30 — v7.3 hotfix #8: deploy.sh orphan-cleanup conflict + script `+x` consistency

**Commit:** `a2442b3`

### Delivered

- **`deploy.sh` orphan-cleanup**: removed `native-session-report.sh` and `native-session-report.py` from the v7.3 dead-script orphan list. Hotfix #7 (`7fabdaa`) restored these files but didn't remove the v7.3 deletion entries; every `./deploy.sh` was: copy → orphan-delete → file missing. Cleanup loop now restricted to the 5 files that are still genuinely dead (`bash-session-init.sh`, `native-session-finalize.py`, `native-subagent-cost.sh`, `sohoai-live-cost.sh`, `otel-headers-helper.sh`). Inline comment warns future editors against re-adding the native-session-report entries.
- **Script `+x` consistency**: chmod'd `scripts/session-report.sh`, `scripts/telemetry-report.sh`, and `scripts/telemetry-summarize.sh` to `+x` in the repo. Previously inconsistent with `native-session-report.sh` and `smoke-test.sh` (which were `+x`). Worked at deploy time because `deploy.sh` chmods, but operators running scripts from the repo directly would hit permission-denied.

### Verification

- `./deploy.sh` no longer reports `cleaned orphan: native-session-report.{sh,py}` after the Scripts: deploy step.
- `~/.config/opencode/scripts/native-session-report.sh` and `.py` persist across redeploys.
- `ls -la scripts/*.sh` in repo: all wrappers `-rwxr-xr-x`.

---

## 2026-05-30 — v7.3 hotfix #7: restore native-session-report + smoke-test deploy/import + $HOME-cwd advisory

**Commit:** `7fabdaa`

### Delivered

- **`native-session-report.{sh,py}` restored (OC-SQLite-sourced)**: v7.3 (`76b9800`) deleted the CC-era native-session reporter pair. Per `claude-orchestra` convention, every Python report should have a `.sh` wrapper (`+x`) + `.py` impl (not `+x`). `session-report.{sh,py}` already followed this; native-session-report was the missing pair. New OC version queries OC's DB for `parent_id IS NULL` sessions and excludes any whose `id` appears in some orchestra session_dir's `.oc-session-id` sidecar. Same arg surface as claude-orchestra: `--last`, `--since`, `--month`, `--project`, `--min-cost`, `--json`, `--exclude-orchestra` (no-op for muscle-memory parity).
- **`smoke-test.sh` deploy + `oc_db` import fix**: `deploy.sh` `Scripts:` loop omitted `smoke-test.sh` entirely → never present at deploy target. Check B's `import oc_db` failed because the deployed file is `oc-db.py` (hyphen) which Python can't `import`. Replaced with `importlib.util.spec_from_file_location` (same pattern as `scripts/telemetry-summarize.py`). Bonus: Check C's `total_tokens` now includes `cache_read + cache_write`, matching the v7.3 hotfix #2 fix to `session-report.py` (previously showed 119K for a 457K-token session).
- **`$HOME`-cwd advisory in `brain.md` + `duo-plan.md` setup bash (nice-to-have)**: When OC's daemon is launched from `$HOME` with no project anchor (the typical octmux-attaching-to-systemd setup), relative paths in `/brain` prompts resolve against `$HOME`. Setup bash now emits 3 `WARN:` lines explaining this so Brain surfaces it in Phase 0. Long-term systemic fix lives in octmux — pass `process.cwd()` to `client.session.create({})` — out of scope here.

`deploy.sh` also reorganized: shell wrappers all in one `+x` loop, Python implementations all in one no-chmod loop. Header comment documents the convention.

### Verification

- `~/.config/opencode/scripts/native-session-report.sh --last 5` lists 5 non-orchestra OC sessions with costs from OC DB.
- `~/.config/opencode/scripts/smoke-test.sh <session_dir>` reports 3/3 PASS with correct 457,388-token total for `ses_18a544a4effeLo8NL1EAZJdcKN`.

---

## 2026-05-29 — v7.3 hotfix #6: deploy.sh restart opencode-server.service

**Commit:** `2cc3721`

### Delivered

- **`deploy.sh` final step**: now runs `systemctl --user restart opencode-server.service`. OC reads its config (agents/, commands/, AGENTS.md, opencode.json) once at startup and never reloads. Without a restart, deployed changes silently have no effect — multiple smoke tests had already mis-fired because the OC server was running stale config.
- **Guards**: detects missing `systemctl`, missing service unit, or restart failure; warns clearly in each case. Override with `--no-restart` for the rare file-only deploy.
- **Quick-start hint** updated: dropped the leftover "Shift+Tab to enter plan mode" CC-ism, replaced with "Set octmux permission mode with Shift-TAB (ask / allow / deny)" per the v7.3 hotfix #4 vocabulary.
- **Safety check** documented in `~/.claude/CLAUDE.md` (global): after every `./deploy.sh`, verify `systemctl --user show -p ActiveEnterTimestamp opencode-server.service` is newer than the deployed file mtimes.

### Verification

- `./deploy.sh` reports `restarted: opencode-server.service` at the end.
- OC daemon process `lstart` is updated after deploy; running `/brain` immediately picks up the new command body.

---

## 2026-05-29 — v7.3 hotfix #5: residual CC-isms in brain.md description + orchestra-guard

**Commit:** `a990703`

### Delivered

Two leaks missed in hotfix #4 (`a676e18`) and surfaced by the next smoke test:

- **`commands/brain.md` frontmatter `description:`** still said "Requires plan mode at parent" — visible in `/help` and the slash-command overlay. Replaced with "Operator approves the plan via natural-language reply."
- **`agents-md-block/orchestra-guard.md`** (injected into `~/.config/opencode/AGENTS.md` on every turn) still referenced `Plan-mode's "build your plan at ~/.config/opencode/plans/<name>.md" reminder does NOT apply` — fighting a CC reminder OC doesn't emit. Also dropped the `planner-long` / `planner` agent variant reference (no `planner-long` agent exists in `agents/`).

### Verification

- `grep -nE "Plan-mode|plan mode" ~/.config/opencode/AGENTS.md` returns empty.
- `head -3 ~/.config/opencode/commands/brain.md` shows the natural-language-reply description.

---

## 2026-05-29 — v7.3 hotfix #4: drop CC-isms, use OC-native permission vocabulary

**Commit:** `a676e18`

### Delivered

OC 1.15.11 has no plan mode, no `ExitPlanMode` tool, no auto-edit/manually-approve UX, no `--dangerously-skip-permissions` flag. The previous command and agent bodies were inherited from `claude-orchestra` and contained:

- "Plan mode is active" prerequisites + "Shift+Tab" instructions
- `ExitPlanMode` calls at the plan-approval gate
- "auto-edit / manually approve / cancel" UX descriptions
- `--dangerously-skip-permissions` / `bypassPermissions` references
- An "Override of plan-mode's plan-file directive" section in `brain.md` fighting a CC reminder OC doesn't emit

Replaced throughout with OC + octmux native vocabulary from `octmux/docs/Stage5.md §5.3` (octmux commit `2d440b9`): octmux's global permission mode (`ask` yellow / `allow` green / `deny` red, cycled with **Shift-TAB**), covering all OC tool categories (filesystem `read`/`edit`/`glob`/`grep`/`list`, shell `bash`, network `webfetch`/`websearch`, repository `repo_clone`/`repo_overview`, agents `task`/`skill`, other `external_directory`/`lsp`/`todowrite`). Plan approval is a natural-language operator signal (`"approved"`/`"go ahead"`/`"proceed"`) — no tool call gates it.

Each agent body now carries an explicit "frontmatter grants X; runtime mode determines per-call behaviour" sentence to make the two-layer permission model (frontmatter `tools:` + runtime mode) visible. The two stack: a tool denied in either layer cannot be authorised by the other (e.g., Planner stays read-only even under `allow`).

**Pipeline semantics unchanged.** Brain/Planner/Actor/Reviewer phases, session-dir artefacts, atomic-rename, cleanup ordering — all identical.

### Verification

- `grep -nE "ExitPlanMode|Plan mode is active|Shift\+Tab|--dangerously|acceptEdits" commands/*.md agents/*.md` returns empty.
- Every operator-facing file (`brain.md`, `duo-plan.md`, `duo-act.md`) carries all three traffic-light terms + `Shift-TAB`.
- `opencode agent list` still shows all four agents registered; `actor` → `actor-heavy` body-mirror invariant maintained.

---

## 2026-05-29 — v7.3 hotfix #3: resolve OC session ID via HTTP API

**Commit:** `51073cf`

### Delivered

The v7.2 setup-bash assumed OC exports `OC_SESSION_ID` into bash subprocesses. **OC 1.15.11 does not.** Verified by extracting the binary's full `OPENCODE_*` env-var list — no `OPENCODE_SESSION_ID`, no `OC_SESSION_ID`. The assumption traces back to early Stage 6 (the deleted `scripts/bash-session-init.sh` used the same env var name as its primary key); either OC dropped it in a past version or it was never exported.

Consequence: `.oc-session-id` had been silently empty in every orchestra session since v7.2 → `telemetry-summarize.py` produced `cost_source: "none"`, zero totals. OC's DB had the correct data throughout; the sidecar contract just never connected to it.

Fix: replace the `${OC_SESSION_ID:-}` write in `commands/brain.md` and `commands/duo-plan.md` setup-bash with an HTTP-API query against `GET /session` (port from `OPENCODE_PORT` env var, default 4096), filtered to top-level (`parentID == null`) sessions in the current `directory`, taking the most-recently-updated. Requires only `curl` (universal) and `jq` (already a deploy prereq). Falls back to empty on API failure — same degraded behaviour as pre-fix, no regression.

### Verification

- Live resolver test against `ses_18c16888dffe0njgOjZs0MXnge`: returns the correct ID for `directory == /home/florian`.
- Post-deploy `/brain` smoke test (`ses_18a544a4effeLo8NL1EAZJdcKN`): `.oc-session-id` is 31 bytes with a valid `ses_...` value; `telemetry.json` has `cost_source: "oc_sqlite"` with full data.

---

## 2026-05-29 — v7.3 hotfix #2: token totals include cache_read + cache_write

**Commit:** `d4b1ab7`

### Delivered

Both `totals.tokens_cache_write` (`oc-db.py`) and `session-report.py`'s displayed "Tokens" column were missing cache traffic. An Opus Brain session showing `$0.76` displayed only 11,891 tokens (input+output) when OC's DB recorded **489,813** (37 input + 11,854 output + 438,260 cache_read + 39,662 cache_write). The displayed number understated processed volume by ~97.5% for cached-heavy sessions. Cost was correct throughout (read straight from `totals.cost_usd_estimate`); this fix is display-only.

Fix: `oc-db.py:get_session_telemetry()` totals now sum `tokens_cache_write` too (and the not-found fallback's zero totals carry the same shape). `session-report.py` adds cache-read and cache-write into the displayed total.

### Verification

- Recomputed `ses_18c3a3e2fffeZg3SOuHaCnoJOy` (Opus 4.7 Brain session) totals: now match raw OC DB columns (37 / 11,854 / 438,260 / 39,662 / total 489,813).
- `~/.config/opencode/scripts/session-report.py --last 5` now shows ~400K–800K tokens for typical Brain sessions (was ~10K before).

---

## 2026-05-29 — v7.3 hotfix #1: agent tools frontmatter as YAML object

**Commit:** `7310878`

### Delivered

OC 1.15.11 rejects `tools:` as a comma-separated string with `Expected object | undefined, got "Read, Grep, ..." tools`. One bad agent file silently kills the entire `~/.config/opencode/agents/` discovery — `opencode agent list` fails, Brain sees only the built-in `general`/`explore` subagents, and Phase 1 dispatch fails with `Unknown agent type: planner`.

Verified the failure mode against `ses_18c3a3e2fffeZg3SOuHaCnoJOy` (octmux `/brain` session, 2026-05-29 12:49Z): parent row present, **0 child sessions** in OC's DB — confirming Planner Task dispatch never created a child row.

Fix: reformatted `tools:` to a YAML map (`Read: true\nGrep: true\n...`) in all four agents — `planner.md`, `actor.md`, `actor-heavy.md`, `reviewer.md`.

### Verification

- `opencode agent list` shows `planner (all)`, `actor (all)`, `actor-heavy (all)`, `reviewer (all)` after deploy.
- Subsequent `/brain` smoke tests dispatch Planner/Actor/Reviewer successfully (3 child sessions visible in OC DB with `parent_id = brain_session_id`).

---

## 2026-05-29 — v7.3: Status-line OC SQLite + dead-file deletes + deploy.sh + docs fold

**Commit:** `76b9800`

### Delivered

- **`status-line/orchestra-block.sh`** rewrite (lines ~96–215 removed):
  - Removed: `_is_non_anthropic` flag + case block, entire "SoHoAI live token fallback" block (`.lck` reads, `sohoai-live-cost.sh` call, `context-windows.yaml` lookups), `cost_divergence` cross-check block, glob+sum block (`_native_cost` from `native-sessions/*.json` + `_orch_cost` from `sessions/*/telemetry.json`).
  - Added: OC SQLite direct read — `$OC_SID` env var passed to `oc-db.py` via python heredoc, calls `get_session_telemetry()`, displays `Σ$` cost prefix format.
  - Kept: header vars, OC-native strip, brain+duo badges, active indicator, ctx token fallback, model_id extraction, `ctx_seg` call, `_insert` block, badge rendering.
  - Result: script is ~100 lines shorter, cost reads from OC DB instead of SoHoAI.

- **`scripts/smoke-test.sh`** rewrite (entire T1/T2/global-log structure removed):
  - Check A (sidecar): File `${SESSION_DIR}/.oc-session-id` exists and non-empty.
  - Check B (DB row + child count): `oc_db.get_session()` returns non-NULL row; `get_child_sessions()` counts dispatches.
  - Check C (telemetry.json + cost): File exists, `cost_source == "oc_sqlite"` (accepts zero cost for flat-rate models).
  - Result: verifies OC-native pipeline end-to-end (v7.3+).

- **`scripts/session-report.py`** rewrite:
  - Removed: `load_native_telemetry()`, `load_active_native_sessions()`, `_read_model_from_jsonl()`, `_read_project_from_jsonl()`, `_NATIVE_UUID_RE` pattern, orchestra-start-time dedup block, `--source native` branch (returns empty).
  - Added: `load_orchestra_telemetry_v2()` — walks `~/.config/opencode/orchestra/sessions/*/telemetry.json` directly.
  - Updated `format_cost()`: with `cost_source == "oc_sqlite"`, display `$0.0000` for zero-cost sessions (flat-rate).
  - Kept: `--last`, `--since`, `--month`, `--source` arg parsing, `apply_filters()`, tabular output, aggregate footer.
  - Result: produces correct output for v7.1+ sessions; native session reads removed (future work).

- **`scripts/telemetry-report.sh`** rewrite:
  - Removed: `TELEMETRY_JSONL` variable + early-exit check, `PRICING_FILE` + staleness check, `--native` mode section, `yaml` import from Python blocks.
  - Added (default mode): Python one-liner walks `sessions/*/telemetry.json`, produces same TSV columns (Date, Command, Outcome, Cost, Source, Tokens, Duration).
  - Rewritten (--tier mode): `TIER_PY` reads cost pre-computed in telemetry.json (per-agent `cost` field); no pricing.yaml lookups. `CUMUL_PY` similarly accumulates from telemetry.json files directly.
  - Kept: `--last N`, `--tier`, arg parsing, aggregates section.
  - Result: works with current telemetry.json files directly.

- **Dead files deleted** (8 total, via `git rm`):
  - `scripts/bash-session-init.sh`, `scripts/native-session-finalize.py`, `scripts/native-subagent-cost.sh`
  - `scripts/sohoai-live-cost.sh`, `scripts/otel-headers-helper.sh`
  - `scripts/native-session-report.sh`, `scripts/native-session-report.py`
  - `config/pricing.yaml`

- **`deploy.sh`** updates:
  - Removed: `$OC_HOME/orchestra/native-sessions` mkdir, 8 scripts from deploy loop, 3 Python blocks, `pricing.yaml` copy.
  - Added: `oc-db.py` copy (after telemetry-summarize.py).
  - Added: orphan cleanup block (7e) for 8 deleted files + `pricing.yaml` removal from existing installs.
  - Updated: AGENTS.md guard — auto-create empty `$GLOBAL_AGENTS_MD` if missing (instead of warn+skip).
  - Result: deploys oc-db.py, cleans 8 orphans from existing installations, auto-creates AGENTS.md.

- **`collect.sh`** update:
  - Removed: `sohoai-live-cost.sh` collect.
  - Added: `oc-db.py` collect.

- **`AGENTS.md`** (new, created from `to-be-reviewed--AGENTS.md`):
  - Removed: dead-script references, T1/T2/native-session telemetry smoke tests, `telemetry-events.jsonl` notes, BASH_ENV setup instructions.
  - Added: new §Smoke tests (v7.3+) — 3 checks via `smoke-test.sh`, cost report via `session-report.py`, ctx segment test.
  - Result: current with v7.3+ architecture; deployed to `~/.config/opencode/AGENTS.md` by deploy.sh.

- **`README.md`** update:
  - Removed: `pricing.yaml` from config/ directory table, T1/T2 / transcript-parse mentions, example status-line with `↯ 100k/1000k` (replaced by ctx bar + cost).
  - Updated: status-line example to show current layout (ctx bar, `Σ$cost`, badge).
  - Result: no longer references removed components.

- **`docs/design.md`** major update:
  - §Telemetry §Rationale: replaced forward pointer to pre-Stage7 doc with "OC-native SQLite shipped in v7.1–v7.3; see §OC SQLite schema below."
  - §File inventory: added `scripts/oc-db.py`, removed `native-sessions/native-*.json`, removed `telemetry.jsonl` reference (now walks `sessions/*/telemetry.json`).
  - **New §OC SQLite schema** subsection: DB path, key columns, per-tier breakdown via `parent_id`, `.oc-session-id` sidecar glue point, design rationale (read-only SQLite, cost pre-computed, schema coupling localised, `time_archived` dual-check).
  - Refreshed: `updated_at: 2026-05-30--00-50`.
  - Result: docs/design.md is authoritative; no forward pointers to pre-Stage7 doc.

- **`docs/pre-Stage7--opencode-redesign.md`** tombstone:
  - Kept: YAML frontmatter with `updated_by`/`updated_at`.
  - Replaced: entire body with breadcrumb: "Content folded into docs/design.md §OC SQLite schema as of v7.3 commit `76b9800`. This file is preserved as a breadcrumb; see docs/Stage7.md §v7.3 for delivery details."
  - Result: file exists as a one-line breadcrumb; doesn't mislead readers.

### Deliverables summary

- 8 dead scripts + config deleted (git rm)
- 5 shell/Python scripts rewritten (status-line, smoke-test, session-report, telemetry-report, deploy, collect)
- 1 new file created (AGENTS.md)
- 2 docs updated + 1 tombstoned
- All syntax checks PASS; all smoke tests PASS (12 checks)

### Smoke tests (all 12 PASS)

- Syntax: orchestra-block.sh, smoke-test.sh, deploy.sh, collect.sh, telemetry-report.sh
- Dead files: 8 total (all confirmed deleted)
- New files: oc-db.py, AGENTS.md (both present)
- Python compile: session-report.py (success)

---

## 2026-05-29 — v7.2: `orchestra-hook.sh` Writers A+B strip + `.oc-session-id` sidecar

**Commit:** `0479ea8`

### Delivered

- **`scripts/orchestra-hook.sh`** (~150 lines removed):
  - **`stop` mode**: Removed Writer A native-residual-tick block (native-sessions/*.json writes, `OC_TOTAL` minus orchestra sum residual computation). Removed dead-lck-file finalizer loop (no more `.lck` files to track). **Preserved**: orphan-session finalizer (safety net for crash recovery; walks session dirs without `telemetry.json` AND without inflight markers).
  - **`end` mode**: Removed Writer B partial-telemetry block (`telemetry-summarize.sh ... --status in_flight` call, `partial_write` invocations.log event). **Preserved**: subagent start/end logging to `invocations.log`.
  - **`start` mode**: Removed telemetry-events.jsonl append logic. Removed `.transcript-uuid` / `.transcript-path` sidecar captures (no longer needed post-v7.1).

- **`commands/brain.md`** setup block:
  - Removed `~/.config/opencode/active-sessions/*.lck` write + housekeeping loop.
  - Removed `.transcript-path` + `.transcript-uuid` sidecar writes.
  - **Added**: `printf '%s\n' "${OC_SESSION_ID:-}" > "${SESSION_DIR}/.oc-session-id"` immediately after `.project-dir` write. This is the **single glue point** between orchestra session-dirs and OC session rows; enables `telemetry-summarize.py` to query OC's DB.
  - Updated cleanup block: removed `.lck` rm, simplified `telemetry-summarize.sh` 4th arg to `""` (no more transcript-uuid fallback).

- **`commands/duo-plan.md`** setup block: identical edits to `brain.md`.

- **`commands/duo-act.md`** cleanup block:
  - Removed `.lck` rm line.
  - **Added** before `.duo-inflight` removal: `printf 'ORCHESTRA_MODE=default\nORCHESTRA_TITLE=\n' >> state.env` to reset the pipeline badge immediately on cleanup.
  - Updated `telemetry-summarize.sh` 4th arg to `""`.

- **`commands/duo-abandon.md`** cleanup block: identical edits to `duo-act.md`.

- **`commands/brain-abandon.md`** cleanup block:
  - Removed `.lck` rm line only (state.env reset already present).
  - Updated `telemetry-summarize.sh` 4th arg to `""`.

### Result

Live `/brain` and `/duo-plan` sessions now write `.oc-session-id` at setup. At cleanup, `telemetry-summarize.py` reads this sidecar, queries OC's SQLite session table via `oc-db.py`, and produces `cost_source: "oc_sqlite"` in the final `telemetry.json`. The active-sessions lck mechanism and native-session cost ticking are gone; cost attribution is now fully OC-native. `invocations.log` writes (Stage 8.1 octmux dependency) are preserved.

### Smoke tests (all PASS)

- **T1**: `orchestra-hook.sh` syntax valid
- **T2**: `.oc-session-id` sidecar written correctly
- **T3**: No lck creation code remains in setup blocks
- **T5**: Writer B removed (no `partial_write` or `in_flight` in stop path)
- **T6**: No telemetry-events.jsonl appends (only checks for artefact existence in orphan finalizer)
- **T4**: `telemetry-summarize.py` structure valid, can read `.oc-session-id`

---

## 2026-05-29 — v7.1: `oc-db.py` + `telemetry-summarize.py` OC-SQLite rewrite

**Commit:** `21c3bd3`

### Empirical findings

- **`time_archived` Hypothesis B confirmed** (2026-05-29 DB inspection): `time_archived` is
  NULL for all observed sessions including those closed hours ago. OC never sets it on normal
  session close. The `time_updated < now - 30 min` fallback in `oc_db.is_session_over()` is
  **load-bearing**, not just defensive.

- **`model` column is JSON**: OC's `session.model` stores a JSON object
  `{"id":"kimi-k2.6","providerID":"sohoai","variant":"default"}`. `oc-db.py`'s `_parse_model()`
  extracts the `id` field; falls back to the raw string for NULL or non-JSON values.
  Stage7.md originally assumed plain strings — corrected in this commit.

- **File disambiguation**: `telemetry.json` (per-session, at
  `sessions/<UTC-ts>-<PID>/telemetry.json`) is distinct from `telemetry.jsonl` (global
  append-only index at `orchestra/telemetry.jsonl`). The latter is dropped here; v7.3's
  `session-report.py` rewrite will walk `sessions/*/telemetry.json` directly.

### Delivered

- **`scripts/oc-db.py`** (new, ~90 lines): read-only OC SQLite helper. Functions:
  `open_db()`, `_check_schema()`, `_parse_model()`, `get_session()`, `get_child_sessions()`,
  `is_session_over()`, `_zero_tier()`, `_row_to_tier()`, `get_session_telemetry()`.
  Safety: `?mode=ro` URI, WAL, 5 s timeout, schema self-check at first open.

- **`scripts/telemetry-summarize.py`** (full rewrite, 852 → ~150 lines): drops T2/SoHoAI/
  litellm/pricing.yaml cascade entirely. Now reads `.oc-session-id` sidecar, calls
  `oc_db.get_session_telemetry()`, writes `telemetry.json` per cross-repo contract shape.
  Drops global `telemetry.jsonl` append. Handles missing `.oc-session-id` gracefully
  (`cost_source: "none"` + stderr warning).

- **`scripts/telemetry-summarize.sh`** (minor): removed `.transcript-uuid` fallback.

- **`docs/Stage7.md`**: corrected empirical findings (Hypothesis B confirmed, `model` JSON
  format); added explicit path for `telemetry.json` + disambiguation note in §Cross-repo
  contract.

- **`docs/design.md`**: updated file inventory annotations: `telemetry.json` label corrected
  (removed stale "T2"); `telemetry.jsonl` noted as dropped in v7.1.

### Smoke tests: PASS T1–T8

T1 schema ok · T2 `_parse_model` JSON/None/plain · T3 `get_session` live row ·
T4 `is_session_over` old session · T5 `get_session_telemetry` structure ·
T6 unknown-id zero-struct · T7 summariser with `.oc-session-id` ·
T8 summariser without `.oc-session-id`

### Out of scope (v7.2)

Live callers (`orchestra-hook.sh`, `commands/*.md`) are not updated here.
The `.oc-session-id` sidecar is not yet written by any orchestra session command.
All live sessions produce `cost_source: "none"` until v7.2 ships. This is expected.

---

## 2026-05-28 — v7.0: Stage 7 redesign scaffold + design.md stale-ref purge

**Commit:** `de631cc`

### Delivered

- Created `docs/pre-Stage7--opencode-redesign.md`: architectural rationale for OC-native SQLite
  telemetry redesign; empirical findings; design choices; transient staging doc.
- Created `docs/Stage7.md`: 6-stage roadmap (v7.0–v7.5) with status markers and Stage 6
  sub-stage status mapping table.
- Created `docs/Stage7--Changelog.md`: this file; carries forward Stage 6 entries.
- Deleted `docs/Stage6.md` and `docs/Stage6--Changelog.md`.
- Cleaned `docs/design.md`: removed T1/T2 hybrid sections, SoHoAI proxy section, cost-source
  cascade section, native session tracking section (CC-era), CC statusLine JSON schema section
  (CC-era), SoHoAI live cost subsection, and all stale references. Added forward-pointer in
  telemetry slot. Refreshed frontmatter timestamps.

### Out of scope
Code changes deferred to v7.1–v7.3.

---

## 2026-05-28 — Stage 6.1.1: `claude-code-*` alias purge [status: PRESERVED, load-bearing for v7.X]

**Commit:** `67a1434`

### Delivered

**Load-bearing fix — agent frontmatter:** `agents/{planner,actor,actor-heavy,reviewer}.md` were declaring `model: claude-code-<X>` in their frontmatter. OpenCode's agent loader has no provider exposing that ID, so dispatch was silently falling back to the parent session's default model. In practice, the multi-tier worker design was running as **single-tier** (Planner, Actor, Reviewer all on whatever the parent used). All four agents now declare canonical OpenCode IDs from the `provider.sohoai` block in `~/.config/opencode/opencode.json`:

| Tier | Was | Now |
|---|---|---|
| Planner | `claude-code-glm-5.1` | `sohoai/glm-5.1` |
| Actor | `claude-code-qwen3-coder-next` | `sohoai/qwen3-coder-next` |
| Actor-Heavy | `claude-code-kimi-k2.6` | `sohoai/kimi-k2.6` |
| Reviewer | `claude-code-kimi-k2.6` | `sohoai/kimi-k2.6` |

**Cleanup — dead lookup keys / dead branches:**
- `config/pricing.yaml`: 6 key renames + `notes:` block rewritten (no more "gateway alias" framing — these are canonical OC IDs). `last_updated: 2026-05-28`.
- `config/context-windows.yaml`: 6 key renames; preamble comment updated to drop alias language.
- `scripts/telemetry-summarize.py`: 3 `startswith("claude-code-")` guards → `startswith("sohoai/")`; docstring at line 305 rewritten.
- `status-line/orchestra-block.sh`: case branches (lines 97, 99) and prefix-strip (line 127) switched to `sohoai/` discriminator. Prefix-strip logic now correctly uses `!=` test instead of empty-string check.

**Docs (live sections only):**
- `README.md`: model-tier table updated to `sohoai/*` IDs.
- `docs/design.md`: every live prose mention updated (intro, subagents section, /duo workflow advice, model-tier table, model-requirements `/duo` advisory row, non-Anthropic models section, cost section, "deployable surfaces" bullet, multi-model routing table, brain recommendation paragraph, SoHoAI routing-stability note, Reviewer rationale).
- `AGENTS.md`: agents/ inventory + ctx-segment smoke-test invocations.

### Files changed
`agents/planner.md`, `agents/actor.md`, `agents/actor-heavy.md`, `agents/reviewer.md`, `config/pricing.yaml`, `config/context-windows.yaml`, `scripts/telemetry-summarize.py`, `status-line/orchestra-block.sh`, `README.md`, `AGENTS.md`, `docs/design.md`, `docs/Stage6--Changelog.md`

---

## 2026-05-28 — Brain model recommendation (Anthropic Opus 4.7, advisory only) + commands/agents docs clarification [status: PRESERVED]

**Commit:** `a90b4dc`

### Delivered

**Brain model recommendation — Anthropic Opus 4.7 (advisory, never blocks):**
- `commands/brain.md`: replaced the prior `claude-code-kimi-k2.6` "recommended run environment" with an Anthropic Opus 4.7 recommendation. Implemented as a Prerequisite #1 **advisory check** — emits a one-line notice when Brain is not on Opus 4.7, then proceeds regardless. Any model is permitted; the operator's choice is final.
- **Deliberate deviation from `claude-orchestra`:** the upstream project hard-gates the equivalent check (STOPs on Haiku, older Sonnet, or non-Anthropic models). `oconona` downgrades to advisory only — the recommendation is preserved, but enforcement is removed. This is documented inline in `commands/brain.md`, `docs/design.md` §Model requirements, and `AGENTS.md`.
- Rationale captured inline: project name `--non-Anthropic` refers to the *worker tier* (Planner / Actor / Reviewer / Actor-Heavy) only. Brain itself benefits from Anthropic's strongest reasoning model because the orchestrator's job (multi-turn interrogation, plan reasoning, dispatch decisions, review judgment) rewards reasoning quality, and Brain is one session per pipeline (not per step), so the cost is bounded.

**Docs clarification — slash commands vs subagents:**
- `README.md`: added an explicit "Slash commands vs subagents" section with a comparison table; updated the model-tier table to reflect Brain = Anthropic Opus 4.7.
- `docs/design.md`: added a dedicated "Slash commands vs subagents" section near the top with full table (source dir, deploy dir, invocation mechanism, frontmatter expectation, purpose). Updated all Brain references (intro, tier table, model-requirements table, telemetry rationale, sample tier proportions, multi-model routing). Added a new "Why /brain is hard-gated to Anthropic" subsection under §Model requirements.
- `AGENTS.md`: added a "Brain model" section and a "Layout" preamble that explicitly distinguishes `commands/` (operator-facing slash commands) from `agents/` (dispatchable subagents).

### Files changed
`commands/brain.md`, `README.md`, `docs/design.md`, `AGENTS.md`, `docs/Stage6--Changelog.md`

---

## 2026-05-28 — Stage 6.1: Dual-stream writers + path audit fix [status: PARTIALLY SUPERSEDED]

**Commits:** `f39e96c` (code), `cbfc067` (docs)

**Superseded by:** v7.1–v7.3 (Writer A + Writer B + glob+sum cost path will be replaced by OC-SQLite reads).
**Preserved:** Path audit (`~/.config/opencode/orchestra/` migration), `.project-dir` sidecar, `deploy.sh` `agent/`→`agents/` fix.

### Delivered

**Path audit (all scripts, commands, docs):**
- Migrated all `${OPENCODE_PROJECT_DIR}/.opencode/orchestra/` references to `~/.config/opencode/orchestra/` (global NFS-shared path)
- Fixed `deploy.sh`: `agent/` → `agents/`, `command/` → `commands/` (canonical OpenCode dirs per opencode.ai/docs)
- Added native-sessions directory creation to `deploy.sh`
- Added `.project-dir` sidecar file written at session creation for project attribution across the global sessions directory

**Stage 6.1 writers:**
- **Writer A** (native residual tick): `scripts/orchestra-hook.sh` stop mode now writes `~/.config/opencode/orchestra/native-sessions/native-<uuid>.json` on every response turn while no orchestra session is in flight. Residual = OC session total minus sum of orchestra session costs. Atomic write (tmp + rename). Logs `native_tick` events and `native_cost_decrease` violations to invocations.log.
- **Writer B** (orchestra partial telemetry): `scripts/orchestra-hook.sh` end mode now triggers `telemetry-summarize.py --status in_flight` after each SubagentStop. Writes `telemetry.json` in the session dir with `"status": "in_flight"` — skips global `telemetry.jsonl` append and T1/T2 cross-check.

**Telemetry infrastructure:**
- `scripts/telemetry-summarize.sh`: added `${@:5}` passthrough so `--status in_flight` reaches the Python script
- `scripts/telemetry-summarize.py`: added `--status final|in_flight` arg; added `project_dir` field to `telemetry.json` and global log (read from `.project-dir` sidecar)
- `scripts/session-report.py`: reads `project_dir` from `telemetry.json` first (Stage 6.1+), falls back to path-based inference for legacy sessions

**Status-line cost display:**
- `status-line/orchestra-block.sh`: replaced SoHoAI + native-subagent-cost.sh live-cost with direct glob+sum over `native-sessions/*.json` and `sessions/*/telemetry.json`. Added 5% cost_divergence cross-check (logs to invocations.log, never suppresses display).

### Files changed
`deploy.sh`, `scripts/orchestra-hook.sh`, `scripts/telemetry-summarize.sh`, `scripts/telemetry-summarize.py`, `scripts/session-report.py`, `status-line/orchestra-block.sh`, `commands/brain.md`, `commands/brain-abandon.md`, `commands/duo-plan.md`, `commands/duo-abandon.md`, `commands/duo-act.md`, `agents-md-block/orchestra-guard.md`, `config/config.yaml`, `scripts/smoke-test.sh`, `.gitignore`, `docs/Stage6.md`, `docs/design.md`, `README.md`, `docs/Stage6--Changelog.md` (new)

---

*(Future Stage 7 sub-stage entries will be prepended here)*
