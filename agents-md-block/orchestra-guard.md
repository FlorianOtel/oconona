## Orchestra in-pipeline guard

If a /brain or /duo session is active **in the current project**, the pipeline
owns code changes. A session counts as active-in-this-project only when some
`${HOME}/.config/opencode/orchestra/sessions/*/.brain-inflight` (or `.duo-inflight`)
file exists **whose sibling `.project-dir` file resolves (realpath) to the current
working directory**. An inflight marker whose `.project-dir` points at a *different*
project does NOT gate this session — it is unrelated and must be ignored (do not
mention it, do not suggest `/brain-abandon` for it). When in doubt, verify by
reading the marker's sibling `.project-dir` before treating the pipeline as active:

- Code edits to project files MUST go through the Actor subagent (Task tool,
  `subagent_type: actor` for default tier, or `subagent_type: actor-heavy` for
  `[tier — heavy]` steps). Direct Edit/Write/Bash on project code violates
  the pipeline.
- Plan production for `/brain` MUST go through the Planner subagent (Task
  tool, `subagent_type: planner`). You (Brain) persist Planner's returned
  plan to `${SESSION_DIR}/PLAN.md` via Bash atomic-rename. Operator approves
  via natural-language reply ("approved" / "go ahead" / "proceed").
- Fact-finding during Phase 0 (load-bearing hypothesis verification) MUST go through the `researcher` or `researcher-deep` subagent (Task tool, `subagent_type: researcher` for default tier, `researcher-deep` for escalation). Direct assertions of unverified factual claims during Phase 0 violate the pipeline — they are the v8.1.5.x failure mode this design prevents.
- Session-dir artefacts (`RESEARCH.md`, `PLAN.md`, `.outcome`, `state.env`,
  `.brain-inflight`, `.duo-inflight`, `.oc-session-id`, `.project-dir`) are
  written directly via Bash heredoc; project code is not.
- If you find yourself about to use Edit/Write/Bash on project code while
  an inflight marker exists, stop and dispatch the appropriate subagent
  (`actor` for default tier, `actor-heavy` for `[tier — heavy]` steps). To
  exit cleanly without executing, run `/brain-abandon` or `/duo-abandon`.
