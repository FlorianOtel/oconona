---
title: "Stage 7.5 — v7.5 orchestra contract: gap analysis"
created_at: 2026-06-04--04-07
created_by: Actor (sohoai/glm-5.1 via /brain octmux-orchestrator)
updated_by: Actor (sohoai/glm-5.1 via /brain octmux-orchestrator)
updated_at: 2026-06-04--04-07
context: >
  Gap analysis of the v7.5 orchestra contract as documented across
  oconona/docs/Stage7.md, oconona/docs/Stage7.5--implementation-details.md,
  octmux/docs/Stage8.md, and octmux/docs/Stage8--implementation-details.md.
  Companion to Stage7.5-stress-tests.md which translates these gaps into
  operator-runnable test recipes. Docs-only audit (no source-code reading);
  findings the docs cannot confirm are explicitly marked Unverified —
  operator source-audit required.
---

# Stage 7.5 — v7.5 orchestra contract: gap analysis

## Status and scope

This document audits the v7.5 orchestra contract for gaps, contradictions, and under-specified edge cases as documented across four canonical source documents:

| Doc | Role |
|---|---|
| `oconona/docs/Stage7.md` | Provider roadmap + write-order invariants + failure-mode table |
| `oconona/docs/Stage7.5--implementation-details.md` | Authoritative v7.5 harness contract (sidecars, badge, telemetry shape, crash recovery) |
| `octmux/docs/Stage8.md` | Consumer changelog + known limitations + oconona feedback |
| `octmux/docs/Stage8--implementation-details.md` | Consumer-side contract mirror + fragility/race analysis |

**Method:** docs-only — every claim below cites file:line from one of these four documents. Conclusions that cannot be confirmed from documentation alone are marked **Unverified — operator source-audit required**. The companion document `Stage7.5-stress-tests.md` (written in a separate step) translates these gaps into operator-runnable test recipes.

---

## Executive summary

The v7.5 contract is broadly sound: atomic-rename writes, snapshot-delta attribution, and the orphan-finalizer crash-recovery path form a coherent foundation. However, the audit identifies **14 gaps** across five categories:

- **Race conditions & ordering (3 gaps):** One direct contradiction between two canonical docs on the telemetry-vs-marker write order (G-01), two scenarios where concurrent writers can corrupt sidecar state (G-02, G-03).
- **Token/cost accounting (3 gaps):** Asymmetric display of hybrid-attribution cost (G-04), grandchild cost undercount (G-05), and numerator/denominator confusion between octmux's cumulative Σ$ and oconona's per-segment delta (G-06).
- **Crash-safety and recovery (3 gaps):** OC daemon kill mid-pipeline (G-07), 24h stale-guard false-positive on legitimately long sessions (G-08), and silent degradation when snapshot sidecars fall back to `{}` (G-09).
- **Session-tracking consistency (3 gaps):** Global `ORCHESTRA_TITLE` clobbering between concurrent `/brain` runs (G-10), NFS realpath divergence between oconona's bash `curl` and octmux's `safeRealpath()` (G-11), and `setOcSessionID()` cache staleness after OC session lifecycle edge cases (G-12).
- **Documentation drift (2 gaps):** `stage` vs `subagent` field deprecation in `invocations.log` (G-13), and cross-doc pointer health for the `.oc-session-id` multi-invocation caveat (G-14).

Ten of 14 gaps are **low** severity, reflecting the system's existing mitigations. Two are **medium** (G-01, G-02) because they involve ordering contradictions or race windows that could produce corrupt state under specific crash timing. Two are **medium** (G-04, G-06) because they cause visible operator confusion about cost correctness.

---

## A. Race conditions & ordering

### G-01 — D2 telemetry-vs-marker write order contradiction

**Severity:** med

**Observed in:** `Stage7.md:140` (invariant 4); `Stage7.5--implementation-details.md:377` (invariant 6); `Stage8--implementation-details.md:334` (item D2)

