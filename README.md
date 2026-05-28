# oconona (OpenCode Orchestra non-Anthropic)

A three-tier orchestration layer for [OpenCode](https://opencode.ai) that routes tasks across model tiers by complexity, adds a structured PLAN → IMPLEMENT → REVIEW pipeline, and provides live visibility into each tier's work via tmux windows. Designed to be as idiomatic as possible and work identically in both terminal (tmux) and VSCode OpenCode extension environments.

## Model tiers

| Tier | Model | Fallback | Role |
|---|---|---|---|
| **Brain** | Your main session, **Anthropic Opus 4.7 recommended** (any model permitted) | — (main session) | Orchestrates, delegates, approves |
| **Planner** | `claude-code-glm-5.1` | — | Decomposes tasks into numbered, reviewable plans |
| **Actor** | `claude-code-qwen3-coder-next` | `claude-code-kimi-k2.6` for `[tier: heavy]` steps | Executes individual plan steps; scoped, fast, cheap |
| **Reviewer** | `claude-code-kimi-k2.6` | — | Reviews Actor's output; emits PASS / FIX / BLOCK verdicts |

The project name's "non-Anthropic" refers to the **worker tier** (Planner / Actor / Reviewer / Actor-Heavy). Brain itself runs on Anthropic Opus 4.7 — the orchestrator's job (multi-turn interrogation, plan reasoning, dispatch decisions, review judgment) benefits from Anthropic's strongest reasoning model. The non-Anthropic workers are where the cost savings come from.

## Slash commands vs subagents

Two distinct kinds of `.md` file in this repo, deployed to two different canonical OpenCode directories — easy to conflate, important to keep separate:

| Kind | Source | Deployed to | Invoked by | Purpose |
|---|---|---|---|---|
| **Slash command** | `commands/*.md` | `~/.config/opencode/commands/` | Operator typing `/name` | Operator-facing entry point; the body becomes Brain's prompt |
| **Subagent** | `agents/*.md` | `~/.config/opencode/agents/` | Parent calling the `Task` tool with `subagent_type: name` | Dispatchable worker with isolated context, its own model, its own tool permissions |

`/brain`, `/duo-plan`, `/duo-act`, `/duo-abandon`, `/brain-abandon` are **slash commands** — operator-facing pipeline orchestrators. They dispatch the agents; they are not workers themselves.

`planner`, `actor`, `actor-heavy`, `reviewer` are **subagents** — each has frontmatter declaring its model (different per tier) and its tool permissions (Planner & Reviewer read-only; Actor has Edit/Write/Bash).

**Brain is neither.** Brain *is* the parent OpenCode session that ran `/brain`. It cannot be implemented as a subagent because Phase 0 of `/brain` is multi-turn interactive interrogation with the operator, and OpenCode subagents are single-dispatch (no back-and-forth with the operator).

## Pipelines

Two invocation styles depending on how much structure the task warrants:

### `/brain` — full pipeline

```
PLAN → [G2 approval] → IMPLEMENT + REVIEW loop (cap 3) → VERIFY + doc/memory update
```

Planner drafts a numbered plan; Brain surfaces it for your approval via `ExitPlanMode`; Actor executes each step; Reviewer reviews each step with up to 3 fix iterations; Brain does a doc-delta check and memory update on completion.

Use for: multi-file refactors, architecture changes, anything where a review loop matters.

### `/duo-plan` / `/duo-act` / `/duo-abandon` — lightweight, session-bracketed

```
/duo-plan <task>  →  refinement turns (multi-turn plan-mode iteration)  →  /duo-act
                                                                           ├→ [G2 approval]
                                                                           └→ Execute all steps (Actor, auto)
                                                                           or
                                                                           /duo-abandon → cancel cleanly
```

`/duo-plan` opens a planning session (sets up artifacts, drafts the initial `PLAN.md`, then yields back). You refine the plan across as many turns as needed using OpenCode's native plan-mode iteration. `/duo-act` calls `ExitPlanMode`, dispatches Actor subagent to execute all approved steps in a single Actor invocation, then runs cleanup + telemetry. `/duo-abandon` cancels the session cleanly (writes `.outcome=abandoned`, runs T2, clears the badge). No review tier, no loop.

Splitting plan-approval into an explicit `/duo-act` (rather than barrelling through `ExitPlanMode` in one response) makes mid-plan refinement first-class and keeps telemetry attribution correct.

Use for: simple, well-scoped tasks (≤ 10 steps) where the plan is clear enough to trust unreviewed execution.

## Prerequisites

- [OpenCode](https://docs.anthropic.com/en/docs/claude-code) installed and configured
- `jq` (for the deploy script and hook JSON parsing)
- `tmux` (optional — for per-stage windows; falls back to logfile-only without it)
- `bash` 5+

## Install

```bash
git clone https://github.com/FlorianOtel/opencode-orchestra--non-Anthropic
cd opencode-orchestra--non-Anthropic
./deploy.sh
```

`deploy.sh` is idempotent — safe to re-run after any change in the repo.

```bash
./deploy.sh            # install / update to ~/.config/opencode/
./deploy.sh --dry-run  # preview what would change without writing
./deploy.sh --diff     # show unified diff of every file that would change
```

It copies `agents/`, `commands/`, `scripts/`, and `config/` to `~/.config/opencode/`, then:

1. Merges orchestra hooks (`PreToolUse → Agent`, `SubagentStop`, `PreCompact`) into `~/.config/opencode/settings.json` without touching existing entries
2. Patches `~/.config/opencode/scripts/status-line.sh` to add orchestra state indicators (if you have one; skipped otherwise)
3. Adds `.opencode/orchestra/` to your global gitignore so per-project runtime state is never accidentally committed

## Development workflow (dogfooding)

Source files live in `agents/` and `commands/` at the repo root. OpenCode running
in this directory has **no** project-level agents or commands — it uses `~/.config/opencode/`
exclusively. Deploying to the local project is a conscious, explicit step, not automatic.

```
opencode-orchestra--non-Anthropic/ (agents/, commands/, scripts/, config/)   ← edit source here
        │
        │  ./deploy.sh   (explicit step — nothing deploys automatically)
        ▼
~/.config/opencode/  (agents, commands, hook, config — shared NFS, all machines)
```

```bash
# Typical development cycle:
# 1. Edit agents/planner.md, commands/brain.md, etc.
# 2. Commit
git add agents/ commands/ && git commit -m "..."
# 3. Deploy
./deploy.sh
# 4. Push
git push
```

**No silent shadowing.** Working in this repo does not activate any dev version of
the orchestra automatically. Changes only take effect after an explicit deploy.

## Usage

```
# 1. Enter plan mode (required for G2 approval gate)
Shift+Tab   (or /plan-mode in OpenCode)

# 2. Choose a pipeline
/brain        implement the X feature       — full pipeline
/duo-plan    add a docstring to function Y — open a lightweight session (multi-turn refinement)
/duo-act                                   — commit the plan and execute (after refining)
/duo-abandon                                — cancel the active session
```

Orchestra is globally on once installed — no per-project setup needed. Each project's runtime state (PLAN.md, TASKS.json, logs) is written to `~/.config/opencode/orchestra/` and is globally gitignored.

## Status line

If you use a custom `status-line.sh`, `deploy.sh` appends orchestra indicators automatically. If you don't, the block is available standalone at `status-line/orchestra-block.sh`.

Status line shows (when orchestra is installed):

```
✦ Sonnet 4.6 | [bar] 10% | ↯ 100k/1000k | ◆ MyProject | ⎇ main | ♪ default
                                                                  ▲
                                                          orchestra badge

♪ orchestra -> plan <title>       — /duo-plan session active, planning in progress
♪ orchestra -> plan <title> ▶ implement   — /duo-act has dispatched Actor
♪ orchestra -> brain <title> ⚠ >200K       — Brain context too large to delegate safely
```

## Updating

After iterating on files directly in `~/.config/opencode/`:

```bash
cd opencode-orchestra
./collect.sh        # sync live files back to repo
git diff            # review
git add -p          # stage selectively
git commit -m '...'
git push
```

After pulling new changes from the repo:

```bash
./deploy.sh
```

## Cross-machine deployment

If `~/.config/opencode/` is shared across machines (e.g. via an NFS-mounted home directory or a symlinked dotfiles store), installed files are immediately available everywhere with no further action. On any machine where `~/.config/opencode/` is local, run `./deploy.sh` to install from the repo.

## Files

`.opencode/` is entirely runtime (gitignored). Source files live at the repo root
and are deployed explicitly — no automatic shadowing.

```
opencode-orchestra--non-Anthropic/
├── agents/
│   ├── planner.md         — writes numbered plan to PLAN.md
│   ├── actor.md           — executes one scoped step
│   ├── actor-heavy.md     — heavy-tier actor (complex refactors, algorithmic work)
│   └── reviewer.md        — reviews diff, emits PASS/FIX/BLOCK
├── commands/
│   ├── brain.md           /brain slash command           — full pipeline (Phase 0 inline + Planner/Actor/Reviewer subagents)
│   ├── brain-abandon.md   /brain-abandon slash command   — cancel the active /brain session, run cleanup + telemetry
│   ├── duo-plan.md       /duo-plan slash command       — open a /duo planning session (multi-turn refinement)
│   ├── duo-act.md        /duo-act slash command        — commit the plan, ExitPlanMode, dispatch Actor, cleanup
│   └── duo-abandon.md     /duo-abandon slash command     — cancel the active /duo session, run cleanup + telemetry
├── scripts/
│   └── orchestra-hook.sh      PreToolUse / SubagentStop / PreCompact hook dispatcher
├── status-line/
│   └── orchestra-block.sh     Orchestra additions for status-line.sh
├── config/
│   ├── config.yaml            Global orchestra configuration
│   ├── context-windows.yaml   Model context window sizes (denominator for status-line ctx bar)
│   ├── pricing.yaml           Non-Anthropic model pricing (SoHoAI, Ollama)
│   └── settings-hooks.json    Hook entries to merge into settings.json
├── docs/
│   ├── design.md              Full design reference (architecture, decisions, TO DOs)
│   ├── design-history.md      Design session notes and change log
│   ├── architecture-decisions.md     Phase 0 architecture decisions (inherited from opencode-orchestra)
│   └── resources.md           Implementation reference and deployment checklist
├── deploy.sh                  Install / update to ~/.config/opencode/
└── collect.sh                 Sync changes from ~/.config/opencode/ back to repo
```

## Architecture

Full architecture, gate policy (G1–G7), autonomy presets (`default` / `acceptEdits` / `auto`), NFS/cross-machine concurrency notes, tmux window naming, and v2 auto-mode spec are in [docs/design.md](docs/design.md).

## v2 roadmap

`/brain --mode auto` (fully unattended PLAN → IMPLEMENT → REVIEW → CROSS-CHECK → FINALIZE) is documented but not yet implemented. See the TO DO section at the end of [docs/design.md](docs/design.md) for the 10 design decisions that need to be resolved before building it.
