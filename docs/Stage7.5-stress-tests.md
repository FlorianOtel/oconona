---
title: "Stage 7.5 — v7.5 orchestra contract: stress-test playbook"
created_at: 2026-06-04--04-15
created_by: Actor (sohoai/qwen3-4b-q6 via /brain octmux-orchestrator)
updated_by: Actor (sohoai/qwen3-4b-q6 via /brain octmux-orchestrator)
updated_at: 2026-06-04--04-15
context: >
  Operator-runnable stress-test playbook covering the v7.5 orchestra contract gaps
  identified in Stage7.5-audit.md. Each test is self-contained, paths are absolute,
  commands are copy-pasteable on this host. Tests can be run in any order; record
  pass/fail in operator notes. Companion to Stage7.5-audit.md.
---

# Stage 7.5 — v7.5 orchestra contract: stress-test playbook

## Status and scope

This playbook operationalizes the 14 gaps identified in `Stage7.5-audit.md` as concrete, operator-runnable tests. Each test validates a specific contract invariant, race condition, or edge case. Tests are designed to be executed manually by the operator on the host machine.

**Companion audit:** `oconona/docs/Stage7.5-audit.md`  
**Code base:** `oconona/` (orchestrator), `octmux/` (consumer)  
**Host:** `/home/florian/Gin-AI/projects/oconona` (primary project)

## How to use this playbook

1. **Set up the test environment:**
   - Ensure OC daemon (`opencode-server.service`) is running: `$ systemctl --user status opencode-server`
   - Have a valid `/brain` session in progress or a recent session in `~/.config/opencode/orchestra/sessions/`
   - Know your session directory: `$ cat ~/.config/opencode/orchestra/sessions/*/telemetry.json | jq '.session_id'` (for completed sessions)

2. **Run a test:**
   - Copy the test's **Setup** section verbatim into a shell and execute
   - Observe the **Trigger** action
   - Verify the **Expected** state matches
   - If mismatch, run **Fail-debug** to investigate

3. **Record results:** Create a file `~/.config/opencode/orchestra/stress-test-results.md` with entries like:
   ```
   [2026-06-04--04-15] ST-01: PASS
   [2026-06-04--04-15] ST-02: FAIL — see debug output below
   ```

4. **Report:** After all tests, share results with the operator via the octmux REPL or email.

## Conventions