**Mechanism description:** `Stage7.md` invariant 4 states: "telemetry.json (final) written via atomic tmp+rename BEFORE .inflight is removed" (`Stage7.md:140`). Conversely, `Stage7.5--implementation-details.md` invariant 6 states: "The inflight marker is removed BEFORE telemetry-summarize.sh is invoked" (`Stage7.5--implementation-details.md:377`). These are mutually exclusive orderings. If invariant 6 is followed, a brief window exists where a session dir has no inflight marker and no `telemetry.json` — the orphan-finalizer would skip it (marker absent = still in-progress per its skip condition at `Stage7.md:160`), yet `telemetry-summarize.sh` hasn't run, so no telemetry exists. Conversely, if invariant 4 is followed (the actual `/brain` skill behavior per `Stage8--implementation-details.md:334`), the marker is removed only after telemetry is written, eliminating the gap.

**Unverified — operator source-audit required:** The actual `/brain` cleanup bash block must be inspected to confirm which ordering it implements. The documented contradiction needs resolution: one invariant must be amended and the other aligned.

**References:** ST-01

---

### G-02 — Orphan-finalizer race with in-flight cleanup: double .outcome write, overwritten .parent-snapshot-end

**Severity:** med

**Observed in:** `Stage7.md:121` (orphan finalizer); `Stage7.5--implementation-details.md:425` (orphan-finalizer step 5); `Stage7.md:139` (invariant 3 — .outcome before telemetry-summarize)

**Mechanism description:** The orphan-finalizer fires on every OC Stop event (`Stage7.5--implementation-details.md:417`). Its candidate condition is: inflight marker absent, `telemetry.json` absent, artefact(s) present (`Stage7.5--implementation-details.md:424`). If a `/brain` cleanup block has removed the inflight marker (per invariant 6 at `Stage7.5--implementation-details.md:377`) but not yet written `telemetry.json`, the orphan-finalizer running on the same Stop event could see the session dir as a candidate and concurrently write `.outcome=abandoned` and `.parent-snapshot-end`. If the cleanup block also writes `.outcome` (per invariant 3 at `Stage7.md:139`) and `.parent-snapshot-end` (per invariant 5 at `Stage7.5--implementation-details.md:375`), the two writers race. Since both use atomic rename, the last writer wins — potentially overwriting the cleanup block's `.outcome=pass` with `.outcome=abandoned`, or overwriting its `.parent-snapshot-end` with stale values. The docs state the orphan-finalizer is "idempotent" (`Stage7.md:156`) but do not address this concurrent-write scenario.

**Unverified — operator source-audit required:** Whether the `/brain` cleanup and the orphan-finalizer can execute on the same Stop event in the same process cycle. If the cleanup block runs inside the same Bash invocation as the hook that triggers the finalizer, serialization may prevent the race. If they are separate invocations (hook callback vs. cleanup skill), the race is real.

**References:** ST-02

---

### G-03 — Snapshot-sidecar write-order: .parent-snapshot-end vs telemetry-summarize.sh

**Severity:** low

**Observed in:** `Stage7.5--implementation-details.md:375` (invariant 5); `Stage7.5--implementation-details.md:219-223` (fallback paths)

**Mechanism description:** Invariant 5 mandates `.parent-snapshot-end` written AFTER `.outcome` and BEFORE `telemetry-summarize.sh` (`Stage7.5--implementation-details.md:375`). If `telemetry-summarize.py` reads `.parent-snapshot-end` and the file hasn't been written yet (e.g., cleanup bash wrote `.outcome` but crashed before writing the snapshot), the summarizer finds a missing or `{}` snapshot. Per the fallback spec at `Stage7.5--implementation-details.md:219-223`, this triggers `parser_warnings: snapshot_missing` and falls back to cumulative parent values. The fallback is safe (data is not lost, just attributed differently) but silently degrades segment-delta correctness. The gap is that no guard ensures `.parent-snapshot-end` exists before `telemetry-summarize.sh` reads it — the summarizer must handle absence gracefully, which it does, but the operator is only warned via `parser_warnings`.

