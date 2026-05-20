---
title: "Porting Plan: claude-orchestra--non-Anthropic → opencode-orchestra--non-Anthropic"
created_at: 2026-05-20--21-58
created_by: Claude Code (Claude Sonnet 4.6 1M)
context: >
  Plan for creating the opencode-orchestra--non-Anthropic project by taking the
  claude-orchestra--non-Anthropic codebase as a baseline and applying the Phase 0
  CC→OC migration changes that were implemented in opencode-orchestra. The goal is
  a fully consistent non-Anthropic variant of opencode-orchestra, preserving all
  non-Anthropic model choices, actor-heavy tier, tier annotations, and
  OPENCODE_ORCHESTRA_SESSION_DIR naming — while fixing infrastructure paths,
  variable names, and process detection to match the opencode-orchestra standard.
---

# Porting Plan: claude-orchestra--non-Anthropic → opencode-orchestra--non-Anthropic

<!-- Opus-4.7> Overall: this is the strongest of the three existing plans. It correctly identifies
     all three projects, names what to preserve from CAN, and walks file-by-file. The structure
     (Step 0 baseline → §5 file-by-file → §8 unchanged files → §9 verification → §10 change-count
     summary) is the right shape. My critique below is mostly "what was missed", not "what is wrong". -->

## 1. Context and Project Relationships

Three projects are involved:

| Project | Location | State |
|---|---|---|
| **opencode-orchestra** | `~/Gin-AI/projects/opencode-orchestra` | Reference: full Phase 0 CC→OC migration done + subsequent fixes |
| **claude-orchestra--non-Anthropic** | `~/Gin-AI/projects/claude-orchestra--non-Anthropic` | Source baseline: non-Anthropic model variant, partially migrated |
| **opencode-orchestra--non-Anthropic** | `~/Gin-AI/projects/opencode-orchestra--non-Anthropic` (this repo) | Target: currently blank (README only), to be built |

The porting work is: copy all files from `claude-orchestra--non-Anthropic` as the baseline, then apply the specific Phase 0 CC→OC infrastructure changes from `opencode-orchestra` — while keeping the non-Anthropic model choices and features that `claude-orchestra--non-Anthropic` already has (and which are better or absent in `opencode-orchestra`).

## 2. What Phase 0 Changed in opencode-orchestra

Phase 0 (commit `91c834a`, 2026-05-17) was a mechanical rename pass across the whole codebase:

- `CLAUDE=` shell var → `OC_HOME=` in `deploy.sh` / `collect.sh`
- Deploy/collect target dirs: `agents/` → `agent/`, `commands/` → `command/` (OpenCode uses singular)
- Guard injection target: `~/.opencode/CLAUDE.md` → `~/.config/opencode/AGENTS.md`
- Session ID fallback: `${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-unknown}}` → `${OC_SESSION_ID:-unknown}`
- Process detection in `bash-session-init.sh`: `"claude"` process → `"opencode"` process
- Runtime paths in Python scripts: `~/.claude/` → `~/.config/opencode/`
- Status-line runtime paths: `~/.opencode/` → `~/.config/opencode/`
- Plans path in commands: `~/.opencode/plans/` → `~/.config/opencode/plans/`
- BASH_ENV path in `AGENTS.md`: `~/.opencode/scripts/` → `~/.config/opencode/scripts/`
- New doc: `docs/architecture-decisions.md`
- Deleted doc: `docs/TODO.md`
- `.gitignore`: added `.claude/` entry
- Comment cleanup: "CC" → "OC", "Claude" → "OpenCode" in various strings

## 3. What to Preserve from claude-orchestra--non-Anthropic

These are non-Anthropic-specific features that are ABSENT or WRONG in `opencode-orchestra`
and must be kept unchanged:

| Item | Where | Reason to Preserve |
|---|---|---|
| `OPENCODE_ORCHESTRA_SESSION_DIR` | `commands/brain.md`, `commands/duo-plan.md`, all agents | Non-Anthropic renamed this further than opencode-orchestra; opencode-orchestra still has the old `CLAUDE_ORCHESTRA_SESSION_DIR` |
| Non-Anthropic model assignments | `agents/planner.md` (`claude-code-glm-5.1`), `agents/actor.md` (`claude-code-qwen3-coder-next`), `agents/reviewer.md` (`claude-code-kimi-k2.6`) | Core feature of the project |
| `agents/actor-heavy.md` | `agents/actor-heavy.md` | Unique to non-Anthropic; opencode-orchestra has no actor-heavy |
| Tier annotations in Planner | `agents/planner.md` | `[tier: fast/default/heavy]` annotation system; absent in opencode-orchestra |
| actor-heavy dispatch in Brain | `commands/brain.md` | Tier-aware dispatch using `subagent_type: actor-heavy`; absent in opencode-orchestra |
| Non-Anthropic pricing entries | `config/pricing.yaml` | `claude-code-glm-5.1`, `claude-code-qwen3-coder-next`, etc. at $0.00 |
| `.opencode/orchestra/sessions/` path | `agents-md-block/orchestra-guard.md` | Non-Anthropic correctly uses `.opencode/`; opencode-orchestra still has the wrong `.claude/` path |
| Generic actor identity text | `agents/actor.md` | "the executor model from the session system context" (model-agnostic) is better than opencode-orchestra's "Haiku 4.5" |
| Design history accuracy | `docs/design-history.md` | Non-Anthropic version is already updated to "OpenCode" throughout; opencode-orchestra still has "Claude Code" references |
| Non-Anthropic model check in brain.md | `commands/brain.md` | Simpler prerequisite check without Sonnet/Opus model requirement |
| actor-heavy collection | `collect.sh` | Collect from `~/.config/opencode/agent/actor-heavy.md` → `agents/actor-heavy.md` |