- `${SESSION_DIR}` = `~/.config/opencode/orchestra/sessions/<UTC-ts>-<PID>/` (the per-invocation orchestra session dir)
- `${OC_SID}` = the OC parent session UUID (`ses_...`), e.g. from `cat ${SESSION_DIR}/.oc-session-id`
- `${PROJECT_DIR}` = `/home/florian/Gin-AI/projects/octmux` (operator's primary project)
- Badge format: `♪ orchestra -> <title> -> <mode> [-> <subagent>]` rendered by octmux StatusLine
- "OC daemon": the user systemd service `opencode-server.service` listening on port 4096
- "Run a /brain session": operator types `/brain <task>` in octmux REPL
- Commands prefixed with `$` = run as the unprivileged user in a shell (not octmux REPL)
- Commands prefixed with `> ` = type into the octmux REPL
- All paths in tests are absolute

## Tests

### ST-01 — Telemetry-vs-marker write-order
**Gap-ref:** Stage7.5-audit.md §A.1 — G-01  
**Severity under test:** med  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
if [ ! -f "${SESSION_DIR}/telemetry.json" ]; then
  echo "Setup: No telemetry.json found in ${SESSION_DIR}"
fi
echo "Session dir: ${SESSION_DIR}"
echo "Inflight marker: $(ls -la ${SESSION_DIR}/.brain-inflight 2>&1 || echo 'absent')"
echo "Telemetry exists: $(test -f ${SESSION_DIR}/telemetry.json && echo yes || echo no)"
```
**Trigger:**
1. Start a fresh `/brain` session in octmux with a short task (e.g., "echo hello")
2. Wait for the session to complete (or manually `ctrl+c` and let the cleanup run)
3. Inspect the cleanup sequence by monitoring file creation order

**Expected:**
- `.brain-inflight` marker is written FIRST (by setup)
- `.oc-session-id` is written SECOND
- `.outcome` is written THIRD (by cleanup)
- `telemetry.json` is written FOURTH (via atomic tmp+rename)
- `.brain-inflight` is removed LAST (after telemetry.json exists)
- No window exists where both `.brain-inflight` is absent AND `telemetry.json` is absent

**Pass criteria:**
- `telemetry.json` exists BEFORE `.brain-inflight` is removed
- No period exists where both are absent simultaneously

**Fail-debug:**
File: `${SESSION_DIR}` — check `ls -lt` output for write timestamps
Command: `stat -c '%Y %n' ${SESSION_DIR}/.brain-inflight ${SESSION_DIR}/telemetry.json 2>/dev/null || echo "files missing"`

**Notes:**
This test validates the ordering invariant from `Stage7.md:140` (telemetry before marker removal). If invariant 6 from `Stage7.5--implementation-details.md:377` is followed instead (marker removal before telemetry), the test will fail. The audit identifies this as a contradiction that needs resolution.

---

### ST-02 — Orphan-finalizer race with cleanup block
**Gap-ref:** Stage7.5-audit.md §A.2 — G-02  
**Severity under test:** med  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
if [ -z "${SESSION_DIR}" ]; then
  echo "Setup: No recent session dirs found"
  exit 1
fi
echo "Target session: ${SESSION_DIR}"
echo "Inflight: $(test -f ${SESSION_DIR}/.brain-inflight && echo present || echo absent)"
echo "Telemetry: $(test -f ${SESSION_DIR}/telemetry.json && echo present || echo absent)"
echo "Outcome: $(cat ${SESSION_DIR}/.outcome 2>/dev/null || echo 'absent')"
echo "Parent-snapshot-end: $(test -f ${SESSION_DIR}/.parent-snapshot-end && echo present || echo absent)"
```
**Trigger:**
1. Manually remove `.brain-inflight` marker (simulating cleanup block that ran first)
   ```bash
   rm -f ${SESSION_DIR}/.brain-inflight
   ```
2. Immediately run the orphan-finalizer by sourcing the hook script's stop mode:
   ```bash
   source ${PROJECT_DIR}/scripts/orchestra-hook.sh
   # Then invoke stop mode logic (see section below)
   ```
3. Check if `.outcome=abandoned` overwrites the cleanup block's `.outcome=pass`

**Expected:**
- If serialization exists (same Bash context): `.outcome=pass` or `.outcome=partial` (cleanup wins)
- If separate processes: `.outcome=abandoned` (orphan-finalizer wins)
- `.parent-snapshot-end` should not be overwritten

**Pass criteria:**
- Documented behavior matches expected outcome (either serialization exists OR race is real)
- No corruption occurs

**Fail-debug:**
File: `${SESSION_DIR}/.outcome` — check if it says `abandoned` when it should say `pass`
Command: Check `invocations.log` for duplicate stop events
```bash
tail -100 ~/.config/opencode/orchestra/invocations.log | grep '"event":"stop"'
```

**Notes:**
This test is **Unverified — operator source-audit required**. The `/brain` cleanup and orphan-finalizer may execute on the same Stop event in the same process cycle (serialization prevents race) or as separate invocations (hook callback vs cleanup skill). The test will reveal which model applies.

---

### ST-03 — Snapshot-sidecar write-order
**Gap-ref:** Stage7.5-audit.md §A.3 — G-03  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
echo "Session dir: ${SESSION_DIR}"
echo "Snapshot-start: $(test -f ${SESSION_DIR}/.parent-snapshot-start && echo present || echo absent)"
echo "Snapshot-end: $(test -f ${SESSION_DIR}/.parent-snapshot-end && echo present || echo absent)"
echo "Outcome: $(cat ${SESSION_DIR}/.outcome 2>/dev/null || echo 'absent')"
```
**Trigger:**
1. Start a `/brain` session with a short task
2. Let it complete normally
3. Inspect sidecar write order

**Expected:**
- `.outcome` written FIRST (cleanup)
- `.parent-snapshot-end` written SECOND (cleanup, AFTER outcome)
- `telemetry-summarize.py` invoked THIRD
- `.parent-snapshot-start` written at setup (before subagent dispatch)

**Pass criteria:**
- `.parent-snapshot-end` exists AFTER `.outcome` is written
- `telemetry.json` includes `parent_snapshot_end` field

**Fail-debug:**
File: `${SESSION_DIR}/telemetry.json` — check `parser_warnings` for `snapshot_missing`
```bash
cat ${SESSION_DIR}/telemetry.json | jq '.parser_warnings'
```

**Notes:**
This test validates invariant 5 from `Stage7.5--implementation-details.md:375`. If `telemetry-summarize.py` reads `.parent-snapshot-end` before it's written, `parser_warnings: snapshot_missing` will appear. The fallback is safe but degrades segment-delta correctness.

---

### ST-04 — hidden_hybrid_cost_usd invisibility in octmux Σ$
**Gap-ref:** Stage7.5-audit.md §B.1 — G-04  
**Severity under test:** med  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
if [ -z "${SESSION_DIR}" ]; then
  echo "Setup: No recent session dirs found"
  exit 1
fi
echo "Session dir: ${SESSION_DIR}"
echo "Telemetry exists: $(test -f ${SESSION_DIR}/telemetry.json && echo yes || echo no)"
```
**Trigger:**
1. Complete a `/brain` session (or use a completed session)
2. Read the telemetry.json
3. Compare `telemetry.json.hidden_hybrid_cost_usd` with octmux's displayed Σ$

**Expected:**
- `telemetry.json.hidden_hybrid_cost_usd` may be non-zero (e.g., 0.00003)
- octmux displays `Σ$0.00` (or similar low value)
- Discrepancy exists: telemetry shows hidden cost, octmux does not

**Pass criteria:**
- `telemetry.json` contains `hybrid_attribution.hidden_hybrid_cost_usd` field
- octmux StatusLine does NOT display this hidden cost in Σ$
- Operator sees different numbers in telemetry vs TUI

**Fail-debug:**
File: `${SESSION_DIR}/telemetry.json` — check hybrid_attribution block
Command: `cat ${SESSION_DIR}/telemetry.json | jq '.hybrid_attribution'`
File: octmux `src/cost-aggregator.ts` — verify it doesn't read `telemetry.json` for cost

**Notes:**
This is a visible operator confusion gap. `telemetry.json` reports the hidden cost but octmux's `Σ$` display sums only `AssistantMessage.cost` from the OC HTTP API, which returns $0 for SoHoAI sessions. The docs note octmux never reads `telemetry.json` for cost.

---

### ST-05 — Grandchild cost undercount
**Gap-ref:** Stage7.5-audit.md §B.2 — G-05  
**Severity under test:** med  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
echo "Session dir: ${SESSION_DIR}"
```
**Trigger:**
1. Start a `/brain` session with a nested task structure (Brain → Actor → Reviewer)
2. Let it complete
3. Check the telemetry.json subagents array depth

**Expected:**
- `telemetry.json.subagents` contains only level-1 children (Actor)
- `telemetry.json.subagents` does NOT contain level-2 children (Reviewer)
- `totals.cost_usd_estimate` undercounts by missing grandchild costs

**Pass criteria:**
- `telemetry.json.subagents` has depth ≤ 1 (no recursive enumeration)
- `refreshTokenUsage()` in octmux only queries immediate children

**Fail-debug:**
File: `${SESSION_DIR}/telemetry.json` — check subagents array length
Command: `cat ${SESSION_DIR}/telemetry.json | jq '.subagents | length'`
Command: Check octmux `src/cost-aggregator.ts` for `client.session.children()` usage

**Notes:**
This is a documented limitation in `Stage8--implementation-details.md:312`. The mitigation is "acceptable for current /brain topology (Planner → Actor → Reviewer; no nesting)". Future workflows with deeper nesting will silently undercount costs.

---

### ST-06 — Σ$ vs per-segment telemetry.json delta consistency
**Gap-ref:** Stage7.5-audit.md §B.3 — G-06  
**Severity under test:** med  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
echo "Session dir: ${SESSION_DIR}"
```
**Trigger:**
1. Start two sequential `/brain` sessions in the same octmux session
2. Let both complete
3. Compare octmux's cumulative Σ$ with individual telemetry.json `cost_usd_estimate` values

**Expected:**
- octmux `Σ$` shows sum of both runs (cumulative within OC session)
- Each `telemetry.json` shows only that run's cost (per-segment delta)
- Denominators differ: Σ$ = session total, telemetry = this run

**Pass criteria:**
- `Σ$` ≠ sum of individual `telemetry.json.cost_usd_estimate` values (they differ)
- Documentation gap exists: no in-band signal distinguishes the two

**Fail-debug:**
Command: Check octmux's Σ$ display vs telemetry files
```bash
# Find all telemetry.json files
find ~/.config/opencode/orchestra/sessions -name 'telemetry.json' -exec cat {} \; | jq -s 'add'
```

**Notes:**
Different denominators cause operator confusion. `Σ$` is cumulative within the OC session (doesn't reset between `/brain` runs), while `telemetry.json` is per-segment. The docs flag this as "different denominators" with "Documentation only" mitigation.

---

### ST-07 — OC daemon kill mid-pipeline + delayed orphan-finalizer
**Gap-ref:** Stage7.5-audit.md §C.1 — G-07  
**Severity under test:** med  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
echo "Session dir: ${SESSION_DIR}"
echo "Inflight marker: $(test -f ${SESSION_DIR}/.brain-inflight && echo present || echo absent)"
```
**Trigger:**
1. Start a `/brain` session in octmux
2. Before completion, kill the OC daemon: `$ systemctl --user stop opencode-server.service`
3. Restart the daemon: `$ systemctl --user start opencode-server.service`
4. Check if inflight marker persists without telemetry.json

**Expected:**
- `.brain-inflight` marker remains on disk (no automatic cleanup)
- `telemetry.json` is absent (daemon killed before cleanup)
- Orphan-finalizer does NOT fire immediately (needs Stop event)
- Badge disappears after 24h (stale-marker guard)

**Pass criteria:**
- Marker persists after daemon kill (crash orphan)
- No automatic telemetry write occurs
- Recovery requires operator action (issuing a turn) or 24h stale-guard

**Fail-debug:**
Command: Find orphaned markers
```bash
find ~/.config/opencode/orchestra/sessions -name '.brain-inflight' -mtime +1
```
Command: Check `invocations.log` for stop events
```bash
tail -100 ~/.config/opencode/orchestra/invocations.log | grep '"event":"stop"'
```

**Notes:**
Recovery is "operator-dependent". The Stop-hook orphan-finalizer fires on every OC session Stop event, but "Stop" events only occur when the operator issues a turn. If the operator doesn't issue a turn after restarting the daemon, the marker persists until 24h or the 30-day reaper.

---

### ST-08 — 24h stale-guard false-positive
**Gap-ref:** Stage7.5-audit.md §C.2 — G-08  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
if [ -z "${SESSION_DIR}" ]; then
  echo "Setup: No recent session dirs found"
  exit 1
fi
echo "Session dir: ${SESSION_DIR}"
echo "Marker mtime: $(stat -c '%y' ${SESSION_DIR}/.brain-inflight 2>/dev/null || echo 'absent')"
```
**Trigger:**
1. Start a `/brain` session
2. Wait 24 hours (or use `touch -d` acceleration)
3. Check if badge disappears

**Expected (with acceleration):**
- Use `touch -d` to simulate 24h marker aging
- Badge disappears after marker mtime > 24h
- Session may still be active but appears stale

**Pass criteria:**
- Inflight marker with mtime > 24h is treated as stale/crashed
- Badge disappears or becomes hidden

**Fail-debug:**
Command: Check marker age
```bash
stat -c '%y %n' ${SESSION_DIR}/.brain-inflight
```

**Notes:**
This is "not a practical concern" per `Stage8--implementation-details.md:306` given typical `/brain` runtimes. However, legitimately long sessions (e.g., multi-day research) would be incorrectly marked as abandoned. The orphan-finalizer would also treat such sessions as crashed.

---

### ST-09 — Snapshot fallback + parser_warnings + cost_source: "none"
**Gap-ref:** Stage7.5-audit.md §C.3 — G-09  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
echo "Session dir: ${SESSION_DIR}"
```
**Trigger:**
1. Delete `.parent-snapshot-start` and `.parent-snapshot-end` sidecars
2. Complete a `/brain` session (or use existing session)
3. Check telemetry.json for fallback behavior

**Expected:**
- `telemetry.json.parser_warnings` includes `{"code": "snapshot_missing", ...}`
- `cost_source: "none"` or `cost_source: "oc_sqlite"` with fallback values
- `parent.cost` contains cumulative values (not segment-delta)
- No crash, but attribution degrades silently

**Pass criteria:**
- `parser_warnings` array is non-empty with `snapshot_missing` code
- `cost_source` reflects fallback state

**Fail-debug:**
File: `${SESSION_DIR}/telemetry.json` — check parser_warnings and cost_source
```bash
cat ${SESSION_DIR}/telemetry.json | jq '{parser_warnings, cost_source, parent: .parent}'
```

**Notes:**
The v7.3 hotfix revealed `.oc-session-id` was silently empty since v7.2 (OC 1.15.11 doesn't export `OC_SESSION_ID`). This fallback path hid the issue for multiple stages. `parser_warnings` was introduced in v7.5 to surface this, but octmux only shows a `!` indicator on completed segments.

---

### ST-10 — ORCHESTRA_TITLE global clobbering
**Gap-ref:** Stage7.5-audit.md §D.1 — G-10  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
echo "Initial state.env content:"
cat ~/.config/opencode/orchestra/state.env 2>/dev/null || echo "file absent"
```
**Trigger:**
1. Start two concurrent `/brain` sessions (simulated by writing to state.env)
2. First: `echo 'ORCHESTRA_TITLE=first session' >> ~/.config/opencode/orchestra/state.env`
3. Second: `echo 'ORCHESTRA_TITLE=second session' >> ~/.config/opencode/orchestra/state.env`
4. Check which title is read by octmux

**Expected:**
- `state.env` is append-only (multiple entries)
- Last write wins per key (ORCHESTRA_TITLE)
- Concurrent sessions may see wrong title

**Pass criteria:**
- `state.env` writes use append (`>>`), not truncate (`>`)
- Last session's title clobbers first session's title

**Fail-debug:**
File: `~/.config/opencode/orchestra/state.env` — check if multiple titles exist
Command: `cat ~/.config/opencode/orchestra/state.env | grep ORCHESTRA_TITLE`

**Notes:**
`state.env` is a global file, not per-session. If two `/brain` sessions run concurrently, the second session's title overwrites the first. The `.oc-session-id` filter prevents wrong session dir matching, but the title string may be wrong. The docs note this as "Practical risk: low — most operators run one orchestra at a time".

---

### ST-11 — NFS realpath mismatch via symlinked CWD
**Gap-ref:** Stage7.5-audit.md §D.2 — G-11  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
PROJECT_DIR="/home/florian/Gin-AI/projects/octmux"
echo "PROJECT_DIR: ${PROJECT_DIR}"
echo "Realpath: $(realpath ${PROJECT_DIR})"
echo "PWD: $(pwd)"
```
**Trigger:**
1. Create a symlinked CWD pointing to the project
   ```bash
   ln -sf /home/florian/Gin-AI/projects/octmux /mnt/opencode/cwd
   cd /mnt/opencode/cwd
   echo "New PWD: $(pwd)"
   echo "Realpath: $(realpath $(pwd))"
   ```
2. Attempt to resolve `.oc-session-id` via the curl command pattern
3. Compare logical vs real path resolution

**Expected:**
- `$PWD` (symlink path) ≠ `realpath $PWD` (resolved path)
- OC API directory filter using `$PWD` may fail to match
- `.oc-session-id` may be empty, triggering `cost_source: "none"`

**Pass criteria:**
- Symlinked CWD has different realpath than `$PWD`
- Path mismatch could cause `.oc-session-id` resolution failure

**Fail-debug:**
Command: Check if curl-based resolution would fail
```bash
# Simulate the oconona setup curl pattern
curl -s "http://localhost:4096/session" "directory=/home/florian/Gin-AI/projects/octmux" | jq '.[].id'
# vs
curl -s "http://localhost:4096/session" "directory=/mnt/opencode/cwd" | jq '.[].id'
```

**Notes:**
This is "low (now)" via `safeRealpath()` in octmux, but the oconona setup bash still uses `$PWD` as the directory filter in the curl command. If the curl fails to find the session due to path mismatch, `.oc-session-id` is empty, triggering the `cost_source: "none"` degradation path.

---

### ST-12 — setOcSessionID() cache staleness
**Gap-ref:** Stage7.5-audit.md §D.3 — G-12  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
echo "Testing cache staleness scenario..."
```
**Trigger:**
1. Simulate cache by checking if stale `.oc-session-id` persists
2. Verify octmux's `OrchestraWatcher` cache behavior

**Expected:**
- Cache returns stale result if input ID unchanged
- Badge filtering still matches correct session dir (UUID hasn't changed)
- State (child counts, cost) stale until `dispose()` + reinstantiate

**Pass criteria:**
- Cache behavior matches documented edge case
- No functional impact on badge filtering (UUID-based match works)

**Fail-debug:**
Command: Check octmux cache implementation
```bash
# Would need to inspect octmux source code
grep -n "harnessOcSessionID" octmux/src/orchestra-watch.ts
```

**Notes:**
This is an "Edge case unlikely in practice" — OC session IDs are time-encoded UUIDs, so recreation with same ID is rare. The fix would be to add a `forceResolve()` method or TTL to the cache, or document this as an accepted edge case.

---

### ST-13 — stage vs subagent field drift
**Gap-ref:** Stage7.5-audit.md §E.1 — G-13  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
echo "Session dir: ${SESSION_DIR}"
```
**Trigger:**
1. Check `invocations.log` for both `stage` and `subagent` fields
2. Verify both fields are present in v7.5+

**Expected:**
- `invocations.log` lines contain both `stage` and `subagent` fields
- `stage` values: `plan`, `implement`, `review` (deprecated)
- `subagent` values: `planner`, `actor`, `actor-heavy`, `reviewer` (canonical)

**Pass criteria:**
- Both fields present in every `invocations.log` entry
- `subagent` field is used by new code; `stage` is deprecated

**Fail-debug:**
File: `~/.config/opencode/orchestra/invocations.log` — check field presence
```bash
tail -20 ~/.config/opencode/orchestra/invocations.log | jq '.[] | {stage, subagent}'
```

**Notes:**
The `stage` field uses orchestration phase labels; `subagent` uses role labels. Not all roles map to stages (Reviewer is not a stage). Both fields are present in v7.5+ for back-compat. New code must use `subagent`.

---

### ST-14 — .oc-session-id multi-invocation regression
**Gap-ref:** Stage7.5-audit.md §E.2 — G-14  
**Severity under test:** low  
**Setup:**
```bash
#!/bin/bash
set -e
SESSION_DIR1="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -1)"
SESSION_DIR2="/home/florian/Gin-AI/projects/oconona/.config/opencode/orchestra/sessions/$(ls -t . | head -2 | tail -1)"
echo "Session dir 1: ${SESSION_DIR1}"
echo "Session dir 2: ${SESSION_DIR2}"
```
**Trigger:**
1. Check `.oc-session-id` in both session dirs
2. Verify they are identical (same OC session)
3. Verify octmux correctly identifies only live/inflight sessions

**Expected:**
- Both session dirs have identical `.oc-session-id` (same OC session)
- Octmux badge count correctly reflects only inflight sessions
- Completed session dirs don't inflate the count

**Pass criteria:**
- `.oc-session-id` matches across multiple session dirs in same OC session
- Badge count uses inflight marker intersection (not raw `.oc-session-id` match)

**Fail-debug:**
Command: Check octmux matchedSessionCount implementation
```bash
grep -A5 "matchedSessionCount" octmux/src/orchestra-watch.ts
```

**Notes:**
This is the Stage 8.2.1 regression test. The `.oc-session-id` match key alone is not sufficient — it identifies any dir created during the OC session, whether active or completed. The fix tracks `dirHasInflight` per loop iteration and only increments the count when an inflight marker is found.

---

## Appendix: shared debug commands

These commands are useful across multiple tests to inspect session state and debug issues.

1. **List all session directories with metadata:**
   ```bash
   $ ls -lt ~/.config/opencode/orchestra/sessions/
   ```

2. **Inspect telemetry.json with jq:**
   ```bash
   $ cat ~/.config/opencode/orchestra/sessions/<SESSION_DIR>/telemetry.json | jq '.'
   ```

3. **Query OC SQLite database for session details:**
   ```bash
   $ sqlite3 -readonly ~/.local/share/opencode/opencode.db \
     "SELECT id, cost, tokens_input, tokens_output, parent_id, time_archived \
      FROM session WHERE id='${OC_SID}'"
   ```

4. **Find orphaned inflight markers (stale > 24h):**
   ```bash
   $ find ~/.config/opencode/orchestra/sessions -name '.brain-inflight' -mtime +1
   ```

5. **Find temporary files:**
   ```bash
   $ find ~/.config/opencode/orchestra/sessions -name '*.tmp'
   ```

6. **Check invocations.log for telemetry events:**
   ```bash
   $ tail -20 ~/.config/opencode/orchestra/invocations.log
   ```

7. **Check OC daemon status:**
   ```bash
   $ systemctl --user status opencode-server
   ```

8. **Inspect snapshot sidecars:**
   ```bash
   $ cat ~/.config/opencode/orchestra/sessions/<SESSION_DIR>/telemetry.json | jq '.parent_snapshot_start, .parent_snapshot_end, parser_warnings'
   ```

---

## Test summary

| Test | Gap | Severity | Status |
|------|-----|----------|--------|
| ST-01 | G-01 | med | pending |
| ST-02 | G-02 | med | pending |
| ST-03 | G-03 | low | pending |
| ST-04 | G-04 | med | pending |
| ST-05 | G-05 | med | pending |
| ST-06 | G-06 | med | pending |
| ST-07 | G-07 | med | pending |
| ST-08 | G-08 | low | pending |
| ST-09 | G-09 | low | pending |
| ST-10 | G-10 | low | pending |
| ST-11 | G-11 | low | pending |
| ST-12 | G-12 | low | pending |
| ST-13 | G-13 | low | pending |
| ST-14 | G-14 | low | pending |

**Total tests:** 14  
**Gaps covered:** 14 (G-01 through G-14)

---

*Last updated: 2026-06-04--04-15 by Actor (sohoai/qwen3-4b-q6 via /brain octmux-orchestrator)*