**References:** ST-03 (may merge with ST-01/ST-02 if the ordering contradiction in G-01 is the root cause)

---

## B. Token/cost accounting

### G-04 — hybrid_attribution.hidden_hybrid_cost_usd invisible in octmux Σ$

**Severity:** med

**Observed in:** `Stage7.5--implementation-details.md:185-194` (telemetry.json hybrid_attribution block); `Stage8--implementation-details.md:44` (cost source — no telemetry.json reads for cost)

**Mechanism description:** `telemetry.json` includes a `hybrid_attribution` block with `hidden_hybrid_cost_usd` (`Stage7.5--implementation-details.md:191`) — the marginal SoHoAI cost for flat-rate subagent tiers that OC reports as $0. This hidden cost is present in the data but octmux's `Σ$` display sums only `AssistantMessage.cost` from the OC HTTP API (`Stage8--implementation-details.md:39`), which returns $0 for SoHoAI sessions. The result: `telemetry.json` reports a non-zero `hidden_hybrid_cost_usd` while octmux displays `Σ$0.00`. The discrepancy is asymmetric — octmux never reads `telemetry.json` for cost (`Stage8--implementation-details.md:44`), and even the `session-report.py` display of this field is gated behind `--hybrid-detail` mode (`Stage7.md:366`). The operator sees one number in the TUI and a different number in the report, with no in-band indication that the TUI number is incomplete.

**References:** ST-04

---

### G-05 — Grandchild cost undercount (one-level children() only)

**Severity:** med

**Observed in:** `Stage8--implementation-details.md:60-61` (one level deep); `Stage8--implementation-details.md:312` (B1)

**Mechanism description:** octmux's `refreshTokenUsage()` calls `client.session.children()` which returns only immediate children (`Stage8--implementation-details.md:40-41`). Grandchild sessions (subagent-of-subagent) are not enumerated. The docs note this as a "documented limitation" with mitigation "acceptable for current /brain topology (Planner → Actor → Reviewer; no nesting)" (`Stage8--implementation-details.md:312`). If a future `/brain` workflow dispatches an Actor that itself dispatches a subagent (e.g., Actor-heavy), the grandchild's cost silently drops from `Σ$`. oconona's `telemetry-summarize.py` uses `get_child_sessions()` via `oc-db.py` — the depth of that query is documented as `WHERE parent_id = <brain_session_id>` (`Stage7.md:78`), which also returns only one level. However, `_compute_hybrid_attribution()` in `oc-db.py` (`Stage7.md:38` referencing v7.3.5) may recurse differently. **Unverified — operator source-audit required** to confirm whether `oc-db.py`'s child query is one-level-only or recursive.

**References:** ST-05

---

### G-06 — Session-cumulative Σ$ vs per-segment telemetry.json delta denominator mismatch

**Severity:** med

**Observed in:** `Stage8--implementation-details.md:316` (B5); `Stage8--implementation-details.md:59` (cumulative within OC session); `Stage7.5--implementation-details.md:215` (cost_usd_estimate is segment-scoped)

**Mechanism description:** octmux's `Σ$` is cumulative within the OC session — it does not reset between sequential `/brain` / `/duo` runs in the same octmux session (`Stage8--implementation-details.md:59`). oconona's `telemetry.json` `cost_usd_estimate` is per-segment: it reflects only the delta `parent_delta.cost + sum(subagent costs)` for that specific orchestra run (`Stage7.5--implementation-details.md:215`). After two `/brain` runs in one octmux session, `Σ$` shows the sum of both runs while each `telemetry.json` shows only that run's cost. The docs flag this as "different denominators" (`Stage8--implementation-details.md:316` with mitigation "Documentation only") but the operator has no in-band signal distinguishing which denominator they are looking at. The stale `telemetry.json` from a previous run may still be on disk and readable, further confusing cross-referencing.