<!-- Opus-4.7> Appreciated: §3 enumerates everything to preserve, including the subtle ones
     (OPENCODE_ORCHESTRA_SESSION_DIR over OP's CLAUDE_ORCHESTRA_SESSION_DIR; the dynamic
     "executor model from session context" identity language in actor.md; the .opencode/
     orchestra/ path in orchestra-guard.md being more correct than OP's .claude/orchestra/).
     These are the exact items Plan B and Plan C both got wrong or omitted. -->

## 4. Step 0 — Establish Baseline

Copy all files from `claude-orchestra--non-Anthropic` into this repo as the starting point.
This is the foundational step; all subsequent steps modify files relative to this baseline.

```bash
# From this repo's root
rsync -av --exclude='.git' --exclude='.claude/orchestra/sessions' \
  ~/Gin-AI/projects/claude-orchestra--non-Anthropic/ .
```

<!-- Opus-4.7> Missing exclusions in the rsync command:
       --exclude='scripts/orchestra-hook.sh.orig'      (stale CC-era backup, must not ship)
       --exclude='scripts/__pycache__/'                (runtime artifact)
       --exclude='utils/codebase_snapshot.md'          (gitignored snapshot output)
     Plan B caught the .orig and __pycache__ items; Plan A missed them. Without these
     exclusions you'll copy stale code into OAN that the verification grep in §9 will then
     flag, producing noise. -->


Files to copy (git-tracked in claude-orchestra--non-Anthropic):
- `AGENTS.md`
- `README.md`
- `deploy.sh`
- `collect.sh`
- `.gitignore`
- `agents/` (all 4 files: actor.md, actor-heavy.md, planner.md, reviewer.md)
- `agents-md-block/orchestra-guard.md`
- `commands/` (all 5 files: brain.md, brain-abandon.md, duo-plan.md, duo-act.md, duo-abandon.md)
- `config/` (config.yaml, context-windows.yaml, pricing.yaml, settings-hooks.json)
- `scripts/` (all scripts)
- `status-line/orchestra-block.sh`
- `utils/snapshot_codebase.py`
- `docs/` (design.md, design-history.md, CC-to-OC-migration-plan.md, architecture/2026-04-28-headless-revert.md)

## 5. Changes to Apply (File by File)

Each section below describes what to change relative to the `claude-orchestra--non-Anthropic`
baseline. Changes are derived from the `opencode-orchestra` Phase 0 migration.

---

### 5.1 `deploy.sh`

**Scope:** Variable rename, deploy dir singular form, guard target fix.

**Changes:**

1. **Line 14** — Rename shell variable:
   ```
   CLAUDE="${HOME}/.config/opencode"
   → OC_HOME="${HOME}/.config/opencode"
   ```

2. **All `$CLAUDE/` references** — Replace with `$OC_HOME/` throughout the file.

3. **Deploy dirs** — Change all deploy target subdirs from plural to singular:
   - `$OC_HOME/agents/` → `$OC_HOME/agent/`
   - `$OC_HOME/commands/` → `$OC_HOME/command/`
   - (scripts, orchestra, config dirs stay the same)

4. **actor-heavy variant check** — Keep the `for pair in "actor:actor-heavy"` drift-check block;
   update paths inside it from `$CLAUDE/agents/` to `$OC_HOME/agent/`.

5. **Planner-long orphan cleanup** — Keep the block; update path:
   ```
   $CLAUDE/agents/planner-long.md → $OC_HOME/agent/planner-long.md
   ```

6. **`.stripped` cleanup** — Update path:
   ```
   $CLAUDE/agents/.stripped → $OC_HOME/agent/.stripped
   ```

7. **researcher orphan cleanup** — Update path:
   ```
   $CLAUDE/agents/researcher.md → $OC_HOME/agent/researcher.md
   ```

8. **CRITICAL — Guard injection target** — Replace the entire guard block target:
   ```bash
   # Before (non-Anthropic baseline):
   GLOBAL_CLAUDE_MD="$HOME/.opencode/CLAUDE.md"
   # ...
   if [ ! -f "$GLOBAL_CLAUDE_MD" ]; then
       warn "~/.config/opencode/CLAUDE.md not found ..."
   # ...all $GLOBAL_CLAUDE_MD references...

   # After:
   GLOBAL_AGENTS_MD="$OC_HOME/AGENTS.md"
   # ...
   if [ ! -f "$GLOBAL_AGENTS_MD" ]; then
       warn "~/.config/opencode/AGENTS.md not found ..."
   # ...all $GLOBAL_AGENTS_MD references...
   ```
   Also update section comment: `# ── 9. Inject orchestra-guard block into ~/.config/opencode/CLAUDE.md`
   → `# ── 9. Inject orchestra-guard block into ~/.config/opencode/AGENTS.md`

9. **Section header echo** — Update informational strings:
   - `echo "CLAUDE.md guard:"` → `echo "AGENTS.md guard:"`
   - All `ok/warn/info` messages referencing `CLAUDE.md` → `AGENTS.md`

---

### 5.2 `collect.sh`

**Scope:** Variable rename, collect dir singular form.

**Changes:**

1. **Line 14** — Rename shell variable:
   ```
   CLAUDE="${HOME}/.config/opencode"
   → OC_HOME="${HOME}/.config/opencode"
   ```

2. **All `$CLAUDE/` references** — Replace with `$OC_HOME/` throughout.

3. **Agent collect paths** — Change plural to singular:
   ```
   $OC_HOME/agents/planner.md → $OC_HOME/agent/planner.md
   $OC_HOME/agents/actor.md   → $OC_HOME/agent/actor.md
   $OC_HOME/agents/actor-heavy.md → $OC_HOME/agent/actor-heavy.md  ← KEEP (non-Anthropic specific)
   $OC_HOME/agents/reviewer.md → $OC_HOME/agent/reviewer.md
   ```

4. **Command collect paths** — Change plural to singular:
   ```
   $OC_HOME/commands/brain.md → $OC_HOME/command/brain.md
   $OC_HOME/commands/brain-abandon.md → $OC_HOME/command/brain-abandon.md
   $OC_HOME/commands/duo-plan.md → $OC_HOME/command/duo-plan.md
   $OC_HOME/commands/duo-act.md → $OC_HOME/command/duo-act.md
   $OC_HOME/commands/duo-abandon.md → $OC_HOME/command/duo-abandon.md
   ```

5. **Scripts and config paths** — Update all `$CLAUDE/...` → `$OC_HOME/...`.

---

### 5.3 `scripts/bash-session-init.sh`

**Scope:** Process name detection — functional change.

**Changes:**

1. **Comment line 2**:
   ```
   # ... sourced via BASH_ENV on every CC Bash tool call.
   → # ... sourced via BASH_ENV on every OC Bash tool call.
   ```

2. **Comment line 4**:
   ```
   # cc_pid (stable CC main process) ...
   → # cc_pid (stable OC main process) ...
   ```

3. **Comment block around line 18–20** — Change "claude process" to "opencode process":
   ```
   # Find stable CC main PID (top-level 'claude' process...)
   # Normal case: PPID is the claude process directly.
   # Ephemeral case: PPID is a transient node subprocess whose parent is claude.
   →
   # Find stable OC main PID (top-level 'opencode' process...)
   # Normal case: PPID is the opencode process directly.
   # Ephemeral case: PPID is a transient node subprocess whose parent is opencode.
   ```

4. **CRITICAL — Process detection (line 23)**:
   ```bash
   if [ "$_ppid_comm" != "claude" ]; then
   → if [ "$_ppid_comm" != "opencode" ]; then
   ```

5. **Process detection (line 26)**:
   ```bash
   [ "$_parent_comm" = "claude" ] && _cc_main_pid=$_parent
   → [ "$_parent_comm" = "opencode" ] && _cc_main_pid=$_parent
   ```

---

### 5.4 `scripts/orchestra-hook.sh`

**Scope:** Remove stale `CLAUDE_SESSION_ID` fallback; update "Claude" comments to "OpenCode".

**Changes:**

1. **Session stamp variable (line ~32)** — Remove the `CLAUDE_SESSION_ID` fallback:
   ```bash
   STAMP_SESSION="${CLAUDE_SESSION_ID:-${OC_SESSION_ID:-unknown}}"
   → STAMP_SESSION="${OC_SESSION_ID:-unknown}"
   ```

2. **Comment "never blocks Claude"** (around line 269):
   ```
   # don't have telemetry.json yet. Best-effort; never blocks Claude.
   → # don't have telemetry.json yet. Best-effort; never blocks OpenCode.
   ```

3. **Comment "multi-Claude-Code-session concurrency"** (around line 318):
   ```
   # Note: in multi-Claude-Code-session concurrency, this can clear
   → # Note: in multi-OpenCode-session concurrency, this can clear
   ```

4. **Comment "CC process has ended"** (around line 328):
   ```
   # Finalise dead native sessions (those whose CC process has ended).
   → # Finalise dead native sessions (those whose OC process has ended).
   ```

5. **Comment on pipefail line** (around line 25):
   ```
   set -uo pipefail  # NOT -e: a failing jq call must never block Claude
   → set -uo pipefail  # NOT -e: a failing jq call must never block OpenCode
   ```

6. **`TODO(Phase 3)` comment** — Verify this is already present:
   ```
   # TODO(Phase 3): drop PreCompact — replaced by session.compacted plugin event in OC
   ```
   If not present, add it after the PreCompact handler.

---

<!-- Opus-4.7> Missing: `scripts/ctx-segment.sh` line 41
       yaml_file="$HOME/.opencode/orchestra/context-windows.yaml"
                   → "$HOME/.config/opencode/orchestra/context-windows.yaml"
     This is read by status-line/orchestra-block.sh on every status refresh; leaving the
     wrong path makes ctx fallback silently return the default denominator for any model
     not in the YAML. Neither Plan B nor Plan C caught this either — Plan C lists
     ctx-segment.sh in its file list but never specifies the actual edit. -->

### 5.5 `status-line/orchestra-block.sh`

**Scope:** Runtime path fixes (`~/.opencode/` → `~/.config/opencode/`) and CC→OC comments.

**Changes:**

1. **Orchestra config check (line ~18)**:
   ```bash
   if [ -n "$cwd" ] && [ -f "$HOME/.opencode/orchestra/config.yaml" ]; then
   → if [ -n "$cwd" ] && [ -f "$HOME/.config/opencode/orchestra/config.yaml" ]; then
   ```

2. **Active sessions lck path (~line 104)**:
   ```bash
   _lck="$HOME/.opencode/active-sessions/${live_session_id}.lck"
   → _lck="$HOME/.config/opencode/active-sessions/${live_session_id}.lck"
   ```

3. **SoHoAI cache path (~line 148)**:
   ```bash
   _sohoai_cache="$HOME/.opencode/active-sessions/${live_session_id}.sohoai"
   → _sohoai_cache="$HOME/.config/opencode/active-sessions/${live_session_id}.sohoai"
   ```

4. **Subcost cache path (~line 255)**:
   ```bash
   "$HOME/.opencode/active-sessions/${live_session_id}.lck" \
   → "$HOME/.config/opencode/active-sessions/${live_session_id}.lck" \
   ```
   ```bash
   _sub_cache="$HOME/.opencode/active-sessions/${live_session_id}.subcost-cache"
   → _sub_cache="$HOME/.config/opencode/active-sessions/${live_session_id}.subcost-cache"
   ```

5. **Comment cleanups** (functional behavior unchanged):
   - `# Strip CC-native fields` → `# Strip OC-native fields`
   - `# Native session: session_id from CC JSON` → `# Native session: session_id from OC JSON`
   - `# (CC reports 0% usage...` → `# (OC reports 0% usage...`
   - `# Non-Anthropic models... CC gives no token counts` → `# ... OC gives no token counts`
   - `# CC's token counts for non-Anthropic models` → `# OC's token counts...`
   - `# Always query SoHoAI and override CC when` → `# ... override OC when`
   - `# Derive bare model name from CC model_id` → `# Derive bare model name from OC model_id`
   - `# CC's context_window_size is wrong` → `# OC's context_window_size is wrong`
   - `# Native sessions: CC provides cost.total_cost_usd` → `# Native sessions: OC provides cost...`

---

### 5.6 `scripts/session-report.py`

**Scope:** Replace all `~/.claude/` runtime paths with `~/.config/opencode/`; fix `.claude` index detection.

**Changes (all `Path.home() /` constructions):**

1. Three occurrences of `Path.home() / ".claude" / "projects"`:
   → `Path.home() / ".config" / "opencode" / "projects"`

2. `Path.home() / ".claude" / "native-sessions" / "telemetry.jsonl"`:
   → `Path.home() / ".config" / "opencode" / "native-sessions" / "telemetry.jsonl"`

3. `Path.home() / ".claude" / "orchestra" / "telemetry.jsonl"`:
   → `Path.home() / ".config" / "opencode" / "orchestra" / "telemetry.jsonl"`

4. **CRITICAL — `.claude` index detection**:
   ```python
   # Find .claude index
   if ".claude" in parts:
       idx = parts.index(".claude")
   → # Find .opencode index
   if ".opencode" in parts:
       idx = parts.index(".opencode")
   ```

5. `Path.home() / ".claude" / "active-sessions"`:
   → `Path.home() / ".config" / "opencode" / "active-sessions"`

6. `Path.home() / ".claude" / "usage-data" / "session-meta"`:
   → `Path.home() / ".config" / "opencode" / "usage-data" / "session-meta"`

7. **Comment** `"""Load sessions from ~/.config/opencode/usage-data/session-meta/*.json (legacy CC architecture)."""`:
   → `(legacy OC architecture).`

---

### 5.7 `scripts/native-session-report.py`

**Scope:** Replace all `~/.claude/` runtime paths with `~/.config/opencode/`.

**Changes (all `Path.home() /` constructions):**

1. `Path.home() / ".claude" / "orchestra" / "pricing.yaml"`:
   → `Path.home() / ".config" / "opencode" / "orchestra" / "pricing.yaml"`

2. Two occurrences of `Path.home() / ".claude" / "projects"`:
   → `Path.home() / ".config" / "opencode" / "projects"`

3. `Path.home() / ".claude" / "orchestra" / "telemetry.jsonl"`:
   → `Path.home() / ".config" / "opencode" / "orchestra" / "telemetry.jsonl"`

4. `Path.home() / ".claude" / "active-sessions"`:
   → `Path.home() / ".config" / "opencode" / "active-sessions"`

5. `Path.home() / ".claude" / "native-sessions" / "telemetry.jsonl"`:
   → `Path.home() / ".config" / "opencode" / "native-sessions" / "telemetry.jsonl"`

---

### 5.8 `scripts/native-session-finalize.py`

**Scope:** One path fix; one comment fix.

**Changes:**

1. **Help text comment**:
   ```python
   help="CC session UUID (OC_SESSION_ID) for JSONL transcript lookup",
   → help="OC session UUID (OC_SESSION_ID) for JSONL transcript lookup",
   ```

2. `Path.home() / ".claude" / "orchestra" / "telemetry.jsonl"`:
   → `Path.home() / ".config" / "opencode" / "orchestra" / "telemetry.jsonl"`

3. `Path.home() / ".claude" / "active-sessions"`:
   → `Path.home() / ".config" / "opencode" / "active-sessions"`

4. `Path.home() / ".claude" / "native-sessions"`:
   → `Path.home() / ".config" / "opencode" / "native-sessions"`

---

### 5.9 `scripts/native-subagent-cost.sh`

**Scope:** Comment only.

**Change:**
```
# native-subagent-cost.sh — sum cost of all subagent JSONLs for a native CC session.
→ # native-subagent-cost.sh — sum cost of all subagent JSONLs for a native OC session.
```

---

### 5.10 `config/context-windows.yaml`

**Scope:** Two comment-only changes.

**Changes:**
```yaml
#   model_id isn't here: CC's own context_window.context_window_size.
→ #   model_id isn't here: OC's own context_window.context_window_size.

# Fallback: CC's own context_window.context_window_size if model_id absent.
→ # Fallback: OC's own context_window.context_window_size if model_id absent.
```

---

### 5.11 `commands/brain-abandon.md`

**Scope:** Session ID fallback variable.

**Change:**
```bash
"$(cat \"<SESSION_DIR>/.transcript-uuid\" 2>/dev/null || echo \"${CLAUDE_SESSION_ID:-}\")"
→ "$(cat \"<SESSION_DIR>/.transcript-uuid\" 2>/dev/null || echo \"${OC_SESSION_ID:-}\")"
```

---

### 5.12 `commands/duo-act.md`

**Scope:** Session ID fallback variable.

**Change:**
```bash
"$(cat \"<SESSION_DIR>/.transcript-uuid\" 2>/dev/null || echo \"${CLAUDE_SESSION_ID:-}\")"
→ "$(cat \"<SESSION_DIR>/.transcript-uuid\" 2>/dev/null || echo \"${OC_SESSION_ID:-}\")"
```

Note: Do NOT import the opencode-orchestra addition of `# TODO(Phase 2): replace with /brain-plan + /brain-act split` — that annotation is specific to the Anthropic-model pipeline design.

---

### 5.13 `commands/duo-abandon.md`

**Scope:** Session ID fallback variable.

**Change:**
```bash
"$(cat \"<SESSION_DIR>/.transcript-uuid\" 2>/dev/null || echo \"${CLAUDE_SESSION_ID:-}\")"
→ "$(cat \"<SESSION_DIR>/.transcript-uuid\" 2>/dev/null || echo \"${OC_SESSION_ID:-}\")"
```

---

<!-- Opus-4.7> Appreciated: §§5.11-5.13 correctly catch every CLAUDE_SESSION_ID fallback site
     across brain-abandon, duo-act, duo-abandon. Plan B catches the orchestra-hook.sh and
     telemetry-summarize.sh sites but misses these four command files entirely. -->

### 5.14 `commands/brain.md`

**Scope:** Plans path fix; comment cleanup. Non-Anthropic model logic and
`OPENCODE_ORCHESTRA_SESSION_DIR` must be preserved.

**Changes:**

1. **Plans path override notice** (plan-mode system reminder):
   ```
   /home/florian/.opencode/plans/<name>.md
   → /home/florian/.config/opencode/plans/<name>.md
   ```

2. **Comment** "CC process PID":
   ```
   # Filename = session ID (human-readable); content = CC process PID (lookup key).
   → # Filename = session ID (human-readable); content = OC process PID (lookup key).
   ```

3. **Comment** "CC process is no longer running":
   ```
   # Housekeeping: remove lck files whose CC process is no longer running.
   → # Housekeeping: remove lck files whose OC process is no longer running.
   ```

**Do NOT change:**
- `export OPENCODE_ORCHESTRA_SESSION_DIR="${SESSION_DIR}"` — correct; opencode-orchestra
  has the wrong name `CLAUDE_ORCHESTRA_SESSION_DIR`
- Non-Anthropic tier-aware dispatch (`subagent_type: actor-heavy` for `[tier: heavy]` steps)
- Non-Anthropic prerequisites / model check
- Non-Anthropic model references

---

<!-- Opus-4.7> Also missing here in §5.14: brain.md line 399, the .outcome telemetry summarize
     call still uses ${CLAUDE_SESSION_ID:-} as the fallback in the bash heredoc. Same fix
     pattern as §§5.11-5.13. -->

### 5.15 `commands/duo-plan.md`

**Scope:** Comment cleanup; `OPENCODE_ORCHESTRA_SESSION_DIR` is already correct.

**Changes:**

1. **Comment** "CC process PID":
   ```
   # Filename = session ID (human-readable); content = CC process PID (lookup key).
   → # Filename = session ID (human-readable); content = OC process PID (lookup key).
   ```

2. **Comment** "CC process is no longer running":
   ```
   # Housekeeping: remove lck files whose CC process is no longer running.
   → # Housekeeping: remove lck files whose OC process is no longer running.
   ```

**Do NOT change:**
- `rely on ${OPENCODE_ORCHESTRA_SESSION_DIR}` — already correct

---

<!-- Opus-4.7> Missing section between 5.15 and 5.16: `agents/planner.md` line 50.
     Inside the schema description, the doc-impact rule says:
       "Scan for: root-level *.md files (CLAUDE.md, README*.md, …),
        any file referenced from CLAUDE.md's project-file inventory"
     Both CLAUDE.md occurrences must become AGENTS.md. CAN renamed the file but missed
     this internal reference; all three existing plans (A/B/C) miss this. The Planner will
     instruct Actor to scan a nonexistent CLAUDE.md if this stays. -->

### 5.16 `AGENTS.md`

**Scope:** BASH_ENV path fix; CC→OC in smoke test and telemetry flow sections.

**Changes:**

1. **BASH_ENV path** (last section, native session smoke test):
   ```
   BASH_ENV=/home/florian/.opencode/scripts/bash-session-init.sh
   → BASH_ENV=/home/florian/.config/opencode/scripts/bash-session-init.sh
   ```

2. **Active-sessions path in smoke test step 5**:
   ```
   ~/.config/opencode/active-sessions/  (already correct, check and confirm)
   ```

3. **Smoke test label** (no CC restart needed):
   ```
   ### Status-line ctx + SoHoAI cost smoke test (no CC restart needed)
   → ### Status-line ctx + SoHoAI cost smoke test (no OC restart needed)
   ```

4. **Smoke test step 1** ("Open a fresh CC session"):
   ```
   Open a fresh CC session (no /brain or /duo).
   → Open a fresh OC session (no /brain or /duo).
   ```

5. **Telemetry flow heading**:
   ```
   **Telemetry flow (CC 2.1.132):**
   → **Telemetry flow (OC 2.1.132):**
   ```

6. **Telemetry flow body** ("cc_pid (stable CC main process)"):
   ```
   with `cc_pid` (stable CC main process), `session_uuid`, `started_at`
   → with `cc_pid` (stable OC main process), `session_uuid`, `started_at`
   ```

7. **Telemetry flow body** ("OC_SESSION_ID is available"):
   ```
   - `OC_SESSION_ID` is available in Bash subprocesses but NOT in hooks
   (already correct — verify it says OC_SESSION_ID, not CLAUDE_CODE_SESSION_ID)
   ```

---

<!-- Opus-4.7> Missing in §5.16: the litellm-gateway branch-policy section (CAN's AGENTS.md
     lines 10-24) is CAN's repo workflow and may not apply to OAN, which has no
     litellm-gateway branch yet. Decision needed — delete now and re-add when OAN forks
     the branch, or rewrite to point at OAN's eventual equivalent. Plan A doesn't address
     this; Plan C mentions the policy must be preserved but doesn't decide. -->

### 5.17 `.gitignore`

**Scope:** One new entry.

**Change:** Add `.claude/` to the gitignore (OpenCode's legacy runtime dir):
```gitignore
.claude/
```

Place it alongside the existing `.opencode/` entry.

---

### 5.18 `README.md`

**Scope:** Model tier table should name models explicitly; Prerequisites link fix.

<!-- Opus-4.7> README.md needs more changes than §5.18 captures:
       Line 3:  [OpenCode](https://claude.ai/code)               → use https://opencode.ai
                (this is a SECOND broken link, in addition to the §5.18.2 line-46 fix)
       Line 54: git clone .../opencode-orchestra                 → .../opencode-orchestra--non-Anthropic
       Line 55: cd opencode-orchestra                             → cd opencode-orchestra--non-Anthropic
       Line 137: cd opencode-orchestra                            → cd opencode-orchestra--non-Anthropic
       Line 162 (ASCII tree root): opencode-orchestra/            → opencode-orchestra--non-Anthropic/
     The Install / Updating / Files sections all reference the wrong repo name. -->

**Changes:**

1. **Model tiers table** — Add model names to the Brain/Planner/Actor/Reviewer rows:

   Current (non-Anthropic baseline):
   ```markdown
   | **Brain** | Your main session — orchestrates, delegates, approves |
   | **Planner** | Decomposes tasks into numbered, reviewable plans |
   | **Actor** | Executes individual plan steps; scoped, fast, cheap |
   | **Reviewer** | Reviews Actor's output; emits PASS / FIX / BLOCK verdicts |
   ```

   Target:
   ```markdown
   | **Brain** | Your main session (`claude-code-kimi-k2.6` recommended) | — (main session) | Orchestrates, delegates, approves |
   | **Planner** | `claude-code-glm-5.1` | Sonnet fallback (`planner-long`) for large inputs | Decomposes tasks into numbered, reviewable plans |
   | **Actor** | `claude-code-qwen3-coder-next` | `claude-code-kimi-k2.6` for `[tier: heavy]` steps | Executes individual plan steps; scoped, fast, cheap |
   | **Reviewer** | `claude-code-kimi-k2.6` | — | Reviews Actor's output; emits PASS / FIX / BLOCK verdicts |
   ```

2. **Prerequisites link** — Fix wrong Claude Code link:
   ```markdown
   - [OpenCode](https://docs.anthropic.com/en/docs/claude-code)
   → - [OpenCode](https://opencode.ai)
   ```

---

<!-- Opus-4.7> Missing entirely: `utils/snapshot_codebase.py`. CAN's snapshot_codebase.py has:
       Line 29: PROJECT_ROOT = Path("/mnt/nfs/Florian/Gin-AI/projects/opencode-orchestra")
                — wrong sibling directory; will snapshot OP's tree, not OAN's. Latent bug
                in CAN that becomes a real bug in OAN.
       Line 35: "CLAUDE.md", in the snapshot file list → should be "AGENTS.md".
       Missing entry: "agents/actor-heavy.md" in the file list (CAN-specific).
       Line 47: # Claude.md injection block             → # AGENTS.md injection block.
     None of Plans A/B/C address this file's content beyond the comment cleanup. -->

### 5.19 `docs/design.md`

**Scope:** Fix CLAUDE.md → AGENTS.md guard reference; fix "CC-native" comment; fix
agent deploy paths in the agent table.

<!-- Opus-4.7> Also in design.md beyond what's listed:
       Line 243: the project file inventory still has "CLAUDE.md ..." as a tree entry
       Line 280: full-uninstall command lists agents/ (plural) and commands/ (plural) —
                 same singularization fix as 5.19.2 but applied to a different line.
       Line 522: historical paragraph mentions CLAUDE_SESSION_ID; rename to OC_SESSION_ID
                 for internal doc consistency (though this is borderline historical record). -->

**Changes:**

1. **Guard injection reference** in design explanation:
   ```
   injected by `deploy.sh` into `~/.config/opencode/CLAUDE.md`
   → injected by `deploy.sh` into `~/.config/opencode/AGENTS.md`
   ```
   And the description: "The CLAUDE.md guard is the load-bearing component"
   → "The AGENTS.md guard is the load-bearing component"

2. **Agent table paths** — `agents/` → `agent/` in the deploy path column:
   ```
   `~/.config/opencode/agents/planner.md`
   `~/.config/opencode/agents/actor.md`
   `~/.config/opencode/agents/actor-heavy.md`
   `~/.config/opencode/agents/reviewer.md`
   → `~/.config/opencode/agent/planner.md`
      etc.
   ```

3. **Status-line comment** "CC-native":
   ```
   It replaces the CC-native progress bar
   → It replaces the OC-native progress bar
   ```

4. **Denominator comment** "CC's `context_window_size`":
   ```
   Without this fix CC's `context_window_size` for non-Anthropic models
   → Without this fix OC's `context_window_size` for non-Anthropic models
   ```

---

### 5.20 `agents-md-block/orchestra-guard.md`

**Scope:** Fix plans path (BOTH opencode-orchestra and non-Anthropic have wrong paths here).

**Change:**
```
- Plan-mode's "build your plan at `/home/florian/.opencode/plans/<name>.md`"
→ - Plan-mode's "build your plan at `/home/florian/.config/opencode/plans/<name>.md`"
```

Note: This is an additional fix beyond what opencode-orchestra does (which has the even-more-wrong
`~/.claude/plans/` path). The correct OpenCode path is `~/.config/opencode/plans/`.

---

## 6. New File to Add

### `docs/architecture-decisions.md`

Create this file (present in `opencode-orchestra`, absent in `claude-orchestra--non-Anthropic`).
Adapt the opencode-orchestra version to reflect the non-Anthropic context:

```yaml
---
title: "OpenCode Orchestra (non-Anthropic) — Phase 0 Architecture Decisions"
created_at: 2026-05-20--00-00
created_by: Claude Code (Claude Sonnet 4.6 1M)
context: >
  Four architectural decisions locked as part of Phase 0 of the CC→OC migration,
  adapted for the non-Anthropic variant. These decisions govern how the
  claude-orchestra pipeline primitives map to OpenCode equivalents, with
  non-Anthropic model substitutions throughout.
---
```

Content is identical to `opencode-orchestra/docs/architecture-decisions.md` except:
- Title updated to include "(non-Anthropic)"
- Metadata updated (created_by, context)
- Decision 3 note: all traffic routes through SoHoAI's LiteLLM proxy (same as opencode-orchestra)
- Any model-specific references in the decision text updated to reflect non-Anthropic models

---

<!-- Opus-4.7> §6 (architecture-decisions.md): appreciated — the front-matter contextualization
     for "non-Anthropic variant" is correct and the note about Decision 3 being the same
     decision adapted to non-Anthropic models is precise. -->

## 7. File to Delete

### `docs/TODO.md`

This file exists in `claude-orchestra--non-Anthropic` but was intentionally deleted in
`opencode-orchestra` during Phase 0. Delete it from this project as well.

**Rationale** (from opencode-orchestra commit `91c834a`): "Delete docs/TODO.md (intentional)".
The TODO items were either completed, superseded by architecture-decisions.md, or moved to
in-code `TODO(Phase N)` annotations.

---

<!-- Opus-4.7> Missing from "files to delete":
       scripts/orchestra-hook.sh.orig  (stale CC-era backup file in CAN's scripts/)
       scripts/__pycache__/             (runtime artifact)
       utils/codebase_snapshot.md       (gitignored snapshot output)
     Plan B explicitly lists these as Phase 6. -->

<!-- Opus-4.7> Missing from "files to consider":
       docs/CC-to-OC-migration-plan.md  — CAN's version is a 120-line Kimi-authored porting
       plan that duplicates the function of the four plans (A/B/C/Opus) now in this docs/
       directory. Recommend deleting it, or renaming to docs/legacy-Kimi-porting-plan.md
       to avoid drift between five live porting plans. Plan A leaves CAN's version in
       §8 "No changes needed" — that's defensible but invites long-term confusion. -->

## 8. Files with No Changes Needed

These files are identical between the two source projects OR the non-Anthropic version is
already correct/better:

| File | Reason |
|---|---|
| `agents/planner.md` | `OPENCODE_ORCHESTRA_SESSION_DIR` already correct; tier annotations unique to non-Anthropic |
| `agents/actor.md` | `OPENCODE_ORCHESTRA_SESSION_DIR` correct; generic model-ID text better than opencode-orchestra's hardcoded "Haiku 4.5" |
| `agents/reviewer.md` | `OPENCODE_ORCHESTRA_SESSION_DIR` already correct |
| `agents/actor-heavy.md` | Unique to non-Anthropic; no equivalent in opencode-orchestra |
| `config/pricing.yaml` | Non-Anthropic entries are the key differentiator; structure unchanged |
| `config/config.yaml` | Identical between both projects |
| `config/settings-hooks.json` | Identical between both projects |
| `docs/design-history.md` | Non-Anthropic version already says "OpenCode" throughout; opencode-orchestra still has "Claude Code" residuals |
| `docs/CC-to-OC-migration-plan.md` | Keep non-Anthropic version; opencode-orchestra version is the same document at an earlier state |
| `docs/architecture/2026-04-28-headless-revert.md` | Both versions differ in metadata only (model name) |
| `scripts/session-report.sh` | Identical between both projects |
| `scripts/telemetry-report.sh` | Identical between both projects |
| `scripts/telemetry-summarize.py` | Identical between both projects |
| `scripts/telemetry-summarize.sh` | Identical between both projects |
| `scripts/smoke-test.sh` | Both projects differ only in smoke test timestamps |
| `scripts/sohoai-live-cost.sh` | Identical between both projects |
| `scripts/native-session-report.sh` | Identical between both projects |
| `scripts/otel-headers-helper.sh` | Identical between both projects |
| `utils/snapshot_codebase.py` | Identical between both projects |

---

## 9. Verification Checklist

After applying all changes, verify the following:

<!-- Opus-4.7> The Structural/Functional/Non-Anthropic/Docs split here is well-organised but
     missing the strongest single signal: a negative grep that asks "is *anything* still
     stale?". Add something like:
       grep -rn --include='*.sh' --include='*.py' --include='*.md' --include='*.yaml' \
         -e '\$CLAUDE\b' -e 'CLAUDE_SESSION_ID' -e 'CLAUDE_ORCHESTRA_SESSION_DIR' \
         -e '~/.claude/' -e '"\.claude"' -e '~/.opencode/' -e 'GLOBAL_CLAUDE_MD' .
     A clean result here catches every site you didn't think to enumerate above. -->

### Structural
- [ ] `deploy.sh --dry-run` shows all paths under `~/.config/opencode/`
- [ ] `deploy.sh` deploys agents to `~/.config/opencode/agent/` (singular)
- [ ] `deploy.sh` deploys commands to `~/.config/opencode/command/` (singular)
- [ ] `deploy.sh` injects guard into `~/.config/opencode/AGENTS.md` (not CLAUDE.md)
- [ ] `collect.sh` collects from `~/.config/opencode/agent/` and `command/` (singular)
- [ ] `actor-heavy.md` is collected and deployed (non-Anthropic specific)
- [ ] No remaining `CLAUDE=` var (should be `OC_HOME=`)
- [ ] No remaining `$CLAUDE/` path references in deploy.sh / collect.sh

### Functional
- [ ] `bash-session-init.sh` looks for "opencode" process (not "claude")
- [ ] `orchestra-hook.sh` uses `OC_SESSION_ID` only (no `CLAUDE_SESSION_ID` fallback)
- [ ] All Python scripts resolve paths under `~/.config/opencode/` (not `~/.claude/`)
- [ ] `session-report.py` detects `.opencode` in path parts (not `.claude`)
- [ ] `status-line/orchestra-block.sh` reads config from `~/.config/opencode/orchestra/`
- [ ] `status-line/orchestra-block.sh` reads active-sessions from `~/.config/opencode/active-sessions/`

### Non-Anthropic Specifics
- [ ] `agents/actor.md` still has `model: claude-code-qwen3-coder-next`
- [ ] `agents/planner.md` still has `model: claude-code-glm-5.1` and tier annotations
- [ ] `agents/reviewer.md` still has `model: claude-code-kimi-k2.6`
- [ ] `agents/actor-heavy.md` still exists with `model: claude-code-kimi-k2.6`
- [ ] `commands/brain.md` still has actor-heavy dispatch for `[tier: heavy]` steps
- [ ] All agents still use `OPENCODE_ORCHESTRA_SESSION_DIR` (not `CLAUDE_ORCHESTRA_SESSION_DIR`)
- [ ] `config/pricing.yaml` still contains non-Anthropic flat-rate ($0.00) model entries

### Docs
- [ ] `docs/architecture-decisions.md` exists
- [ ] `docs/TODO.md` is deleted
- [ ] `docs/design.md` references `AGENTS.md` (not `CLAUDE.md`) for guard injection
- [ ] `docs/design.md` agent table shows `agent/` (singular) paths
- [ ] `agents-md-block/orchestra-guard.md` references `~/.config/opencode/plans/`
- [ ] `README.md` links to `https://opencode.ai` in Prerequisites
- [ ] `README.md` model tier table has explicit non-Anthropic model names

### Deploy smoke test
```bash
cd ~/Gin-AI/projects/opencode-orchestra--non-Anthropic
./deploy.sh --dry-run
# Should show: target ~/.config/opencode/
# Should show: agent/ and command/ (singular dirs)
# Should show: AGENTS.md guard injection target
```

---

<!-- Opus-4.7> Final summary of the plan:
     STRENGTHS — most thorough of the three. Clear three-project framing, correct
     identification of OAN as the target. Excellent §3 "Preserve from CAN" table.
     Detailed line-numbered edits. Good split between structural/functional/
     non-Anthropic/docs verification.

     WEAKNESSES — missed seven concrete sites:
       1. scripts/ctx-segment.sh:41 (the path that drives status-line ctx fallback)
       2. agents/planner.md:50 (CLAUDE.md inside the doc-impact rule body)
       3. utils/snapshot_codebase.py (PROJECT_ROOT, CLAUDE.md, missing actor-heavy entry)
       4. README.md line 3 (second broken https://claude.ai/code link)
       5. README.md repo-name references (lines 54/55/137/162)
       6. Stale CAN artefacts (scripts/orchestra-hook.sh.orig, __pycache__/)
       7. CAN's docs/CC-to-OC-migration-plan.md disposition

     RECOMMENDATION — adopt as the base; merge in the missed items above. -->

## 10. Summary of Change Counts

| Category | Files Affected |
|---|---|
| Variable rename (`CLAUDE=` → `OC_HOME=`) | `deploy.sh`, `collect.sh` |
| Deploy/collect dirs (plural → singular) | `deploy.sh`, `collect.sh` |
| Guard target fix | `deploy.sh` |
| Session ID var cleanup | `orchestra-hook.sh`, `brain-abandon.md`, `duo-act.md`, `duo-abandon.md` |
| Process name fix ("claude" → "opencode") | `bash-session-init.sh` |
| Runtime paths `~/.claude/` → `~/.config/opencode/` | `session-report.py`, `native-session-report.py`, `native-session-finalize.py` |
| Runtime paths `~/.opencode/` → `~/.config/opencode/` | `status-line/orchestra-block.sh`, `AGENTS.md` |
| Plans path fix `~/.opencode/plans/` → `~/.config/opencode/plans/` | `commands/brain.md`, `agents-md-block/orchestra-guard.md` |
| Index detection `.claude` → `.opencode` | `session-report.py` |
| CC → OC comment cleanups | `bash-session-init.sh`, `orchestra-hook.sh`, `status-line/orchestra-block.sh`, `commands/brain.md`, `commands/duo-plan.md`, `AGENTS.md`, `docs/design.md`, `config/context-windows.yaml`, `scripts/native-subagent-cost.sh` |
| Agent deploy path fix (`agents/` → `agent/`) | `docs/design.md` |
| Guard file name fix (CLAUDE.md → AGENTS.md) | `docs/design.md` |
| Prerequisites link fix | `README.md` |
| Model tier table | `README.md` |
| New file | `docs/architecture-decisions.md` |
| Delete file | `docs/TODO.md` |
| Gitignore | `.gitignore` |
