---
title: "OpenCode Orchestra (non-Anthropic) — Phase 0 Architecture Decisions"
created_at: 2026-05-20--23-30
created_by: Claude Code (Claude Haiku 4.5)
context: >
  Four architectural decisions inherited from the opencode-orchestra Phase 0 migration,
  applied to the non-Anthropic variant. All four decisions (plan-approval gate,
  pre-compact state, SoHoAI routing, status-line cost display) are unchanged in substance.
  Decision 3 (SoHoAI routing: option C — all traffic through SoHoAI) is more load-bearing
  here because the entire non-Anthropic pipeline depends on SoHoAI's LiteLLM router for
  model aliasing.
---

# Architecture Decisions — opencode-orchestra (non-Anthropic) Phase 0

Inherited decisions from the opencode-orchestra Phase 0 migration, applied to the non-Anthropic variant.

## Decision 1: Plan-approval gate

**Choice:** Option A — `/brain-plan` + `/brain-act` split

The `ExitPlanMode` call that currently bridges Phase 0→Phase 2 in `/brain` will be
replaced by a two-command split: `/brain-plan` sets up the session and dispatches
Planner, `/brain-act` calls the approval gate then dispatches Actor. This orphans
the current `ExitPlanMode` call in `/brain`. Marked with `TODO(Phase 2)` comments.

## Decision 2: Pre-compact state

**Choice:** Option A — drop resume-after-clear

`PLAN.md` and `TASKS.json` in the session directory are sufficient for resume.
The `PreCompact` hook that writes `brain-state.md` is retained for Phase 0 but
marked `TODO(Phase 3)` for removal when the `session.compacted` plugin event
becomes available in OpenCode.

## Decision 3: SoHoAI routing

**Choice:** Option C — all traffic through SoHoAI

All model requests (Planner, Actor, Reviewer, Brain) route through SoHoAI.
`_resolve_proxy_model` in `telemetry-summarize.py` handles the model ID mapping.
No split between native Anthropic and SoHoAI routing.

**Non-Anthropic variant note:** This decision is more load-bearing in the non-Anthropic
pipeline because all models (claude-code-glm-5.1, claude-code-qwen3-coder-next,
claude-code-kimi-k2.6) are SoHoAI-routed via LiteLLM aliases. There is no fallback
to direct Anthropic APIs.

## Decision 4: Status-line cost display

**Choice:** Option A — defer to post-v1

Live cost display in the status line is deferred until after the v1 OpenCode
integration is stable. The existing SoHoAI sidecar fallback (`sohoai-live-cost.sh`)
remains in place and will be wired up in a follow-on pass.

**Non-Anthropic variant note:** Cost display is partially implemented via the
`orchestration-block.sh` status-line patch, which queries SoHoAI live-cost endpoint
for non-Anthropic models and falls back to T2 (transcript parsing) when SoHoAI is
unavailable or during the session's final turn (when `/duo-act` or `/brain-abandon`
cleanup runs).