**References:** ST-06

---

## C. Crash-safety and recovery

### G-07 — OC daemon kill mid-pipeline + delayed orphan-finalizer fire

**Severity:** med

**Observed in:** `Stage8--implementation-details.md:303` (A4); `Stage7.md:121` (orphan finalizer fires on OC Stop event)

**Mechanism description:** If the OC daemon is killed mid-`/brain` (SIGKILL, OOM), both the SSE stream and the `/brain` pipeline halt immediately. The inflight marker remains on disk. Recovery requires the OC daemon to restart, at which point the Stop-hook orphan-finalizer fires on the first OC Stop event — but "Stop" events only occur when the operator issues a turn. If the operator doesn't issue a turn (e.g., they restart the daemon and walk away), the marker persists. octmux's 24h mtime guard hides the badge after 24h (`Stage8--implementation-details.md:306`), but the session dir lingers with no telemetry until the next Stop event or the 30-day reaper. The docs call this "recoverable" (`Stage8--implementation-details.md:303`) but the recovery path depends on an operator action (issuing a turn) that may not occur promptly. No timeout or proactive cleanup trigger is documented.

**References:** ST-07

---

### G-08 — 24h marker stale-guard false-positive on legitimately long sessions

**Severity:** low

**Observed in:** `Stage8--implementation-details.md:306` (A7); `Stage7.5--implementation-details.md:57-58` (stale marker guard)

**Mechanism description:** Both octmux and the harness checklist prescribe ignoring inflight markers with `mtime > 24h` (`Stage8--implementation-details.md:306`; `Stage7.5--implementation-details.md:57`). If a `/brain` session legitimately runs longer than 24h (e.g., a long-running Research phase followed by multi-step implementation), the badge disappears at the 24h boundary while the session is still active. The operator may believe the pipeline has ended. The docs note this as "not a practical concern" (`Stage8--implementation-details.md:306`) given typical `/brain` runtimes, but no mechanism exists to extend the guard or refresh the marker mtime during legitimately long sessions. The orphan-finalizer would also eventually treat such a session as crashed (marker present without telemetry.json and with an mtime > 24h threshold).

**References:** ST-08

---

### G-09 — Snapshot fallback to `{}` and cost_source: "none" silent degradation paths

**Severity:** low

**Observed in:** `Stage7.5--implementation-details.md:219-223` (fallback paths); `Stage7.md:126` (cost_source: "none")

**Mechanism description:** When the OC SQLite DB is unavailable or `.oc-session-id` is empty, `telemetry-summarize.py` falls back to `cost = 0.0`, `cost_source: "none"` (`Stage7.md:126`). Similarly, when snapshot sidecars are `{}` or missing, `parser_warnings: snapshot_missing` is emitted and parent cost falls back to cumulative values (`Stage7.5--implementation-details.md:219-223`). Both paths are "safe" (no crash, no data corruption) but silently degrade attribution correctness. The v7.3 hotfix (`Stage7.md:639-645`) revealed that `.oc-session-id` was silently empty in every orchestra session since v7.2 (OC 1.15.11 does not export `OC_SESSION_ID`). The fallback path hid this for multiple stages — `cost_source: "none"` was written to every `telemetry.json` but no operator-visible alert surfaced. The `parser_warnings` field (v7.5) partially addresses this, but its only consumer in octmux is a ` !` indicator on completed segments (`Stage8--implementation-details.md:157`), and it requires operator attention to interpret. No proactive notification (log line, stderr warning in `/brain` output) is documented for either degradation path.

**References:** ST-09

---

## D. Session-tracking consistency

### G-10 — ORCHESTRA_TITLE global clobbering between concurrent /brain runs

**Severity:** low

**Observed in:** `Stage8--implementation-details.md:327` (C6); `Stage7.5--implementation-details.md:75` (state.env format)

