---
title: "oconona TODO & open questions"
created_at: 2026-05-30--00-30
created_by: Claude Code (Claude Sonnet 4.6, 1M context)
updated_by: Brain (Anthropic Opus 4.7 via /brain) — v7.5beta
updated_at: 2026-06-03--07-52
context: >
  Single-file ledger of open questions, deferred investigations, and follow-up
  items for the oconona project. Created during the v7.3 hotfix cycle to
  capture deep-dive findings on telemetry capture and cache cost mechanics
  that warrant further investigation but are out of scope for the immediate
  hotfix work. Sections are timestamped on creation; close them out (don't
  delete) when resolved so the audit trail remains.
---

# oconona TODO & open questions

Append new entries at the top with a clear timestamp and topic header.
Mark resolved items with their resolution date and outcome rather than
deleting them — the rationale chain matters.

---

## 2026-06-03 — v7.5beta delivered: SSOT tier config mechanism + deploy-time audit + arch sweep

**Commit:** `4c1e292`

v7.5beta introduces the single source of truth (SSOT) mechanism for tier→model mapping. The new `config/orchestra-tiers.yaml` centralizes the four worker-tier model assignments with per-tier documentation and recommendations for brain/duo roles. Deploy-time audit script (`scripts/check-tiers.py`) runs hard-fail checks on agent frontmatter, model-rates.yaml, and context-windows.yaml, plus soft-warn checks on documentation sync. Supporting prose corrections in `docs/design.md` (model-string literals removed, Reviewer non-Anthropic claim corrected, tier table annotated), `README.md` (SSOT pointer added), and `AGENTS.md` (brain model id inlined). Legacy fallback in `scripts/session-report.py` removed. Octmux integration (original v7.5 scope) deferred to v7.6.

---

## Periodic maintenance checklist

### Cost rate refresh (quarterly)

Every three months, verify model costs against Anthropic's published rates:

