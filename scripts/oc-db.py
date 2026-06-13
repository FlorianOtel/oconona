#!/usr/bin/env python3
"""
oc-db.py — read-only helper for querying OpenCode's SQLite session table.

Safety guarantees:
  - Opens DB in read-only mode (`?mode=ro` URI parameter)
  - Respects WAL (write-ahead log) mode; multiple concurrent readers never block
  - Assumes DB lives on local NVMe (~/.local/share/opencode/opencode.db)
  - 5-second query timeout per connection
  - Schema self-check at first open() call per process (raises RuntimeError on mismatch)

Import pattern (for callers):
  import sys
  from pathlib import Path
  sys.path.insert(0, str(Path(__file__).parent / "scripts"))
  import oc_db
  telemetry = oc_db.get_session_telemetry(oc_session_id)
"""

import json
import sqlite3
import time
import warnings
from pathlib import Path
from typing import Optional

try:
    import yaml
except ImportError:
    yaml = None


_DB_PATH = Path.home() / ".local" / "share" / "opencode" / "opencode.db"
_REQUIRED_COLUMNS = {
    "id", "parent_id", "cost", "tokens_input", "tokens_output", "tokens_reasoning",
    "tokens_cache_read", "tokens_cache_write", "model", "agent",
    "time_created", "time_updated", "time_archived", "directory",
}
_schema_checked = False
_model_rates = None  # Cached rates dict


def open_db() -> sqlite3.Connection:
    """
    Open OC's SQLite DB in read-only mode with schema self-check.

    Returns sqlite3.Connection with row_factory = Row.
    Raises RuntimeError if DB not found or schema mismatch.
    Schema check runs once per process (guarded by _schema_checked flag).
    """
    global _schema_checked

    if not _DB_PATH.exists():
        raise RuntimeError(f"OC database not found at {_DB_PATH}")

    uri = f"file:{_DB_PATH}?mode=ro"
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=5.0, check_same_thread=False)
        conn.row_factory = sqlite3.Row
    except sqlite3.OperationalError as e:
        raise RuntimeError(f"Failed to open OC database: {e}") from e

    if not _schema_checked:
        _check_schema(conn)
        _schema_checked = True

    return conn


def _check_schema(conn: sqlite3.Connection) -> None:
    """
    Verify that the 'session' table has all required columns.
    Raises RuntimeError with explicit missing-column name on mismatch.
    """
    try:
        cursor = conn.execute("PRAGMA table_info(session)")
        columns = {row[1] for row in cursor.fetchall()}
    except sqlite3.OperationalError as e:
        raise RuntimeError(f"OC schema check failed: {e}") from e

    missing = _REQUIRED_COLUMNS - columns
    if missing:
        first_missing = sorted(missing)[0]
        raise RuntimeError(f"OC schema mismatch: missing column '{first_missing}'")


def _parse_model(raw) -> str:
    """
    Extract model ID from OC's model column (which stores JSON).

    If raw is a non-empty string:
      - Try json.loads(raw)["id"]
      - On TypeError / JSONDecodeError / KeyError: return raw as fallback
    If raw is None or empty: return ""
    """
    if not raw:
        return ""

    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if isinstance(parsed, dict) and "id" in parsed:
                return str(parsed["id"])
        except (TypeError, json.JSONDecodeError, KeyError):
            pass
        return raw

    return ""


def _parse_model_full(raw) -> str:
    """
    Extract full provider-qualified model key from OC's model column (which stores JSON).

    Returns "{providerID}/{normalized_id}" if both are present; defensive fallback:
      - If providerID missing but id starts with "claude-", assume "anthropic"
      - Normalization for sohoai: strip "ollama-cloud/" or "local/" prefixes
      - On error, returns ""

    Format of raw: {"id":"kimi-k2.7","providerID":"sohoai","variant":"default"}
    """
    if not raw:
        return ""

    if isinstance(raw, str):
        try:
            parsed = json.loads(raw)
            if not isinstance(parsed, dict):
                return ""

            model_id = parsed.get("id", "")
            provider_id = parsed.get("providerID", "")

            # Defensive fallback: if providerID missing but id starts with claude-, assume anthropic
            if not provider_id and model_id and model_id.startswith("claude-"):
                provider_id = "anthropic"

            if not provider_id or not model_id:
                return ""

            # Normalization: strip sohoai prefixes
            if provider_id == "sohoai":
                if model_id.startswith("ollama-cloud/"):
                    model_id = model_id[len("ollama-cloud/"):]
                elif model_id.startswith("local/"):
                    model_id = model_id[len("local/"):]

            return f"{provider_id}/{model_id}"
        except (TypeError, json.JSONDecodeError, KeyError):
            pass

    return ""