**Mechanism description:** `state.env` is a global file at `~/.config/opencode/orchestra/state.env` (not per-session) containing `ORCHESTRA_TITLE=<title>` (`Stage7.5--implementation-details.md:75`). If two `/brain` sessions run concurrently on the same host (different projects), the second session's setup bash appends its title, potentially overwriting the first's. octmux reads this title for badge rendering (`Stage8--implementation-details.md:327`). The `.oc-session-id` filter prevents the wrong *session dir* from being matched, but the *title string* read from `state.env` for the correct dir may be wrong. The docs note this as "Practical risk: low — most operators run one orchestra at a time" (`Stage8--implementation-details.md:327`). However, `state.env` is also **reset at cleanup** (`Stage7.5--implementation-details.md:75` — "Reset to `ORCHESTRA_MODE=default\nORCHESTRA_TITLE=\n` at cleanup"), which means a completing `/brain` session could blank the title for a still-running concurrent session.

**Unverified — operator source-audit required:** Check whether `state.env` writes use append (`>>`) or truncate (`>`). If append, concurrent writes coexist (last line wins per key). If truncate, a setup or cleanup block overwrites the entire file.

**References:** ST-10

---

### G-11 — NFS realpath mismatch between oconona bash setup curl and octmux safeRealpath

**Severity:** low

**Observed in:** `Stage8--implementation-details.md:325` (C3); `Stage8--implementation-details.md:267-269` (safeRealpath helper); `Stage7.5--implementation-details.md:68` (.oc-session-id obtained via HTTP API curl); `Stage7.5--implementation-details.md:267-270` (why not .project-dir — NFS symlink issues)

