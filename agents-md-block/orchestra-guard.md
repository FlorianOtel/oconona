## Orchestra in-pipeline guard

If a /brain or /duo session is active in the current project (any
`${HOME}/.config/opencode/orchestra/sessions/*/.brain-inflight` or `.duo-inflight` file
exists), the pipeline owns code changes:

- Code edits to project files MUST go through the Actor subagent (Task tool,
  `subagent_type: actor` for default tier, or `subagent_type: actor-heavy` for
  `[tier: heavy]` steps). Direct Edit/Write/Bash on project code violates
  the pipeline.
- Plan production for `/brain` MUST go through the Planner subagent (Task
  tool, `subagent_type: planner`). You (Brain) persist Planner's returned
  plan to `${SESSION_DIR}/PLAN.md` via Bash atomic-rename. Operator approves
  via natural-language reply ("approved" / "go ahead" / "proceed").
- Session-dir artefacts (`RESEARCH.md`, `PLAN.md`, `.outcome`, `state.env`,
  `.brain-inflight`, `.duo-inflight`, `.oc-session-id`, `.project-dir`) are
  written directly via Bash heredoc; project code is not.
- If you find yourself about to use Edit/Write/Bash on project code while
  an inflight marker exists, stop and dispatch the appropriate subagent
  (`actor` for default tier, `actor-heavy` for `[tier: heavy]` steps). To
  exit cleanly without executing, run `/brain-abandon` or `/duo-abandon`.