def _load_model_rates() -> dict:
    """
    Load model rates from scripts/model-rates.yaml.

    Returns dict with keys "provider_models", "default_cache_ttl".
    On error, returns empty dict {}.
    Caches result in module global _model_rates.
    """
    global _model_rates

    if _model_rates is not None:
        return _model_rates

    if yaml is None:
        return {}

    try:
        rates_path = Path(__file__).parent / "model-rates.yaml"
        if not rates_path.exists():
            return {}

        with open(rates_path, "r") as f:
            data = yaml.safe_load(f)

        if not isinstance(data, dict):
            return {}

        _model_rates = data
        return data
    except Exception:
        return {}


def _get_rate(key: str, field: str, *, ttl: Optional[str] = None) -> Optional[float]:
    """
    Look up a rate from the model-rates table.

    Args:
        key: provider-qualified model key (e.g., "anthropic/claude-opus-4-7")
        field: rate field ("input", "output", "cache_read", "cache_write")
        ttl: optional TTL override (e.g., "1h", "5m"); only used for cache_write.
             If not provided, uses top-level default_cache_ttl from YAML.

    Returns:
        Float cost ($/1M tokens), or None if not found / key unknown.

    Behavior:
      - For TTL-invariant fields (input, output, cache_read): ttl param ignored; returns scalar.
      - For cache_write: if field is a dict, resolves to the specified (or default) TTL sub-key.
        Returns None if the TTL tier is not defined (e.g., "1h" commented out).
      - Backward-compat: if cache_write is a scalar (deprecated), logs DeprecationWarning and treats as "5m" value.
    """
    rates = _load_model_rates()
    if not rates:
        return None

    provider_models = rates.get("provider_models", {})
    model_data = provider_models.get(key)
    if not model_data:
        return None

    if field != "cache_write":
        # TTL-invariant fields
        val = model_data.get(field)
        if val is not None:
            return float(val)
        return None

    # cache_write handling: TTL-keyed sub-map
    cache_write = model_data.get("cache_write")
    if cache_write is None:
        return None

    # Deprecated scalar form
    if not isinstance(cache_write, dict):
        warnings.warn(
            f"Deprecated: cache_write for {key} is scalar; should be TTL-keyed dict. "
            f"Treating as 5m value.",
            DeprecationWarning,
            stacklevel=2
        )
        return float(cache_write)

    # Resolve TTL
    if ttl is None:
        ttl = rates.get("default_cache_ttl", "5m")

    val = cache_write.get(ttl)
    if val is not None:
        return float(val)

    return None