**Mechanism description:** oconona's `/brain` setup bash resolves `.oc-session-id` via a `curl` command that filters OC sessions by `directory == $PWD` (`Stage7.5--implementation-details.md:68`, recipe at `Stage7.5--implementation-details.md:240`; actual implementation per `Stage7.md:643`). `$PWD` in bash may be a logical (symlink) path. octmux's `OrchestraWatcher` applies `safeRealpath()` to both sides of a `directory === process.cwd()` comparison (`Stage8--implementation-details.md:267-269`), resolving symlinks to realpaths. If oconona writes a logical path into the OC session (via `$PWD`) and octmux compares the resolved realpath, the comparison may fail for NFS symlinked directories. `Stage8--implementation-details.md:325` flags this as mitigated ("low (now)") via `safeRealpath()`, and `Stage7.5--implementation-details.md:267-270` explicitly deprecates `.project-dir` for this reason, but the `.oc-session-id` resolution curl in oconona setup bash still uses `$PWD` as the directory filter — the match key itself is correct (it's a UUID, not path-based), but if the curl fails to find the OC session due to a path mismatch, `.oc-session-id` is written empty, triggering the `cost_source: "none"` degradation.

**Unverified — operator source-audit required:** The actual curl command in oconona's setup bash must be inspected to confirm whether it uses `$PWD` or `$(realpath "$PWD")` as the directory filter.

**References:** ST-11

---

### G-12 — setOcSessionID() cache staleness if OC session destroyed + recreated with same UUID

**Severity:** low

**Observed in:** `Stage8--implementation-details.md:326` (C5); `Stage8--implementation-details.md:98` (resolveHarnessSessionID cache)

**Mechanism description:** `OrchestraWatcher` caches `harnessOcSessionID` and only re-resolves when `setOcSessionID()` receives a different input (`Stage8--implementation-details.md:98`: "Cache the result; re-resolve only when `setOcSessionID(id)` is called with a different ID"). If an OC session is destroyed and recreated with the same UUID (unusual but possible if the daemon resets), the cache returns the stale result. The docs note this as "Edge case unlikely in practice; OC session IDs are time-encoded UUIDs" (`Stage8--implementation-details.md:326`) with no mitigation. The practical impact is that badge filtering would still match the correct session dir (since `.oc-session-id` is the UUID and hasn't changed), but any state associated with the old session (child counts, cost) would be stale until `dispose()` + reinstantiate.

**References:** ST-12 (may be deprioritized)

---

## E. Documentation drift

### G-13 — stage vs subagent field drift in invocations.log

**Severity:** low

**Observed in:** `Stage7.5--implementation-details.md:474-482` (deprecation notice)

**Mechanism description:** The `invocations.log` format carries both `stage` (deprecated) and `subagent` (canonical) fields (`Stage7.5--implementation-details.md:476-482`). The `stage` field uses values `plan`, `implement`, `review` (orchestration phase labels); `subagent` uses `planner`, `actor`, `actor-heavy`, `reviewer` (role labels). Not all roles map to stages (e.g., Reviewer is not a stage), and multiple Actors may run per step, making `stage` ambiguous (`Stage7.5--implementation-details.md:478-479`). The deprecation notice states "Both fields present in v7.5+ for back-compat. New code must use `subagent` field. Legacy consumers reading `stage` will continue to work" (`Stage7.5--implementation-details.md:482`). However, octmux's Stage 8.2 implementation reads the `subagent` field (`Stage8.md:45`), and Stage 8.1 originally read `stage` before being superseded by SSE-based detection (`Stage8.md:51`). No consumer currently reads `stage` in production octmux code, but any third-party consumer or legacy script may still rely on it. The drift risk is that future code changes stop writing `stage` while consumers still expect it.

**Unverified — operator source-audit required:** Confirm that `orchestra-hook.sh` PreToolUse(Agent) and SubagentStop hooks still write both fields in every `invocations.log` line.

**References:** ST-13

---

### G-14 — Cross-doc pointer health: .oc-session-id multi-invocation caveat

**Severity:** low

**Observed in:** `Stage8.md:81-93` (suggested oconona-side action); `Stage7.5--implementation-details.md:247-263` (multi-invocation invariant)

**Mechanism description:** octmux's Stage 8.md explicitly requested that oconona add a documentation subsection about the `.oc-session-id` multi-invocation caveat (`Stage8.md:81-93`). oconona's `Stage7.5--implementation-details.md` now includes §Multi-invocation invariant at `Stage7.5--implementation-details.md:247-263`, which documents the invariant and cites the octmux Stage 8.2.1 fix. The requested documentation clarification is present and addresses the concern. However, the octmux `Stage8.md` feedback section (`Stage8.md:81-93`) still reads as an open request ("Suggested oconona-side action") rather than referencing the completed fix. When the octmux refactor `/brain` session consumes the oconona contract, it should update `Stage8.md` to mark this feedback item as resolved. This is a doc-hygiene gap, not a contract gap.

**References:** ST-14

---

## F. Recommendations & forward work

### Gap-to-remediation mapping

| Gap | Recommended remedy | Owner | Effort |
|---|---|---|---|
| G-01 | Amend one of the two contradicting invariants. Recommend aligning `Stage7.5--implementation-details.md` invariant 6 to match `Stage7.md` invariant 4 (telemetry before marker removal), since the actual `/brain` skill follows that order and it eliminates the no-marker-no-telemetry window. | oconona docs | Small (text edit + verify against source) |
| G-02 | Document a mutual-exclusion guarantee for the orphan-finalizer vs. cleanup block, or add a sentinel file (e.g., `.cleanup-in-progress`) that the finalizer checks. If serialization exists (same Bash context), document it explicitly. | oconona code+docs | Medium (needs source audit first) |
| G-03 | Add a pre-read guard in `telemetry-summarize.py`: if `.parent-snapshot-end` is missing/empty, wait briefly or log a clear warning beyond `parser_warnings`. | oconona code | Small |
| G-04 | Surface `hidden_hybrid_cost_usd` in octmux badge or a cost-tooltip. Alternative: add an `(!)` indicator next to `Σ$0.00` when `telemetry.json` (from a prior run) has non-zero hidden cost. | octmux code | Medium |
| G-05 | Add recursive child enumeration to `refreshTokenUsage()` (walk grandchildren) or document the undercount boundary explicitly in the `Σ$` display. | octmux code | Medium |
| G-06 | Add a label or tooltip to `Σ$` clarifying scope ("session total" vs "this run"). Alternatively, reset `Σ$` on `/brain` completion in the same OC session. | octmux code | Small–Medium |
| G-07 | Add a proactive orphan-finalizer trigger on daemon start (not just on Stop events). Or document the recovery SLA explicitly. | oconona code | Medium |
| G-08 | Add marker-mtime refresh (touch) in long-running pipelines, or make the 24h threshold configurable. | oconona code | Small |
| G-09 | Add an operator-visible warning (stderr in `/brain` output) when `telemetry-summarize.py` emits `cost_source: "none"` or `parser_warnings: snapshot_missing`. | oconona code | Small |
| G-10 | Move `ORCHESTRA_TITLE` to a per-session sidecar (e.g., `${SESSION_DIR}/.title`) instead of global `state.env`. | oconona code | Medium (refactor state.env consumers) |
| G-11 | Use `$(realpath "$PWD")` in the oconona setup curl directory filter instead of bare `$PWD`. | oconona code | Small (one-line fix) |
| G-12 | Add a `forceResolve()` method or TTL to `harnessOcSessionID` cache, or document the edge case as accepted. | octmux code | Small |
| G-13 | Verify both fields are still written; add a comment in `orchestra-hook.sh` noting the deprecation timeline. | oconona code | Small |
| G-14 | Mark the octmux `Stage8.md` feedback item as resolved once the octmux refactor cycle runs. | octmux docs | Trivial (future `/brain` session) |

### Priority order for remediation

1. **G-01** (ordering contradiction) — root cause for G-02/G-03 concerns; resolving it clarifies the crash-recovery model.
2. **G-02** (orphan-finalizer race) — potential for corrupt `.outcome` writes; needs source audit.
3. **G-04** (hidden cost display gap) — visible operator confusion; simple doc/code fix.
4. **G-06** (Σ$ scope confusion) — visible operator confusion; UX improvement.
5. **G-09** (silent degradation) — prevents future silent failures like the v7.3 `.oc-session-id` incident.
6. Remaining gaps — lower severity, can be addressed incrementally.

---

## Cross-references

| Gap | Test recipe | Topic |
|---|---|---|
| G-01 | ST-01 | Telemetry-vs-marker write-order test |
| G-02 | ST-02 | Orphan-finalizer race test |
| G-03 | ST-03 | Snapshot-sidecar write-order test (may merge with ST-01/ST-02) |
| G-04 | ST-04 | hidden_hybrid_cost_usd display gap test |
| G-05 | ST-05 | Grandchild cost undercount test |
| G-06 | ST-06 | Σ$ vs per-segment delta consistency test |
| G-07 | ST-07 | OC daemon kill mid-pipeline test |
| G-08 | ST-08 | 24h stale-guard test (via `touch -d` acceleration) |
| G-09 | ST-09 | Snapshot `{}` fallback + parser_warnings test |
| G-10 | ST-10 | ORCHESTRA_TITLE clobbering test |
| G-11 | ST-11 | NFS realpath mismatch via symlinked CWD test |
| G-12 | ST-12 | setOcSessionID cache stale test (deprioritized) |
| G-13 | ST-13 | stage vs subagent invocations.log compat test |
| G-14 | ST-14 | .oc-session-id multi-invocation caveat regression test |

**Source documents:**
- `oconona/docs/Stage7.md` — 705 lines
- `oconona/docs/Stage7.5--implementation-details.md` — 524 lines
- `octmux/docs/Stage8.md` — 94 lines
- `octmux/docs/Stage8--implementation-details.md` — 369 lines

**Companion document:** `oconona/docs/Stage7.5-stress-tests.md` (test recipes for all 14 gaps, written in Step 2)