1. **Check Anthropic pricing page** (https://www.anthropic.com/pricing/claude)
2. **Update `scripts/model-rates.yaml`** if any rates have changed:
   - Update `last_verified` timestamp (YYYY-MM-DD)
   - Update or add entries under `provider_models`
   - Uncomment `"1h"` lines if/when extended-cache TTL is activated
3. **Run `./deploy.sh`** to deploy the updated rates
4. **Verify with smoke test**:
   ```bash
   /brain "test query"  # or /duo-plan + /duo-act
   ~/.config/opencode/scripts/smoke-test.sh <session_dir>
   ```
   Check D should pass (all tiers OK or WARN; no STALE).

---

## 2026-06-02 — S1 open questions: parent.model NULL in OC DB

**Status:** open — investigation deferred; not in v7.3.5 hotfix #1.

**Context:** Discovered during root-cause analysis of the all-zeros telemetry bug
(octmux orchestra session `20260601T220451Z-126209`). Full forensic record at
`../octmux/docs/cost-telemetry-investigation.md` §S1.

### Background

The brain parent session row (`ses_17ad26e03ffeWX9l6sspQFduDz`) has `model: NULL`
and `agent: NULL` in OC SQLite. In `oc-db.py`, `_parse_model_full(None)` returns
`""`, so `provider_model_key = ""` in the tier dict. `_compute_hybrid_attribution()`
short-circuits to `hybrid_applicable: False` with all zeros when `parent_key` is
empty.

**Bounded impact:** dollar cost is still correct (read from `session.cost` directly);
token counts are still correct. Only hybrid-attribution analytics (marginal cost of
subagent dispatches against the parent's cache_write tier) is suppressed.

**Comparison:** an older session `ses_18bc9650bffeuLSruGyLjfo9KC` (slug `clever-meadow`,
2026-05-29) has populated fields: `agent: 'build'`, `model: '{"id":"claude-opus-4-7",...}'`.
So the OC daemon CAN write them; this brain session simply did not have them set.

### Open questions for S1

a. Does the OC `/session/create` REST API accept `model` and `agent` fields in the
   request body, and does the /brain entry path supply them?

b. Does OC write `session.model` only after the first message is sent on the session,
   and if so does the column ever get back-filled for the *creating* session (vs. only
   for sessions that originate from a user message in the chat UI)?

c. Does the `OPENCODE_MODEL` environment variable, or default-config inheritance,
   bypass the DB write path entirely — leaving the column NULL even though a model
   is in fact being used?

---


## 2026-05-30 — Telemetry capture mechanics + cache cost (mis)allocation deep-dive

Created during v7.3 hotfix #7 cycle, after the end-to-end `/brain` smoke test
verified the math but raised legitimate questions about *what* OC is actually
billing for vs what Anthropic actually charges.

### 1. How telemetry is captured

#### 1.1 Native OC sessions (no orchestra wrapping)

A "native" OC session is any top-level OC chat session that is **not** wrapped by
`/brain` or `/duo-plan`. Telemetry for these is entirely OC-internal — oconona
doesn't intervene:

| Step | Where it happens |
|---|---|
| Session row created | OC daemon, when `client.session.create({})` is called (typically on first message in octmux) |
| Per-turn cost computed | `@ai-sdk/anthropic` SDK inside OC, from the `usage` field of each Anthropic API response |
| Cost stored | OC writes to `session.cost` (epoch-cumulative) and `session.tokens_*` columns in `~/.local/share/opencode/opencode.db` |
| WAL behaviour | Local NVMe, WAL mode confirmed — concurrent readers (status-line, oconona reports) never block OC's writer |

Reporting for native sessions uses the new `scripts/native-session-report.{sh,py}`
(restored in commit `7fabdaa`), which walks OC's DB for `parent_id IS NULL`
sessions and excludes any whose `id` appears in some orchestra session_dir's
`.oc-session-id` sidecar.

#### 1.2 Orchestra-wrapped sessions (`/brain`, `/duo-plan` → `/duo-act`)

These have BOTH an OC session row AND an oconona session directory. The two are
joined by the `.oc-session-id` sidecar (v7.3 hotfix #3 resolver, commit `51073cf`).

Lifecycle:

```
operator types /brain in octmux
       │
       ▼
OC processes the command body (cached at OC server startup; restart needed for re-read)
       │
       ▼
Setup bash runs:
  • mkdir SESSION_DIR (UTC-ts-PID)
  • write .brain-inflight, .project-dir
  • resolve OC session ID via HTTP API → .oc-session-id sidecar
  • write state.env (badge: ORCHESTRA_MODE=brain, ORCHESTRA_TITLE=...)
       │
       ▼
Phase 0: Brain interrogates operator inline (no subagent)
       │
       ▼
Phase 1: Brain dispatches Planner via `Task` tool
  → OC creates a CHILD session row (parent_id = brain's OC session id)
  → Child runs on sohoai/glm-5.1 (flat-rate, cost = $0)
  → Child returns plan text; Brain persists it to PLAN.md via Bash atomic-rename
       │
       ▼
Phase 2: Brain dispatches Actor (similar — child session, sohoai/qwen3-coder-next)
       │
       ▼
Phase 3: Brain dispatches Reviewer (anthropic/claude-sonnet-4-6); loop on FIX up to 3x
       │
       ▼
Cleanup runs:
  1. Write .outcome (atomic-rename) BEFORE summariser — mtime bounds the time window
  2. Run telemetry-summarize.sh → telemetry-summarize.py:
     a. Reads .oc-session-id sidecar
     b. Imports oc-db.py via importlib (hyphen-in-filename quirk)
     c. Calls oc_db.get_session_telemetry(oc_session_id):
        • parent row from OC DB
        • child rows via WHERE parent_id = brain_session_id
        • totals aggregated: cost (sum), tokens_input/output/cache_read/cache_write (sum)
     d. Writes telemetry.json atomically (mktemp + mv -f)
  3. Remove .brain-inflight (badge clears)
  4. Append state.env reset (ORCHESTRA_MODE=default)
```

Important properties of this design:

- **OC's `session.cost` is the authoritative source.** oconona does NOT compute
  cost from token counts. It reads what OC's SDK already computed and stored.
- **telemetry.json is a snapshot at cleanup time.** Any OC activity after the
  summariser runs (e.g. Brain's final operator-facing summary message) is in
  OC's DB but not in `telemetry.json`. The gap is real but small (~$0.05).
- **`cost_source: "oc_sqlite"`** marks the new path. Pre-v7.3 sessions used
  `cost_source: "none"` or pricing.yaml fallback (now removed).

#### 1.3 Subagent invocation and child-session creation

When Brain (or Duo's Actor in the simpler pipeline) calls the `Task` tool with
`subagent_type: planner` etc., OC internally:

1. Creates a new session row with `parent_id = current_session.id`
2. Runs the subagent's body in that child session
3. Records usage events from the child's model into the child's row
4. Returns the subagent's final text to the parent (Brain)

The parent session's `cost` and `tokens_*` are NOT incremented by the child's
tokens — they're separate rows. `get_session_telemetry` follows the
`parent_id` link to sum them at report time.

For oconona's worker tier (planner/actor/actor-heavy/reviewer running on
`sohoai/*`), OC's SDK correctly reports `cost = 0` because those go through the
`@ai-sdk/openai-compatible` provider which honors the flat-rate-marginal
convention. The child sessions still get `tokens_input/output` recorded; they
just don't have a per-token cost.

#### 1.4 Cost summarization

The `telemetry.json` written at cleanup has three nested layers:

| Layer | Fields | Source |
|---|---|---|
| `parent` | agent, model, cost, tokens_* | Brain's OC session row |
| `subagents[]` | one entry per child row, same fields | child OC session rows |
| `totals` | cost_usd_estimate, tokens_input, tokens_output, tokens_cache_read, tokens_cache_write | sum of parent + subagents |

Top-level `cost_usd_estimate` mirrors `totals.cost_usd_estimate` for backward
compat with octmux Stage 6.4 consumers.

`session-report.py` reads these telemetry.json files; it does NOT re-query OC's DB.
This makes the report fast but means OC activity after cleanup is invisible to
the report — which is by design (per-session cost should be stable).

### 2. Cache mechanics — how cache really behaves during a Brain pipeline

A common misconception (held by the operator at one point): "subagent returns
invalidate Brain's cache." That's not how Anthropic's prompt caching works.
The actual mechanics matter for understanding cost.

#### 2.1 Anthropic prompt cache is forward-only

Anthropic's caching is **append-only / forward-only**:

- Each request includes the current prompt with optional `cache_control` breakpoints.
- A breakpoint tells the API "cache the prefix up to here." Anthropic identifies
  this prefix by content hash + cache_control marker position.
- If a subsequent request has the SAME prefix up to a previously-cached
  breakpoint, Anthropic charges `cache_read` for those tokens (~10x cheaper).
- If the prefix DIVERGES before the breakpoint, the cache is missed and the
  full prefix is charged at input rate.
- If new content is APPENDED past a previously-cached breakpoint, the new
  content is charged at input rate (uncached). To cache the new content for
  future requests, a NEW breakpoint must be set after it.

**There is no "invalidation event."** A cache write doesn't get torn down by
later activity — it just lives until its TTL expires (5 min ephemeral, ~1 h
persistent). New content appended after a breakpoint doesn't touch the older
cached prefix.

#### 2.2 What happens when Brain dispatches a subagent

| Event | Cache effect |
|---|---|
| Brain's prompt grows over turns | Each turn, Brain's full conversation history is sent. If the same prefix has been seen recently with a cache_control marker, it reads from cache. New tail (the latest turn's content + tool calls) is uncached input — or new cache_write if Brain sets a new breakpoint. |
| Brain calls Task tool (subagent dispatch) | Brain's API request includes a tool_use call. The model produces output_tokens for "I'm calling Task." This is normal output billing. |
| Subagent runs in a SEPARATE OC child session | The subagent has its OWN prompt (its system prompt, its task), its own cache, its own usage. Brain's cache is untouched by anything the subagent does. |
| Subagent returns text to Brain | Brain receives the return in its NEXT turn's tool_result content block. That content becomes new input tokens (or new cache_write if a breakpoint is set after it). Brain's previously-cached prefix is still valid; only the new tail is uncached. |
| Brain's TTL clock | Brain's cached prefix has a 5-minute TTL (ephemeral). If Brain takes >5 min processing the subagent return + next turn, the cache expires. The NEXT turn will see a cache miss and pay full input rate for the previously-cached prefix. |

#### 2.3 What this means for cost

For a typical `/brain` session that took ~400 seconds (>5 min):

- The earliest cache_write tokens TTL-expire before the session ends
- Later turns either pay full input rate (cache miss) OR re-cache the same
  prefix at a new breakpoint (more cache_write tokens)
- Both behaviors show up in OC's recorded token counts — there's no hidden
  cost; we see all of it

Example from `ses_18a544a4effeLo8NL1EAZJdcKN` (405-second Brain session):

| Token category | Count | Rate ($/M) | Cost |
|---|---:|---:|---:|
| Uncached input (`tokens_input`) | 24 | 5.00 | $0.0001 |
| Output (`tokens_output`) | 11,021 | 25.00 | $0.2755 |
| Cache reads (`tokens_cache_read`) | 372,277 | 0.50 | $0.1861 |
| Cache writes (`tokens_cache_write`) | 35,196 | 6.25 | $0.2200 |
| **Total** | | | **$0.6818** |

OC's stored `session.cost`: **$0.6818** — exact match assuming 5-minute cache rate.

The high cache_read:cache_write ratio (372K read vs 35K written) is the
expected pattern for a multi-turn session that benefits from prefix caching —
each turn rewrites a small tail and reads a large stable prefix.

### 3. Open questions — cache TTL and pricing tier

These are the things we DON'T know for sure, that the verification math
above doesn't resolve.

#### 3.1 Which cache tier does Anthropic actually bill for an OC request?

OC's binary contains references to BOTH cache types:
- `type: "ephemeral"` — 5-minute TTL, billed at **$6.25/M** for Opus 4.7
- `type: "persistent"` (`ttl: "1h"`) — 1-hour TTL, billed at **~$12.50/M** for Opus 4.7

The math above (which matches OC to the penny) assumes ALL cache_write tokens
are billed at the 5-minute rate. If any portion of OC's requests actually use
1-hour cache, OC is under-billing for those tokens.

What's known:
- Default `cache_control` constant in the AI-SDK is `{ type: "ephemeral" }`
- `ttl: "1h"` is reachable but requires explicit opt-in
- We have NOT yet seen a request where OC sets the 1-hour TTL

What's unclear:
- Does OC ever opt into 1-hour cache automatically? (e.g. for stable system
  prompts that are unlikely to change across sessions)
- Does the operator's account tier / auth method affect what TTL is granted
  even when requested as 5 min?

#### 3.2 Cache TTL behavior may depend on auth method (operator empirical observation)

The operator has previously observed that cache TTL behavior differs between:
- **OAuth-based auth** (browser login flow, Anthropic Console)
- **API-key-based auth** (`ANTHROPIC_API_KEY` env var)

Hypothesis (not yet confirmed):
- OAuth sessions may default to 1-hour cache server-side
- API key sessions may stay at 5-minute cache
- OR: the inverse, depending on account tier

If true:
- An OC session authenticated via OAuth that REQUESTS 5-min cache could be
  GRANTED 1-hour cache and BILLED at the 1-hour rate
- OC's cost calculation (based on 5-min rate) would systematically under-count
- The same OC code running with API key auth would NOT have this gap

This needs empirical verification with both auth methods, comparing actual
Anthropic billing.

#### 3.3 Reasoning tokens for Anthropic (extended thinking) — capture path?

OC's schema has `tokens_reasoning` as a separate column. In our test DB:

| Model class | `tokens_reasoning` populated? |
|---|---|
| `sohoai/*` (Kimi, Qwen, GLM) | YES — values up to 62K per session |
| Anthropic Opus 4.7 (Brain) | NO — always 0 in all observed sessions |

Either:
- (a) Brain was not using extended thinking in our `/brain` sessions
- (b) OC's `@ai-sdk/anthropic` path doesn't capture reasoning tokens into the
  DB even when they're generated

If (b), a Brain session that DID think internally would be under-counted by
`tokens_reasoning × $25/M` (Anthropic bills reasoning tokens at output rate).

#### 3.4 Server-side tool tokens (web_search, computer_use)

Not relevant to our current local-only `/brain` sessions but worth noting:
Anthropic's server-side tools generate tokens that are billed as input.
OC's binary has handling for `server_tool_use` in its usage parsing. We
have not yet verified this path captures correctly into `session.cost`.

### 4. Ways to investigate further / mitigate

In priority order — cheapest, most informative tests first.

#### 4.1 Cross-check OC totals against Anthropic billing console (cheapest, definitive)

Sum OC's recorded cost for a specific time window per Anthropic model. Compare
against the operator's Anthropic billing console for the same window.

```bash
python3 -c "
import sqlite3
c = sqlite3.connect('file:'+os.path.expanduser('~/.local/share/opencode/opencode.db')+'?mode=ro', uri=True)
rows = c.execute('''
  SELECT model, COUNT(*) as n, SUM(cost) as total
  FROM session
  WHERE model LIKE \"%anthropic%\"
    AND time_created > strftime(\"%s\",\"2026-05-01\") * 1000
  GROUP BY model
''').fetchall()
for r in rows: print(r)"
```

If the gap is within 5%: OC's math is right; stop here. If 10-30%: investigate
4.2-4.4. If >30%: there's a deeper discrepancy.

#### 4.2 Capture a real OC → Anthropic API request and inspect cache_control

The deterministic answer to §3.1. Options:

- **Network tap**: `mitmproxy` between OC and `api.anthropic.com`, capture one
  full Brain turn, inspect the JSON `messages[].content[].cache_control` field
  for `{type, ttl}`. Direct evidence of which tier is in use.
- **OC verbose logging**: set `--log-level DEBUG` on the systemd unit and
  inspect `~/.local/share/opencode/log/*.log` for raw outgoing request bodies.
  Less invasive than mitmproxy.
- **Anthropic Console request log**: if available, shows what the API
  recorded vs what was charged.

#### 4.3 Auth-method-paired test for §3.2

Run two equivalent Brain sessions (same prompt, same model):
- One with OAuth-authenticated OC
- One with `ANTHROPIC_API_KEY`-authenticated OC

Compare:
- OC's recorded `cost` field
- Anthropic billing console actual charges
- Captured API requests (per §4.2)

If the API-key session matches OC's math (5-min rate) and the OAuth session
costs ~2x more on Anthropic's side, §3.2 hypothesis is confirmed — OC's cost
calculation is silently wrong under OAuth.

#### 4.4 Extended-thinking probe for §3.3

Force Brain to use extended thinking explicitly (one operator turn that
prompts "think carefully step by step before responding"). After the turn,
check whether OC's DB has populated `tokens_reasoning > 0` for the Brain
session. If still 0 despite thinking blocks in the response, OC's capture
path is incomplete.

#### 4.5 Mitigation options (assuming any of the above confirms under-counting)

| Source of gap | Fix |
|---|---|
| 1-hour cache used but billed at 5-min rate | Patch OC's pricing config or oc-db.py to add `cache_write_1h_rate` and detect tier from cache_control captured in usage events |
| Reasoning tokens not captured | Patch `@ai-sdk/anthropic` integration to propagate `output_thinking` or `reasoning_tokens` into OC's session.tokens_reasoning |
| OAuth path silently upgrades cache TTL | File upstream issue with OC; in oconona, document the operator workaround (use API key for accurate cost) |
| models.dev rates stale | Override via OC config or oconona's own cost recomputation in `oc-db.py:get_session_telemetry` |

If OC's upstream is unwilling/slow to fix, oconona could add a `cost_correction`
layer in `telemetry-summarize.py` that re-bills cache_write at 1-hour rate
whenever the OC session was OAuth-authenticated. Adds complexity but
preserves billing accuracy. Defer until §4.1-§4.3 confirm the gap is real.

#### 4.6 Build a `cost-audit.py` tool

Light Python script that pulls OC's totals broken down by:
- model
- token category (input / output / cache_read / cache_write / reasoning)
- per-day and cumulative

Output format compatible with side-by-side comparison against Anthropic
console CSV exports. Estimated 80 lines. Would make §4.1 a one-command
operation and make follow-up auth-method probing tractable.

---
