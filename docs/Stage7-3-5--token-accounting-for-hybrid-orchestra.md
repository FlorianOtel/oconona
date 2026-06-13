---
title: "Stage 7.3.5 — Token accounting for hybrid orchestra"
created_at: 2026-05-31--13-40
created_by: Claude Code (Claude Haiku 4.5)
updated_by: Claude Code (Claude Opus 4.7, 1M context)
updated_at: 2026-05-31--17-07
context: >
  v7.3.5 adds comprehensive token-accounting features for hybrid orchestra sessions:
  per-agent marginal-cost attribution, TTL-aware rate tables, drift detection, and
  session-report enhancements to surface per-agent cost delineation. Enables cost
  visibility across the Brain + Anthropic/SoHoAI subagent stack.
---

## 1. Overview

v7.3.5 introduces **hybrid orchestra token accounting** — a framework for tracking and attributing marginal token costs across the Brain (parent) and its subagent dispatches (Planner, Actor, Reviewer). After v7.3.5 ships:

1. **Reviewer** reverts from `sohoai/kimi-k2.7` to `anthropic/claude-sonnet-4-6` (restoring the standard pipeline as of v7.2+).
2. **Model rates** are centralized in `scripts/model-rates.yaml`, keyed by provider and supporting TTL-parameterised cache costs.
3. **Marginal attribution** computes the hidden cost of subagent dispatches within a Brain session (e.g., if Brain on Claude Opus caches a Planner response, the cache write is a marginal cost on Opus's output rate, not charged separately).
4. **Session reports** display per-agent cost delineation with a new `--hybrid-detail` flag for marginal-cost breakdown.
5. **Rate drift detection** (`verify-cost-rates.py`, Check D in smoke-test.sh) catches stale rates before they accumulate cost errors.

## 2. Reviewer Revert

In this stage, the Reviewer agent's model field changes from:

```yaml
model: sohoai/kimi-k2.7
```

to:

```yaml
model: anthropic/claude-sonnet-4-6
```

The 1M context is inherited from `opencode.json`. This restores the pre-v7.3 behaviour: after a `/brain` or `/duo`, the Reviewer tier runs on Anthropic (Claude Sonnet 4.6), yielding measurable per-tier costs and enabling marginal-cost attribution on Anthropic model costs.

## 3. Rate File

`scripts/model-rates.yaml` is the central source of truth for model costs. It has two main sections:

- **Provider models** — a dict of `"provider/model-id"` keys, each with an object containing `input`, `output`, `cache_read`, and `cache_write` fields.
- **`default_cache_ttl`** — a top-level field governing which TTL-based cache cost to use globally.

### Structure

```yaml
default_cache_ttl: "5m"

provider_models:
  "anthropic/claude-opus-4-7":
    input: 5.00
    output: 25.00
    cache_read: 0.50
    cache_write:
      "5m": 6.25
      # "1h": 10.00

  "sohoai/kimi-k2.7":
    input: 0
    output: 0
    cache_read: 0
    cache_write:
      "5m": 0
      "1h": 0
```

**Units:** all rates are in **USD per 1 million tokens** (matching Anthropic's public pricing format).

**Anthropic entries:** rates derived from https://www.anthropic.com/pricing/claude (as of 2026-05-31).

**SoHoAI entries:** all costs are zero (free-tier, internal deployment).

## 4. Cache TTL Parameterisation

`cache_write` is a **TTL-keyed sub-map**, while `cache_read`, `input`, and `output` are scalar (TTL-invariant).

### Why?

Cache write cost varies dramatically by TTL:
- **5m (ephemeral):** cheaper write cost, used by default.
- **1h (extended):** higher write cost, but cheaper read cost over a longer window (deferred in v7.3.5).

### Active TTL

The `default_cache_ttl` field at the top level selects which sub-key to use from `cache_write`:

```yaml
default_cache_ttl: "5m"  # Uses "5m" rates from all cache_write sub-maps
```

To switch to 1-hour extended-cache (a future config-only change when Oracle/SoHoAI/Anthropic support the header):

1. Update `default_cache_ttl: "1h"`.
2. Uncomment the `"1h"` lines in all `cache_write` sub-maps.
3. No code changes needed; `_get_rate()` automatically uses the new default.

### Per-call override (reserved)

In v7.4+, when per-turn TTL detection is implemented, `_get_rate(key, field, ttl="1h")` will allow per-session overrides. Currently all sessions use the global `default_cache_ttl`.

## 5. Marginal-Attribution Methodology

### Formula

For each subagent dispatch, the **marginal cost** to the Brain is:

```
marginal_cost = subagent.tokens_output × _get_rate(brain_model_key, "cache_write") / 1e6
```

The Brain's output becomes cached input for the subagent; thus the cost is attributed to the Brain's cache_write rate, not the subagent's input rate.

### Hidden hybrid cost

The sum of all subagent marginal costs is the **hidden hybrid cost** — cost incurred but not directly paid by the OC user (bundled into Brain's cost as a cache effect).

### Computation in telemetry.json

The `hybrid_attribution` field (added by v7.3.5) contains:

```json
{
  "hybrid_applicable": true,
  "parent_cache_efficiency_pct": 0,
  "ttl_lapse_flag": false,
  "subagent_marginal_costs": [
    { "agent": "planner", "output_tokens": 2500, "marginal_cost_usd": 0.0156 },
    { "agent": "actor", "output_tokens": 8000, "marginal_cost_usd": 0.0500 },
    ...
  ],
  "hidden_hybrid_cost_usd": 0.0656
}
```

**Fields:**
- `hybrid_applicable` — True if Brain's model rate is known and can be looked up; False for unknown models or free-tier models.
- `parent_cache_efficiency_pct` — advisory; 0 for now (reserved for read-amortisation component in v7.4+).
- `ttl_lapse_flag` — advisory; False (reserved for per-turn TTL detection in v7.4+).
- `subagent_marginal_costs` — list of per-agent marginal costs.
- `hidden_hybrid_cost_usd` — sum of marginal costs.

## 6. TTL-Lapse Audit

### Purpose

A **TTL lapse** occurs when a Brain session spans a cache TTL boundary (e.g., a 6-minute session with default 5m TTL crosses the boundary, causing the cache to flush mid-run). The `ttl_lapse_flag` is advisory only — it marks sessions where per-turn diagnosis should check whether cached tokens became uncached due to TTL expiry.

### Interpretation by active TTL

When `default_cache_ttl: "5m"`:
- Sessions **< 5 minutes** in duration: no lapse expected.
- Sessions **5–10 minutes** : lapse likely (first requests cached, later requests not).
- Sessions **> 10 minutes** : lapse very likely (multiple TTL cycles).

When `default_cache_ttl: "1h"` (future):
- Sessions **< 1 hour** : no lapse expected.
- Sessions **1–2 hours** : lapse likely.

### Current implementation

v7.3.5 sets `ttl_lapse_flag: False` unconditionally (heuristic deferred to v7.4+). Per-turn diagnosis (reading the `anthropic-beta` TTL header) is out of scope for v7.3.5.

## 7. Rate Maintenance

### Verification cadence

Rates are verified **quarterly** (every 3 months) against Anthropic's published pricing page. A smoke-test check (Check D) runs `verify-cost-rates.py` to detect drift > 1% from the stored session costs.

### Maintenance checklist

**When rates change (e.g., new model added or price update):**

1. Update `scripts/model-rates.yaml`:
   - Add or modify entries under `provider_models`.
   - Update `last_verified` timestamp.
   - Optionally update `last_verified_session` (a known good session to validate against).

2. Deploy:
   ```bash
   cd /mnt/nfs/Florian/Gin-AI/projects/oconona
   ./deploy.sh
   systemctl --user restart opencode-server.service
   ```

3. Run a test session and verify Check D passes:
   ```bash
   /brain "test query"  # or /duo-plan + /duo-act
   ~/.config/opencode/scripts/smoke-test.sh <session_dir>
   ```

### How to add a new model

1. Look up the model's pricing on the provider's page:
   - Anthropic: https://www.anthropic.com/pricing/claude
   - SoHoAI: ask the team (or use 0 for free-tier).

2. Add or update an entry in `scripts/model-rates.yaml`:

   ```yaml
   "provider/model-name":
     input: X.XX
     output: Y.YY
     cache_read: Z.ZZ
     cache_write:
       "5m": W.WW
       # "1h": V.VV  (uncomment when extended-cache is adopted)
   ```

3. Run `verify-cost-rates.py` on a test session to confirm the rates are sensible.

## 8. telemetry.json Schema

The `telemetry.json` file (produced by `telemetry-summarize.py` after every session) now includes a `hybrid_attribution` field (v7.3.5+):

```json
{
  "session_id": "20260531T101238Z-123456",
  "oc_session_id": "ses_1b96dc2ad...",
  "command": "brain",
  "started_at": "2026-05-31T10:12:38Z",
  "ended_at": "2026-05-31T10:15:42Z",
  "duration_s": 184,
  "outcome": "pass",
  "parent": {
    "agent": "brain",
    "model": "claude-opus-4-7",
    "provider_model_key": "anthropic/claude-opus-4-7",
    "cost": 0.0247,
    "tokens_input": 150,
    "tokens_output": 1200,
    "tokens_reasoning": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 500
  },
  "subagents": [
    {
      "agent": "planner",
      "model": "claude-opus-4-7",
      "provider_model_key": "anthropic/claude-opus-4-7",
      "cost": 0.0123,
      "tokens_input": 1200,
      "tokens_output": 800,
      "tokens_reasoning": 0,
      "tokens_cache_read": 2000,
      "tokens_cache_write": 0
    }
  ],
  "totals": {
    "cost_usd_estimate": 0.0370,
    "tokens_input": 1350,
    "tokens_output": 2000,
    "tokens_cache_read": 2000,
    "tokens_cache_write": 500
  },
  "cost_usd_estimate": 0.0370,
  "cost_source": "oc_sqlite",
  "project_dir": "/mnt/nfs/Florian/Gin-AI/projects/oconona",
  "status": "final",
  "hybrid_attribution": {
    "hybrid_applicable": true,
    "parent_cache_efficiency_pct": 0,
    "ttl_lapse_flag": false,
    "subagent_marginal_costs": [
      {
        "agent": "planner",
        "output_tokens": 800,
        "marginal_cost_usd": 0.005
      }
    ],
    "hidden_hybrid_cost_usd": 0.005
  }
}
```

**Backward compatibility:** pre-v7.3.5 telemetry files do not have a `hybrid_attribution` key. Scripts handle this gracefully with safe defaults (all fields zero/false).

## 9. Display Format

### session-report.py enhancements

The per-session report now includes per-agent cost delineation:

```
=== Per-Agent Cost Delineation ===

Session: 20260531T101238Z-3575052
  Agent | Model | Cost | Tokens
  brain | claude-opus-4-7 | $0.0247 (+$0.0050 hidden) | 1200
  [TTL-lapse?]
  planner | claude-opus-4-7 | $0.0123 | 800
```

**Annotations:**
- **`(+$Y.YY hidden)`** — displayed on Brain row when `hybrid_attribution.hidden_hybrid_cost_usd > 0`. This is the marginal cost of subagent caching charged to the Brain's cache_write rate.
- **`[TTL-lapse?]`** — displayed on Brain row when `ttl_lapse_flag: True`. Advisory marker for manual per-turn inspection.

### --hybrid-detail flag

Pass `--hybrid-detail` to `session-report.py` to print a detailed marginal-cost breakdown:

```bash
~/.config/opencode/scripts/session-report.sh --last 1 --hybrid-detail
```

Output (extra section):

```
  Marginal Cost Breakdown:
  Subagent | Output tokens | Marginal Brain cost
  planner  |           800 | $0.005000
  actor    |          2100 | $0.052500
```

For sessions with no hybrid attribution (pure-Anthropic `/duo` with no free-tier subagents), the breakdown shows:

```
  (no hybrid attribution — all tiers paid directly)
```

### verify-cost-rates.py output

```
Tier cost verification (tolerance: 1.0%):

  brain    | claude-opus-4-7 | OK: 0.024700 (expected 0.024650)
  planner  | claude-opus-4-7 | OK: 0.012300 (expected 0.012325)
  actor    | claude-opus-4-7 | OK: 0.010500 (expected 0.010525)
  reviewer | claude-sonnet-4-6 | OK: 0.003200 (expected 0.003200)
```

Or for a stale rate:

```
  brain    | claude-opus-4-7 | STALE: 0.024700 vs 0.025500 (3.2% drift)
```

Exit code 0 (success) when all tiers are OK or WARN; exit code 1 (failure) when any tier is STALE.

---

## Deliverables

**Commit:** `ba998ee`

**Files:**
- `agents/reviewer.md` — model field updated to anthropic/claude-sonnet-4-6
- `scripts/model-rates.yaml` — new; central rate table (v7.3.5)
- `scripts/oc-db.py` — added `_parse_model_full()`, `_load_model_rates()`, `_get_rate()`, `_compute_hybrid_attribution()`; updated `_zero_tier()`, `_row_to_tier()`, `get_session_telemetry()`
- `scripts/telemetry-summarize.py` — updated `_zero_struct()` with `hybrid_attribution` field; passes through in telemetry object
- `scripts/session-report.py` — added `--hybrid-detail` flag; prints per-agent cost delineation with hidden-cost and TTL-lapse annotations
- `scripts/native-session-report.py` — backward-compat ensured; no changes needed for v7.3.5
- `scripts/verify-cost-rates.py` — new; standalone rate-drift detector (Check D)
- `scripts/smoke-test.sh` — added Check D; updated pass threshold from 3/3 to 4/4
- `deploy.sh` — added model-rates.yaml and verify-cost-rates.py to deployment list
- `AGENTS.md` — Reviewer model reference updated
- `docs/Stage7.md` — v7.3.5 row added to sub-stage roadmap
- `docs/Stage7--Changelog.md` — v7.3.5 entry prepended
- `docs/design.md` — rate-source paragraph + Reviewer row update + TTL cross-ref
- `docs/TODO.md` — periodic maintenance section prepended

---

## Notes

- **Rate staleness:** rates are verified quarterly; Check D (smoke-test.sh Check D or standalone `verify-cost-rates.py`) catches drift. Until v7.4's per-turn TTL detection, `ttl_lapse_flag` is advisory only.
- **Per-session TTL override:** reserved for v7.4+; currently global `default_cache_ttl` applies to all sessions.
- **1-hour extended-cache:** rates present but commented out in YAML; activation is a future config edit (no code changes).
- **Backward compatibility:** pre-v7.3.5 telemetry files render unchanged in session-report.py; `--hybrid-detail` shows "no hybrid attribution" for old sessions.
