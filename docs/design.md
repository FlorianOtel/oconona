---
title: "OpenCode Orchestra — three-tier Brain/Planner/Actor pattern over OpenCode"
created_at: 20260424-000000
created_by: OpenCode (Claude Opus 4.7, 1M context)
updated_by: Actor (Claude Haiku 4.5)
updated_at: 2026-05-29--12-37
context: >
  Reference architecture for OpenCode Orchestra — a three-tier orchestration
  pattern layered on OpenCode using native subagents. The design supports
  fully autonomous review loops and operates across multiple machines via NFS.
  This is the summary document; for implementation history and deferred items,
  see design-history.md, resources.md, and TODO.md.
---

# OpenCode Orchestra

A three-tier orchestration system for OpenCode: **Brain** (Anthropic Opus 4.7) delegates reasoning, implementation, and review across **Planner** (sohoai/glm-5.1), **Actor** (sohoai/qwen3-coder-next), and **Reviewer** (sohoai/kimi-k2.6) tiers using OpenCode's native `Task` tool for subagent dispatch. Single global install at `~/.config/opencode/`; usable from any project.

## Intro

OpenCode Orchestra solves the cost/capability trade-off for multi-step code work. A single powerful Brain (Anthropic Opus 4.7) orchestrates cheaper specialized tiers: a read-only Planner for structured reasoning, a write-capable Actor for implementation, and a read-only Reviewer for quality gates. The project name's `--non-Anthropic` suffix refers to the **worker tier** — Planner, Actor, Reviewer, and Actor-Heavy are all non-Anthropic (SoHoAI flat-rate); Brain itself runs on Anthropic Opus 4.7 because the orchestrator's job (interrogation, planning, dispatch, review judgment) benefits from Anthropic's strongest reasoning model. The key design choice: **Option B — native OpenCode subagents, not separate processes** — which keeps the architecture simple and preserves permission modes and plan-approval gates.

## Slash commands vs subagents

Two distinct kinds of `.md` file in this repo, deployed to two different OpenCode-canonical directories. Conflating them is a common source of confusion, so the distinction is stated explicitly here.