def get_session(session_id: str) -> Optional[dict]:
    """
    Fetch a single session row by ID.
    Returns dict or None if not found.
    """
    conn = open_db()
    try:
        row = conn.execute("SELECT * FROM session WHERE id = ?", (session_id,)).fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def get_child_sessions(parent_id: str) -> list:
    """
    Fetch all child sessions (subagent dispatches) for a parent session.
    Returns list of dicts, sorted by time_created.
    """
    conn = open_db()
    try:
        rows = conn.execute(
            "SELECT * FROM session WHERE parent_id = ? ORDER BY time_created",
            (parent_id,)
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def get_session_snapshot(session_id: str) -> Optional[dict]:
    """
    Fetch a lightweight point-in-time snapshot of OC parent cost+tokens.

    Returns dict with fields: cost, tokens_input, tokens_output, tokens_reasoning,
    tokens_cache_read, tokens_cache_write, time_updated. All values coerced to
    float/int (never None). Returns None if session not found.

    This is a lightweight snapshot operation; does NOT call get_session_telemetry().
    """
    conn = open_db()
    try:
        row = conn.execute("SELECT * FROM session WHERE id = ?", (session_id,)).fetchone()
        if row is None:
            return None

        row_dict = dict(row)
        return {
            "cost": float(row_dict.get("cost") or 0),
            "tokens_input": int(row_dict.get("tokens_input") or 0),
            "tokens_output": int(row_dict.get("tokens_output") or 0),
            "tokens_reasoning": int(row_dict.get("tokens_reasoning") or 0),
            "tokens_cache_read": int(row_dict.get("tokens_cache_read") or 0),
            "tokens_cache_write": int(row_dict.get("tokens_cache_write") or 0),
            "time_updated": int(row_dict.get("time_updated") or 0),
        }
    finally:
        conn.close()


def get_child_sessions_in_window(
    parent_id: str, started_at_ms: int, ended_at_ms: int
) -> list:
    """
    Fetch child sessions within a time window.

    Queries SELECT * FROM session WHERE parent_id = ? AND time_created >= ? AND time_created <= ?
    ordered by time_created. Applies a -1000 ms tolerance to started_at_ms (lower bound).

    Args:
        parent_id: parent session ID
        started_at_ms: window start (epoch ms); query uses (started_at_ms - 1000) as lower bound
        ended_at_ms: window end (epoch ms, inclusive)

    Returns list of dicts identical to get_child_sessions().
    """
    conn = open_db()
    try:
        # Apply -1000 ms tolerance to lower bound for s/ms precision skew
        lower_bound = started_at_ms - 1000
        rows = conn.execute(
            "SELECT * FROM session WHERE parent_id = ? AND time_created >= ? AND time_created <= ? ORDER BY time_created",
            (parent_id, lower_bound, ended_at_ms)
        ).fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


def is_session_over(session_id: str) -> bool:
    """
    Check if an orchestra session is complete.

    Hypothesis B (confirmed 2026-05-29): `time_archived` is NULL for all sessions.
    The `time_updated < now - 30 min` fallback is load-bearing.

    Returns True if:
      - Session not found, OR
      - time_archived IS NOT NULL, OR
      - time_updated is more than 30 minutes in the past
    """
    row = get_session(session_id)
    if row is None:
        return True

    if row["time_archived"] is not None:
        return True

    now_ms = int(time.time() * 1000)
    return row["time_updated"] < now_ms - 1_800_000


def _zero_tier() -> dict:
    """Return a zero-valued tier structure for fallback cases."""
    return {
        "agent": "",
        "model": "",
        "provider_model_key": "",
        "cost": 0.0,
        "tokens_input": 0,
        "tokens_output": 0,
        "tokens_reasoning": 0,
        "tokens_cache_read": 0,
        "tokens_cache_write": 0,
    }


def _row_to_tier(row: dict) -> dict:
    """Convert a session row to a tier dict (parent or subagent)."""
    return {
        "agent": row["agent"] or "",
        "model": _parse_model(row["model"]),
        "provider_model_key": _parse_model_full(row["model"]),
        "cost": float(row["cost"] or 0),
        "tokens_input": int(row["tokens_input"] or 0),
        "tokens_output": int(row["tokens_output"] or 0),
        "tokens_reasoning": int(row["tokens_reasoning"] or 0),
        "tokens_cache_read": int(row["tokens_cache_read"] or 0),
        "tokens_cache_write": int(row["tokens_cache_write"] or 0),
    }


def _compute_hybrid_attribution(parent_tier: dict, subagents: list) -> dict:
    """
    Compute hybrid orchestra attribution: marginal costs for each subagent dispatch,
    and hidden (unpaid) hybrid cost on the parent (Brain).

    Args:
        parent_tier: tier dict for the parent session (Brain)
        subagents: list of tier dicts for subagent dispatches

    Returns dict with keys:
        - hybrid_applicable (bool): True if parent model is known and hybrid cost can be computed
        - parent_cache_efficiency_pct (float): advisory; 0 for now (reserved for future read-amortisation)
        - ttl_lapse_flag (bool): advisory; False (reserved for per-turn diagnosis in v7.4+)
        - subagent_marginal_costs (list): [{"agent": "...", "output_tokens": N, "marginal_cost_usd": Y.YY}, ...]
        - hidden_hybrid_cost_usd (float): sum of subagent marginal costs

    Formula: subagent.tokens_output × _get_rate(parent_key, "cache_write") / 1e6
    (ttl parameter omitted; uses default_cache_ttl from YAML)

    If parent model unknown or rate lookup fails, returns all fields with safe defaults:
    {hybrid_applicable: False, parent_cache_efficiency_pct: 0, ttl_lapse_flag: False,
     subagent_marginal_costs: [], hidden_hybrid_cost_usd: 0.0}
    """
    parent_key = parent_tier.get("provider_model_key", "")
    if not parent_key:
        return {
            "hybrid_applicable": False,
            "parent_cache_efficiency_pct": 0,
            "ttl_lapse_flag": False,
            "subagent_marginal_costs": [],
            "hidden_hybrid_cost_usd": 0.0,
        }

    # Look up the marginal rate (cache_write) for the parent model
    marginal_rate = _get_rate(parent_key, "cache_write")
    if marginal_rate is None:
        return {
            "hybrid_applicable": False,
            "parent_cache_efficiency_pct": 0,
            "ttl_lapse_flag": False,
            "subagent_marginal_costs": [],
            "hidden_hybrid_cost_usd": 0.0,
        }

    # Compute marginal cost for each subagent
    subagent_marginal_costs = []
    total_hidden_cost = 0.0

    for subagent in subagents:
        output_tokens = subagent.get("tokens_output", 0)
        if output_tokens == 0:
            continue

        # Marginal cost = output_tokens * rate / 1e6
        marginal_cost = output_tokens * marginal_rate / 1e6
        total_hidden_cost += marginal_cost

        subagent_marginal_costs.append({
            "agent": subagent.get("agent", "unknown"),
            "output_tokens": output_tokens,
            "marginal_cost_usd": round(marginal_cost, 6),
        })

    return {
        "hybrid_applicable": True,
        "parent_cache_efficiency_pct": 0,  # Reserved for future
        "ttl_lapse_flag": False,  # Reserved for per-turn diagnosis in v7.4+
        "subagent_marginal_costs": subagent_marginal_costs,
        "hidden_hybrid_cost_usd": round(total_hidden_cost, 6),
    }


def get_session_telemetry(session_id: str) -> dict:
    """
    Fetch complete telemetry data for an orchestra session.

    Returns dict with keys:
      - parent: tier dict for the parent session
      - subagents: list of tier dicts for child sessions
      - totals: aggregated cost and token counts
      - hybrid_attribution: hybrid orchestra cost attribution (v7.3.5+)
      - not_found (optional): True if session_id not found

    On error, wraps in RuntimeError with context.
    """
    try:
        parent_row = get_session(session_id)
        if parent_row is None:
            return {
                "not_found": True,
                "parent": _zero_tier(),
                "subagents": [],
                "totals": {
                    "cost_usd_estimate": 0.0,
                    "tokens_input": 0,
                    "tokens_output": 0,
                    "tokens_cache_read": 0,
                    "tokens_cache_write": 0,
                },
                "hybrid_attribution": {
                    "hybrid_applicable": False,
                    "parent_cache_efficiency_pct": 0,
                    "ttl_lapse_flag": False,
                    "subagent_marginal_costs": [],
                    "hidden_hybrid_cost_usd": 0.0,
                },
            }

        parent = _row_to_tier(parent_row)
        child_rows = get_child_sessions(session_id)
        subagents = [_row_to_tier(r) for r in child_rows]

        all_tiers = [parent] + subagents
        totals = {
            "cost_usd_estimate": round(sum(t["cost"] for t in all_tiers), 6),
            "tokens_input": sum(t["tokens_input"] for t in all_tiers),
            "tokens_output": sum(t["tokens_output"] for t in all_tiers),
            "tokens_cache_read": sum(t["tokens_cache_read"] for t in all_tiers),
            "tokens_cache_write": sum(t["tokens_cache_write"] for t in all_tiers),
        }

        hybrid_attribution = _compute_hybrid_attribution(parent, subagents)

        return {
            "parent": parent,
            "subagents": subagents,
            "totals": totals,
            "hybrid_attribution": hybrid_attribution,
        }
    except Exception as e:
        raise RuntimeError(f"oc_db.get_session_telemetry failed: {e}") from e