| Kind | Source | Deployed to | Invoked by | Has model/tools frontmatter? | Purpose |
|---|---|---|---|---|---|
| **Slash command** | `commands/*.md` | `~/.config/opencode/commands/` | Operator typing `/name` | No (it's a prompt template) | Operator-facing entry point; the body becomes the parent (Brain) session's prompt |
| **Subagent** | `agents/*.md` | `~/.config/opencode/agents/` | Parent calling `Task` tool with `subagent_type: name` | **Yes** — per-agent model and tool permissions | Dispatchable worker with isolated context, its own model, its own tool permissions |

**Slash commands (`commands/*.md`):** `brain.md`, `brain-abandon.md`, `duo-plan.md`, `duo-act.md`, `duo-abandon.md`. These are pipeline orchestrators — operator-facing entry points whose body becomes Brain's instructions. They are not "workers"; they coordinate work by dispatching subagents via the `Task` tool.

**Subagents (`agents/*.md`):** `planner.md` (model: `sohoai/glm-5.1`, read-only tools), `actor.md` (model: `sohoai/qwen3-coder-next`, Edit/Write/Bash), `actor-heavy.md` (model: `sohoai/kimi-k2.6`, Edit/Write/Bash), `reviewer.md` (model: `sohoai/kimi-k2.6`, read-only tools). Each has frontmatter that declares its model and tool permissions; OpenCode enforces both at dispatch time.

**Brain is neither.** Brain *is* the parent OpenCode session that executes `/brain` (or `/duo-act`). It runs on Anthropic Opus 4.7. Brain cannot be implemented as a subagent because Phase 0 of `/brain` is multi-turn interactive interrogation with the operator, and OpenCode subagents are single-dispatch units (they cannot have multi-turn dialog with the operator). The orchestration logic in `commands/brain.md` is therefore intentionally in `commands/`, not `agents/`.

**Auxiliary directory:** `agents-md-block/orchestra-guard.md` is yet a third thing — a markdown block injected by `deploy.sh` into `~/.config/opencode/AGENTS.md` between sentinels, to remind Brain about pipeline rules on every turn. Not a subagent, not a slash command — a project-instruction snippet.

Use it when you want code changes reviewed before landing, or when you want to isolate reasoning from implementation for cost control.

## How to use it

### Interactive conversation (default)

Talk to Brain normally. Brain delegates to Planner/Actor/Reviewer as needed. No forced pipeline. Example: "explain the SoHoAI routing architecture" — Brain reads files and answers directly.

### /duo — lightweight (Brain plans, Actor executes), session-bracketed

`/duo` is a three-command session-bracketed pipeline. `/duo-plan <task>` opens a planning session (sets up the session_dir, drafts an initial `PLAN.md`, and yields back). The operator then refines the plan across as many normal plan-mode turns as needed. `/duo-act` commits the plan, calls `ExitPlanMode`, dispatches Actor, and runs cleanup + telemetry. `/duo-abandon` cancels the active session cleanly. No Reviewer. Example: "add a docstring to rag_engine/search.py::search_rag" — low risk, no review needed.

Workflow: (1) Launch a OpenCode session (any model works for `/duo`; `sohoai/kimi-k2.6` recommended). (2) `Shift+Tab` to enter plan mode. (3) `/duo-plan <task>`. (4) Refine across turns until the plan is right. (5) `/duo-act` to execute (or `/duo-abandon` to cancel); on approval, `Shift+Tab` to bypassPermissions if desired, Actor runs uninterrupted.

Splitting the plan-approval gate into an explicit `/duo-act` (rather than the slash command barrelling through to `ExitPlanMode` in one response) means rejection-or-redirect during planning is now first-class: refinement is a normal multi-turn conversation, not a rejected-plan-and-informally-keep-chatting situation. Telemetry attribution stays correct because `.outcome`-file mtime bounds the T2 time window (see §Telemetry).

### /brain — full pipeline (Opus orchestrates, cap-3 review loop)

Enter plan mode, type `/brain <task>`. Opus runs Phase 0 (RESEARCH, inline — interrogates you across as many turns as needed; the operator's natural-language signal — "proceed", "go ahead" — ends Phase 0), then Phase 1 (PLAN via Planner), Phase 2 (IMPLEMENT via Actor, one step at a time), Phase 3 (REVIEW via Reviewer, loop up to 3 times). Example: "refactor the SoHoAI LiteLLM routing to support a new provider" — high-risk, multi-step, needs review loop.

`/brain-abandon` cancels the active /brain session cleanly at any point — writes `.outcome=abandoned`, removes the inflight marker, runs T2 telemetry, and clears the badge. The cleanup block also runs automatically on Phase 0 abandonment ("never mind", "drop it"), Phase 1 outright rejection at the plan-approval gate, and Phase 3 BLOCK verdict — so every exit path bounds the T2 telemetry window.

**Pipeline-rules guard (2026-05-05):** plan-mode and `/brain` give Brain conflicting instructions about who produces the plan — plan-mode's per-turn "build your plan in `~/.config/opencode/plans/<name>.md` using Write" reminder out-competed `/brain.md`'s loaded-once "dispatch Planner via Task tool" instruction in long Phase 0 sessions, causing Brain to write the plan and execute the implementation directly under Opus 4.7. Hybrid fix: (a) `commands/brain.md` reinforced with an explicit override clause, concrete `Task`-tool dispatch templates at the top of each Phase, a self-check guard, phase-boundary reinforcement, and a negative-examples block; (b) a per-turn guard block at `agents-md-block/orchestra-guard.md` injected by `deploy.sh` into `~/.config/opencode/AGENTS.md` between sentinels `<!-- ORCHESTRA_GUARD_START -->` / `<!-- ORCHESTRA_GUARD_END -->`. The AGENTS.md guard is the load-bearing component because it loads on every turn (parallel to plan-mode's reminder cadence), while `/brain.md` reinforcement makes the command body self-coherent. Cost overhead is < 5% of typical /brain session due to prompt caching of stable system-prompt content.

**`/duo-plan` setup-bash override (2026-05-06):** the same plan-mode override conflict affects `/duo-plan`'s setup phase: plan-mode's "MUST NOT run non-readonly tools" clause suppressed the refusal-check and session-dir-creation bash calls, meaning `.duo-inflight` was never written, /duo mode never activated, and the session ran as plain plan mode + direct edits. Fix: `commands/duo-plan.md` now opens with a prominent `PLAN-MODE OVERRIDE` callout at line 11, before `## When to use /duo vs /brain`, explicitly exempting the setup bash calls (lifecycle management, not code edits) from the plan-mode restriction.

When NOT to use /brain: simple tasks with ≤5 steps, low blast radius. Use /duo instead.

## How the workflow works

### Agents

| Agent | Model | File | Tools | Role |
|---|---|---|---|---|
| **Brain** | Anthropic Opus 4.7 recommended (any model permitted; advisory only) | — (main session) | all | Orchestrates; calls `ExitPlanMode` at plan approval (G2). Strictly speaking Brain is not an "agent" — it's the parent session itself; included here as the top of the tier hierarchy. |
| **Planner** | `sohoai/glm-5.1` | `~/.config/opencode/agents/planner.md` | Read, Grep, Glob, WebFetch, TodoWrite (read-only) | Decomposes task into numbered plan; Brain persists to PLAN.md |
| **Actor** | `sohoai/qwen3-coder-next` | `~/.config/opencode/agents/actor.md` | Read, Edit, Write, Bash, Grep, Glob (+ denies on rm -rf, git push) | Executes one step per invocation; self-persists TASKS.json via atomic-rename |
| **Actor** (heavy) | `sohoai/kimi-k2.6` | `~/.config/opencode/agents/actor-heavy.md` | Read, Edit, Write, Bash, Grep, Glob (+ denies on rm -rf, git push) | Complex multi-file refactors; triggered by `[tier: heavy]` step annotations |
| **Reviewer** | `sohoai/kimi-k2.6` | `~/.config/opencode/agents/reviewer.md` | Read, Grep, Glob, TodoWrite (read-only) | Reviews diff against PLAN.md; returns PASS / FIX / BLOCK |

### Model requirements

| Command | Minimum | Recommended | Enforcement |
|---|---|---|---|
| `/brain` | none | Anthropic Opus 4.7 | **Advisory only** — Brain emits a one-line notice on non-Opus models and continues. Any model is permitted. |
| `/duo` | none | sohoai/kimi-k2.6 | Advisory only — Brain warns and continues |

The check happens at command startup before any Bash or setup runs. It is LLM-enforced (Brain reads "The exact model ID is…" injected by OpenCode into every session's system context) — same trust level as the plan-mode gate.

**Why Anthropic Opus 4.7 is recommended for `/brain`.** Brain's job is multi-turn interrogation, plan reasoning over a large session context, dispatch decisions, and review judgment across the cap-3 loop. These all reward strong reasoning, and the cost is small (Brain is one session per pipeline, not per step). The pipeline subagents — Planner, Actor, Actor-Heavy, Reviewer — deliberately use non-Anthropic models because their work is per-step, narrow-context, and benefits more from the SoHoAI flat-rate economics than from incremental reasoning quality.

**Deliberate deviation from `claude-orchestra`.** The upstream `claude-orchestra` project enforces this as a hard gate (STOPs on Haiku, older Sonnet, or non-Anthropic models). `oconona` deliberately downgrades the check to advisory only — the operator's model choice is final, and any model can drive `/brain`. The recommendation is preserved (notice emitted on non-Opus) but never blocks.

### Sequential Phase Architecture & gates

| Phase | Gate before | Policy | Mechanism |
|---|---|---|---|
| 0 RESEARCH | PLAN | skip | Brain interrogates operator inline (Brain only, not separate agent) |
| 1 PLAN | IMPLEMENT | **approve (required)** | **`ExitPlanMode` called by Brain — NOT by Planner** |
| 2 IMPLEMENT | REVIEW | follow permission mode | Standard OpenCode approval UX per tool |
| 3 REVIEW | LOOP/DONE | **auto-loop, cap 3** | Brain counts; surfaces PASS/FIX/BLOCK verdict |

RESEARCH is served by Brain itself (with user input) or by built-in `Explore` subagent. No dedicated Researcher agent in v1.

### Autonomy presets

Two presets fully wired in v1; third is a stub:

| Preset | Permission mode | Review loop | When to use |
|---|---|---|---|
| `default` | default (per-edit prompts) | auto-loop cap 3 | all interactive work; user reviews each edit |
| `acceptEdits` | bypassPermissions (no prompts) | auto-loop cap 3 | low-risk tasks; full automation of edits |
| `auto` (v2 stub) | bypassPermissions | checkpoint commits + CROSS-CHECK + test gate | unattended runs; NOT implemented in v1 |

No `/orchestra-mode` command in v1 (`auto` is deferred to v2).

## Design details

### Hooks

Five hook types in `~/.config/opencode/settings.json`, dispatching to `~/.config/opencode/scripts/orchestra-hook.sh`:

1. **PreToolUse(Agent)** — `start` mode. Logs subagent invocation to invocations.log.
2. **SubagentStop** — `end` mode. Logs subagent completion.
3. **PreCompact** — `compact` mode. Saves `brain-state.md` (plan/task/decision snapshot for resumption post-`/clear`).
4. **Stop** — `stop` mode (safety net). Fires at the end of **every response turn** (not only on process exit). Walks session_dirs that have no `telemetry.json` **and** no inflight marker — i.e., sessions where cleanup already started (inflight markers removed by `/duo-act`/`/duo-abandon`/`/brain`) but `telemetry-summarize.sh` failed to write `telemetry.json`. Gate (updated 2026-05-06): skip if `.duo-inflight` or `.brain-inflight` is present (session still in-progress — removing the marker here would destroy the badge and cause `NO_SESSION` errors on the next refinement turn); then check for artefacts (`PLAN.md`, `RESEARCH.md`). Writes `.outcome=abandoned` before invoking the summariser (mtime bounds the T2 window), and resets `state.env` when finalising a /brain session so the badge clears. Inflight marker removal is the exclusive responsibility of `/duo-act`, `/duo-abandon`, and `/brain`/`/brain-abandon` cleanup.
5. (No tool-call hooks; subagent tool dispatch is opaque by design.)

### Status line

The OpenCode status line is extended by `status-line/orchestra-block.sh`, injected into `~/.config/opencode/scripts/status-line.sh` at deploy time via the `# ORCHESTRA_BLOCK_START` / `# ORCHESTRA_BLOCK_END` sentinels.

#### What it displays

The orchestra block produces a **full status line layout** (not just a badge). It replaces the OC-native progress bar and token-count fields and inserts its own fields immediately after the model name:

```
model | ctx ▓▓▓▓░░░░░░░░░░░░░░░░ 21% 210K/1M | Σ$X.YZ | ◆ project | ⎇ branch | [♪ badge]
```

Fields injected by the orchestra block:

**`ctx`** — context window utilization (always shown). Colored 20-cell bar (1 cell = 5%), percentage, and token usage. Example: `ctx ▓▓░░░░░░░░░░░░░░░░░░ 12% 24K/200K` (green). Color thresholds:
- **Green**: < 50% utilization
- **Yellow**: 50–79% utilization
- **Orange**: ≥ 80% utilization

The utilization denominator is looked up from `context-windows.yaml` per model ID, with fallback to OpenCode's native `context_window.context_window_size`. Model ID normalization strips `[1m]`, `[200k]`, and date suffixes before lookup. Models with `[1m]` in their ID force a 1,000,000 denominator.

**`Σ$X.YZ`** — accumulated running cost (always shown, including `Σ$0.00` from the very first render so the display is visibly live from session start). The `Σ` prefix marks the value as a cumulative total across the session (orchestra subagents + native residual). Source:
- **All sessions**: OC SQLite `session.cost` for the captured `OC_SESSION_ID`. See `docs/pre-Stage7--opencode-redesign.md` for the redesign rationale; v7.1–v7.3 will implement this path.

**`♪ badge`** — orchestra session badge (shown only during active /duo or /brain sessions, or when a subagent is running). Badge formats in descending priority:

| Condition | Badge |
|---|---|
| `/duo` session active (one) | `♪ orchestra -> plan <title>  [▶ stage]` |
| `/duo` sessions active (many) | `♪ orchestra -> plan #N` |
| `/brain` session active | `♪ orchestra -> brain <title>  [▶ stage]` |
| Subagent running (no /brain or /duo context) | `♪ orchestra  ▶ stage` |
| No orchestra activity | *(nothing — orchestra block is silent for badge)* |

#### When it updates

The status line script is called by OpenCode on each render tick — after every model turn and when tool calls are shown in the UI. **The active-subagent indicator (`▶ stage`) appears in real-time**: the `PreToolUse(Agent)` hook writes the `start` event to `invocations.log` *before* the Task tool executes, so the indicator is already present by the time the subagent begins running.

#### Data sources

| Signal | Source | Written by |
|---|---|---|
| `/duo` title and inflight state | `${SESSION_DIR}/.duo-inflight` | `/duo-plan` command setup |
| `/brain` title and mode | `~/.config/opencode/orchestra/state.env` (`ORCHESTRA_MODE=brain`, `ORCHESTRA_TITLE=…`) | `/brain` command setup |
| `/brain` inflight marker (session-discovery for `/brain-abandon` and explicit CMD-classification by Stop-hook) | `${SESSION_DIR}/.brain-inflight` | `/brain` command setup |
| Active subagent stage | `~/.config/opencode/orchestra/invocations.log` (last `start` event with no matching `end`) | `orchestra-hook.sh start` (PreToolUse) |
| Live cost | OC SQLite `session.cost` (via `scripts/oc-db.py`, v7.1) | OpenCode runtime |

#### Amendment 2026-05-29--07-54 — octmux status-line cost source (from octmux /brain session)

> **Context:** The following amendment was produced during a `/brain` session in the octmux repo
> (session `20260529T075453Z-2939750`) and records architectural decisions that affect the
> Data sources table above. See also `docs/Stage7.md` v7.5 amendment and octmux `docs/Stage8.md`.

The standalone-OC status line (row "Live cost" in the table above) reads cost from OC's SQLite
`session.cost` column via `scripts/oc-db.py` — a live, sub-second-accurate source. octmux cannot
use the same path for a structurally different reason: `telemetry.json` — the cross-repo contract
defined in `docs/Stage7.md` — is written only at orchestra session **cleanup**, not during the
session. This means `telemetry.json` is stale (or absent) for any active session; an octmux
aggregator that reads it would display the cost of the *previous* session rather than the live one.

The octmux `/brain` session (Stage 8) therefore chose **Option A: OC SDK direct**. `CostAggregator`
(new file `octmux/src/cost-aggregator.ts`) calls `client.session.messages({ path: { id: sessionID } })`
and sums `AssistantMessage.cost` for the active session, then calls `client.session.children()` and
accumulates per-child costs. This is symmetric with standalone-OC behaviour: both read live cost from
the same underlying data (OC's session rows), they simply use different access paths (HTTP SDK vs.
direct SQLite). For completed sessions, both paths arrive at the same dollar value. They differ only
for in-flight work, where octmux's HTTP poll is live and `telemetry.json` is stale.

Implementation details:
- **Cadence:** 5-second poll. No SSE subscription in this iteration.
- **Scope:** octmux reads cost only for the OC session it is directly attached to (the session
  established on startup). Child sessions (subagent `Task` dispatches) are enumerated one level deep
  via `client.session.children()`.
- **No `telemetry.json` reads.** octmux does not glob `~/.config/opencode/orchestra/sessions/*/telemetry.json`.
- **No `oc-db.py` coupling.** octmux is a pure HTTP API consumer; it does not link against, invoke,
  or depend on oconona's Python scripts. The two repos share only the inflight-marker filesystem
  convention and the `state.env` schema (for the orchestra badge, also in Stage 8).

**Cross-references:** `docs/Stage7.md` v7.5 amendment (2026-05-29--07-54) · octmux `docs/Stage8.md`.

#### ctx segment implementation details

The ctx segment uses `scripts/ctx-segment.sh` which reads `context-windows.yaml` from `~/.config/opencode/orchestra/`. Model ID normalisation strips `[1m]`, `[200k]`, and `-YYYYMMDD` suffixes before lookup. If the original ID contains `[1m]`, the denominator is forced to 1,000,000 regardless of the map entry.

Bar: 20 cells, each representing 5% of the context window (filled `▓`, empty `░`). Prior to 2026-05-12 the bar was 10 cells at 10% each; prior to 2026-05-11 it was 8 cells at 12.5% each.

Token formatting: values ≥ 1,000,000 show as `XM` (e.g., `1.2M`), values ≥ 1,000 show as `XK`, otherwise raw `XK`.

Model ID lookup in `context-windows.yaml` uses:
- Primary: exact `model.id` match
- Fallback: `display_name` (lowercase, hyphenated, sans parentheses)

#### Deploy / portability

`status-line/orchestra-block.sh` is a **portable standalone snippet** — it defines its own color variables so it can be dropped into any host status-line script. `deploy.sh` strips the old block and re-injects the current source whenever the two diverge, making status-line updates idempotent.

### NFS / cross-machine

All state at `~/.config/opencode/` is shared via NFS symlink (`~/.config/opencode → /mnt/nfs/Florian/Gin-AI/.claude`), so agents and config are instantly visible on all Debian hosts.

Per-project state (`PLAN.md`, `TASKS.json`, logs) lives at `${OPENCODE_PROJECT_DIR}/.opencode/orchestra/sessions/<UTC-timestamp>-<PID>/` — per-invocation isolation.

Concurrency safety via hostname + PID + timestamp stamping in log lines; atomic-rename for state files; no lock sentinel in v1.

### File inventory

**Global (~/.config/opencode/):**
```
agents/
  planner.md, actor.md, actor-heavy.md, reviewer.md
commands/
  brain.md, brain-abandon.md
  duo-plan.md, duo-act.md, duo-abandon.md
scripts/
  orchestra-hook.sh, ctx-segment.sh
orchestra/
  config.yaml, context-windows.yaml
  invocations.log (append-only)
AGENTS.md  (sentinel-bracketed orchestra-guard block injected by deploy.sh
            from agents-md-block/orchestra-guard.md in the repo)
```

**Global (~/.config/opencode/orchestra/) — shared across all projects:**
```
sessions/
  <UTC-ts>-<PID>/
    PLAN.md, TASKS.json, review-comments.md
    .duo-inflight          (present during /duo planning phase + execution; removed by /duo-act or /duo-abandon)
    .brain-inflight        (present throughout /brain Phase 0/1/2/3; removed by cleanup block or /brain-abandon)
    .project-dir           (sidecar: project_dir for attribution; written by commands at session start)
    .last-logfile          (sidecar: hook start writes logfile path; end reads+deletes)
    .outcome               (pass | block | partial | abandoned)
    telemetry.json         (per-session OC-SQLite record, written at cleanup; full shape in `docs/Stage7.md` §Cross-repo contract)
    logs/
      <stage>-<UTC-ts>-<HOST>-<PID>.log  (auto-deleted after 30 days)
native-sessions/
  native-<OC_SESSION_ID>.json      (Writer A residual tick files)
state.env          (ORCHESTRA_MODE + ORCHESTRA_TITLE, append-only)
invocations.log    (subagent start/end events, append-only)
telemetry.jsonl    (dropped in v7.1; v7.3 `session-report.py` walks `sessions/*/telemetry.json` directly)
brain-state.md     (pre-compact snapshot)
```

### Cost model — SoHoAI flat-rate

All subagents operate under a flat-rate SoHoAI subscription (marginal cost = $0 per invocation):

- **Brain** (Anthropic Opus 4.7): most expensive; receives every subagent's return. Brain is per-token Anthropic pricing (NOT flat-rate SoHoAI). Mitigated by prompt caching + `PreCompact` hook saving state. Cost dominates a typical session.
- **Planner** (sohoai/glm-5.1): called once per plan. $0 marginal cost.
- **Actor** (sohoai/qwen3-coder-next or sohoai/kimi-k2.6 if heavy): called once per step. $0 marginal cost.
- **Reviewer** (sohoai/kimi-k2.6): called once per review (up to 3 per step). $0 marginal cost.

Rule of thumb: use `/brain` for tasks where the review loop actually earns the Brain overhead (architecture, multi-file refactors). Use `/duo` for simple, low-risk tasks. The zero-marginal-cost subagents make both pipelines economically viable even with repeated review iterations.

### Disabling and troubleshooting

**Global disable**: `mv ~/.config/opencode/scripts/orchestra-hook.sh{,.bak}` (intentionally loud; next `opencode` invocation will fail visibly).

**Full uninstall**: `rm -rf ~/.config/opencode/agent/{planner,actor,actor-heavy,reviewer}.md ~/.config/opencode/command/{brain,duo}.md ~/.config/opencode/scripts/orchestra-hook.sh ~/.config/opencode/orchestra/`, then edit `~/.config/opencode/settings.json` to remove hook entries.

Quick-ref troubleshooting:

| Symptom | Likely cause | Check |
|---|---|---|
| Status-line badge doesn't appear | `config.yaml` missing or `cwd` unset in status-line input | `ls ~/.config/opencode/orchestra/config.yaml`; run `status-line.sh` manually with test JSON |
| `PLAN.md` garbled | Atomic-rename not used — direct write instead | Inspect for `.tmp` sibling; check Planner prompt |
| `/brain` command unrecognised | `~/.config/opencode/commands/brain.md` missing or malformed | `/help` lists commands; inspect file frontmatter |
| `.last-logfile.*` files accumulating in `orchestra/` | Old bug: sidecar used PID of hook process so `end` could never find and delete `start`'s file | Fixed: sidecar now lives in session dir (shared path for start and end); stale files auto-cleaned after 120 min at hook startup |
| `logs/*.log` growing unbounded | No rotation | Auto-rotated at hook startup: files older than 30 days deleted |

### Deviations from canonical OpenCode

Aligned with canonical:
- Subagent definitions (`.opencode/agent/*.md` with frontmatter)
- Hooks (`PreToolUse`, `SubagentStop`, `PreCompact`)
- Permission modes (`default` / `acceptEdits` / `plan` / `bypassPermissions`)
- Slash commands (`.opencode/command/*.md`)
- Plan approval via `ExitPlanMode`

Deliberate deviations:
- **Custom state dir `.opencode/orchestra/`** — pragmatic co-location with other OpenCode config.
- **Per-invocation subdirs** — isolation and lazy cleanup (30-day retention).
- **Atomic-rename pattern** — POSIX standard, documented in prompts, not enforced at hook level.
- **SoHoAI-routed worker models** — `sohoai/glm-5.1`, `sohoai/qwen3-coder-next`, `sohoai/kimi-k2.6` (routing stability governed by §Multi-model routing).

### Live feed limitations

Hooks fire at tool-call boundaries only. They capture *what the subagent is doing* (Edit/Write/Bash calls) but **not** *why* (thinking blocks) or *what it sees* (tool results). Full live feed would require a OpenCode streaming hook (not available in v1) or subagents running as separate `claude -p` processes (Option A, rejected in favor of simplicity).

See design-history.md §13.3 for three potential approaches to close the gap.

---

## Telemetry

### Rationale

Multi-tier orchestration has a non-obvious cost structure. Brain (Anthropic Opus 4.7) dominates by token volume — it re-sends its full context every turn (cached after the first hit, but still billed at the cache-read rate of the most expensive model) and receives all subagent returns. Planner (sohoai/glm-5.1) and Reviewer (sohoai/kimi-k2.6) are single-call-per-phase. Actor (sohoai/qwen3-coder-next) is called once per step and may iterate. Without measurement, cost/quality trade-offs are guesses: which tier to change? which phase to skip? does the built-in `Explore` subagent justify a dedicated cheaper Researcher agent? Telemetry makes those decisions data-driven (see `TODO.md §0` for the full decision-gate framework).

Every `/brain` and `/duo` run is instrumented at cleanup by `scripts/telemetry-summarize.{sh,py}`, invoked from each command's cleanup block.

**Telemetry architecture is being redesigned for Stage 7.** See `docs/pre-Stage7--opencode-redesign.md` for the rationale and `docs/Stage7.md` for the roadmap. The OC-native SQLite implementation ships in v7.1–v7.3.

### Per-tier cost interpretation

**Typical tier proportions:**

These are historical examples from the Anthropic-only era. For current non-Anthropic deployments, see the SoHoAI flat-rate cost model (§Cost model — SoHoAI flat-rate) and per-tier breakdown command (`telemetry-report.sh --tier`).

**Sample tier proportions from historical /brain sessions:**

| Session type | Brain | Planner | Actor | Reviewer |
|---|---|---|---|---|
| `/brain` | variable | ~13% | ~8% | ~13% |
| `/duo` | ~60% | — | ~40% | — |

Models: Brain (Anthropic Opus 4.7), Planner (sohoai/glm-5.1), Actor (sohoai/qwen3-coder-next, or sohoai/kimi-k2.6 for heavy steps), Reviewer (sohoai/kimi-k2.6). All subagents operate under flat-rate SoHoAI pricing (marginal cost = $0); Brain is per-token Anthropic pricing.

Brain's tier dominance is what remains **after** prompt caching has already taken ~86% off Brain's bill — the proportions in the table are post-cache. Three multipliers stack to keep Brain on top: **model rate** (Brain pays per-token Anthropic pricing; subagents run on SoHoAI flat-rate), **context size** (Brain re-sends the whole session every turn; subagents get a fresh, scoped prompt), and **turn count** (Brain runs every user message + every dispatch round-trip; subagents are one-shot). Caching only attacks the first multiplier. To shift the proportions further: trim context (`/compact`, smaller inlined artifacts) or downgrade the Brain model.

The `--tier` flag on `telemetry-report.sh` reads per-session `telemetry.json` files (located via the `session_dir` field in the global log) to produce a per-tier breakdown for each session, then a cumulative totals table across all sessions — the primary tool for answering "which tier is driving my costs overall?".

**Sample `--tier` output:**

```
  2026-05-20  brain   560s  outcome=pass  total=~$0.02
    Tier         Model                        Tokens   %tok      Cost   %cost
    -----------------------------------------------------------------------
    brain        claude-code-kimi-k2.6    1,322,163  68.5%  ~$0.0200 100.0%
    planner      claude-code-glm-5.1         92,598   4.8%  ~$0.0000   0.0%
    actor        claude-code-qwen3-coder-next 425,531  22.0%  ~$0.0000   0.0%
    reviewer     claude-code-kimi-k2.6       89,658   4.6%  ~$0.0000   0.0%
    -----------------------------------------------------------------------
    TOTAL                                 1,929,950          ~$0.0200

--- Cumulative totals (3 session(s)) ---
  Tier         Model                        Tokens   %tok        Cost   %cost
  --------------------------------------------------------------------------
  brain        claude-code-kimi-k2.6    2,009,402  69.3%    ~$0.0600 100.0%
  planner      claude-code-glm-5.1         92,598   3.2%    ~$0.0000   0.0%
  actor        claude-code-qwen3-coder-next 709,827  24.5%    ~$0.0000   0.0%
  reviewer     claude-code-kimi-k2.6       89,658   3.1%    ~$0.0000   0.0%
  --------------------------------------------------------------------------
  TOTAL                                 2,901,485          ~$0.0600
```

**Decision gates** (see `TODO.md §0` for thresholds and sample-size requirements):

1. **Researcher agent** — implement only if `Explore` dispatches account for > 15% of session cost.
2. **Planner model** — downgrade to a cheaper model only if `planner_replans` rate is low and Planner cost fraction is measurable.
3. **1-hour TTL caching** — activate per-tier when TTL-miss rate exceeds 33%.
4. **Reviewer skip** — only if FIX-verdict rate drops below 10% over ≥ 50 sessions (quality risk).
5. **Opus vs Sonnet for Brain** — compare `regret_flag` rate at different model tiers once sufficient data exists.

---

## Multi-model routing (SoHoAI graduated rollout)

### Rationale: from marginal cost to flat-rate pricing

Prior to May 2026, multi-model routing in the orchestra was rejected based on a per-token marginal cost model: switching from Sonnet to a cheaper tier would save money linearly. The analysis assumed all cost differences flowed to the operator. Under that assumption, tiering complexity was not justified.

Ollama Cloud Pro changed the equation: it operates on a **flat-rate subscription model** rather than per-token billing. This means the marginal cost of a Planner replan or an Actor redo is now zero (within the subscription cap), while the **quality risk** of using an untested model remains real. The decision matrix inverted: we now optimize for **quality and capability per subscription dollar**, not token efficiency.

Reference: [Design history & amendments](design-history.md) §Amendment 2026-05-10 — this section documents the decision; see `design-history.md` for the historical context.

### Model assignments and tier annotations

| Role | Model | Trigger |
|---|---|---|
| Planner (normal) | `sohoai/glm-5.1` | all inputs |
| Actor (default) | `sohoai/qwen3-coder-next` | all steps unless marked heavy |
| Actor (heavy) | `sohoai/kimi-k2.6` | `[tier: heavy]` annotation in PLAN.md step |
| Reviewer | `sohoai/kimi-k2.6` | all reviews (calibration + flat-rate economics) |

**Brain** is recommended on Anthropic Opus 4.7 (advisory only — any model permitted; see §Model requirements above). `/duo` is unconstrained and recommends sohoai/kimi-k2.6 advisory; any model works for `/duo`.

### Step-level tier annotations

Plan steps may be tagged with optional `[tier: …]` annotations to override tier defaults:

- `[tier: default]` — use default tier (Qwen3 for Actor, GLM-5.1 for Planner). Usually omitted.
- `[tier: heavy]` — use heavy tier (Kimi K2.6 for Actor; Sonnet stays for Planner). Used for complex multi-file refactors, architectural changes, or security-sensitive code.

Format: annotation appears on the same line as the step heading (e.g., `### 5. Refactor X [tier: heavy]`). Brain's PLAN parser confirms the annotation exists before dispatching the heavy-tier subagent; if malformed or missing, the step runs at default tier.

### Alias stability contract

OpenCode's SoHoAI provider exposes models as `sohoai/<key>` (e.g. `sohoai/glm-5.1`, `sohoai/qwen3-coder-next`, `sohoai/kimi-k2.6`) per the `provider.sohoai.models` block in `~/.config/opencode/opencode.json`. These keys are **stable across deployments** within the SoHoAI domain (as of 2026-05-11, per handoff §1). If the upstream routing changes (e.g., DeepSeek → Claude 3.7), SoHoAI commits to rotating the proxy entry, not swapping backends silently. Updates will be documented in the design-history.md amendment chain.

Without this contract, cost + quality tracking would drift silently between deployments.

### Reviewer is now Kimi K2.6

Reviewer switched from Sonnet 4.6 to `sohoai/kimi-k2.6` under the flat-rate SoHoAI model. Rationale:
- **Calibration still possible**: Sonnet 4.6 remains available as the Brain's primary model for interactive sessions. Reviewer's verdict can be cross-checked against any Sonnet-based `/duo` plans the operator runs interactively.
- **Quality under flat-rate**: Kimi K2.6 has proven reliable for code review tasks and operates on a flat-rate subscription basis (marginal cost = $0 per invocation), making the review loop economically viable even with cap-3 iteration.
- **Consistency**: Reviewer stays single-model (no multi-model routing per tier); the actor-heavy tier (also Kimi K2.6) provides operational consistency across the implementation and review stages.

### Cross-reference

- Agents table (this document, §How the workflow works): file paths and role descriptions.
- design-history.md §Amendment 2026-05-10: historical context, operator caveats, deferred follow-ups.
- TODO.md §10b–10f: deferred items (GLM-5.1 second-pass, 429 fallback, PLAN schema validator, 30 KB threshold automation, max_tokens knob).
- Handoff §1: SoHoAI alias stability contract.
- Handoff §3: max_tokens ≥ 500 requirement for reasoning models.

---

## See also

- [Design history & amendments](design-history.md) — implementation record, experimental detours, v1 validation, historical amendments
- [Resources & references](resources.md) — consulted sources, disregarded third-party claims
- [TODO & deferred items](TODO.md) — v2 stubs, optimization opportunities, open questions
