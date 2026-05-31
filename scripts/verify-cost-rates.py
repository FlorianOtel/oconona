#!/usr/bin/env python3
"""
verify-cost-rates.py — Standalone rate-drift detector for model-rates.yaml.

Compares per-tier stored costs (from telemetry.json) against rate-based calculation
using model-rates.yaml. Reports OK / WARN / STALE for each tier.

Usage:
  verify-cost-rates.py <session_dir>
  verify-cost-rates.py --session-id <oc_session_id>
  verify-cost-rates.py --tolerance 2.0 <session_dir>

Options:
  --tolerance PCT        Drift tolerance in percent (default 1.0)
  --session-id ID        Use OC session ID directly (reads from DB, not telemetry.json)
  --verbose              Print detailed per-field breakdown

Exit codes:
  0 — all tiers OK or WARN (no drift beyond tolerance)
  1 — at least one tier STALE (drift > tolerance)

Rate lookup for cache_write omits explicit ttl= (picks up YAML default_cache_ttl).
For pre-v7.3.5 sessions (no model-rates.yaml), all non-free models show WARN.
"""

import argparse
import importlib.util
import json
import sys
from pathlib import Path
from typing import Optional, Tuple


def load_rates() -> dict:
    """Load model-rates.yaml. Returns {} if not found."""
    try:
        import yaml
    except ImportError:
        return {}

    rates_path = Path(__file__).parent / "model-rates.yaml"
    if not rates_path.exists():
        return {}

    try:
        with open(rates_path, "r") as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}


def load_telemetry(session_dir: Path) -> dict:
    """Load telemetry.json from session_dir. Returns {} if not found."""
    telemetry_path = session_dir / "telemetry.json"
    if not telemetry_path.exists():
        return {}
    try:
        return json.loads(telemetry_path.read_text())
    except Exception:
        return {}


def load_oc_db() -> Optional[object]:
    """Load oc-db.py via importlib. Returns None on import failure."""
    try:
        spec = importlib.util.spec_from_file_location(
            "oc_db",
            Path(__file__).parent / "oc-db.py"
        )
        oc_db = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(oc_db)
        return oc_db
    except Exception:
        return None


def get_rate(rates: dict, key: str, field: str) -> Optional[float]:
    """
    Look up a rate from the rate dict.
    Returns float or None if not found.
    """
    if not rates:
        return None

    provider_models = rates.get("provider_models", {})
    model_data = provider_models.get(key)
    if not model_data:
        return None

    if field != "cache_write":
        val = model_data.get(field)
        if val is not None:
            return float(val)
        return None

    # cache_write: TTL-keyed sub-map
    cache_write = model_data.get("cache_write")
    if cache_write is None:
        return None

    if not isinstance(cache_write, dict):
        # Backward compat: scalar form treated as 5m value
        return float(cache_write)

    ttl = rates.get("default_cache_ttl", "5m")
    val = cache_write.get(ttl)
    if val is not None:
        return float(val)

    return None


def compute_tier_cost(
    tier: dict, model_key: str, rates: dict
) -> Tuple[Optional[float], str]:
    """
    Compute expected cost for a tier using rates.
    Returns (cost, status_flag) where status_flag is "OK" / "WARN" / "unknown".
    """
    # Check if model is in rates
    if not rates or not rates.get("provider_models"):
        return None, "WARN"

    if model_key not in rates["provider_models"]:
        return None, "WARN"

    # For free-tier models (all costs = 0), return a special marker
    model_data = rates["provider_models"][model_key]
    if (model_data.get("input", 0) == 0 and model_data.get("output", 0) == 0 and
        model_data.get("cache_read", 0) == 0 and model_data.get("cache_write", {}).get("5m", 0) == 0):
        return 0.0, "OK: free-tier"

    # Calculate expected cost
    input_tokens = tier.get("tokens_input", 0)
    output_tokens = tier.get("tokens_output", 0)
    cache_read_tokens = tier.get("tokens_cache_read", 0)
    cache_write_tokens = tier.get("tokens_cache_write", 0)

    input_rate = get_rate(rates, model_key, "input") or 0
    output_rate = get_rate(rates, model_key, "output") or 0
    cache_read_rate = get_rate(rates, model_key, "cache_read") or 0
    cache_write_rate = get_rate(rates, model_key, "cache_write") or 0

    expected_cost = (
        (input_tokens * input_rate) +
        (output_tokens * output_rate) +
        (cache_read_tokens * cache_read_rate) +
        (cache_write_tokens * cache_write_rate)
    ) / 1e6

    return round(expected_cost, 6), "OK"


def check_tier(
    tier: dict, rates: dict, tolerance_pct: float
) -> str:
    """
    Check a single tier against rates.
    Returns status line: "OK: ..." / "WARN: ..." / "STALE: ..."
    """
    agent = tier.get("agent", "unknown")
    model = tier.get("model", "?")
    model_key = tier.get("provider_model_key", "")
    stored_cost = tier.get("cost", 0)

    if not model_key:
        return f"{agent:8} | {model:23} | WARN: unknown model key"

    expected_cost, status = compute_tier_cost(tier, model_key, rates)

    if "free-tier" in status:
        return f"{agent:8} | {model:23} | {status}"

    if expected_cost is None:
        return f"{agent:8} | {model:23} | WARN: {model_key} not in YAML"

    # Check drift
    if expected_cost == 0:
        if stored_cost == 0:
            return f"{agent:8} | {model:23} | OK: zero-cost tier"
        else:
            drift_pct = 100.0
    else:
        drift_pct = abs(stored_cost - expected_cost) / expected_cost * 100.0

    if drift_pct <= tolerance_pct:
        return f"{agent:8} | {model:23} | OK: {stored_cost:.6f} (expected {expected_cost:.6f})"
    else:
        return f"{agent:8} | {model:23} | STALE: {stored_cost:.6f} vs {expected_cost:.6f} ({drift_pct:.1f}% drift)"


def main():
    parser = argparse.ArgumentParser(
        description="Verify per-tier costs against model-rates.yaml"
    )
    parser.add_argument("session_arg", nargs="?", help="Session dir or --session-id required")
    parser.add_argument("--session-id", dest="session_id", help="OC session ID (reads from DB)")
    parser.add_argument("--tolerance", type=float, default=1.0, help="Drift tolerance percent (default 1.0)")
    parser.add_argument("--verbose", action="store_true", help="Print detailed breakdown")
    args = parser.parse_args()

    # Load rates
    rates = load_rates()

    # Load telemetry or OC data
    telemetry = {}
    if args.session_id:
        # Load from OC DB
        oc_db = load_oc_db()
        if oc_db is None:
            print("verify-cost-rates.py: Failed to load oc-db.py", file=sys.stderr)
            sys.exit(1)
        try:
            db_data = oc_db.get_session_telemetry(args.session_id)
            telemetry = {
                "parent": db_data.get("parent", {}),
                "subagents": db_data.get("subagents", []),
            }
        except Exception as e:
            print(f"verify-cost-rates.py: OC query failed: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        if not args.session_arg:
            parser.print_help()
            sys.exit(1)
        session_dir = Path(args.session_arg)
        if not session_dir.exists():
            print(f"verify-cost-rates.py: session_dir not found: {session_dir}", file=sys.stderr)
            sys.exit(1)
        telemetry = load_telemetry(session_dir)

    if not telemetry:
        print("verify-cost-rates.py: No telemetry data found", file=sys.stderr)
        sys.exit(1)

    parent = telemetry.get("parent", {})
    subagents = telemetry.get("subagents", [])

    # Check each tier
    print()
    print("Tier cost verification (tolerance: %.1f%%):" % args.tolerance)
    print()

    all_tiers = [parent] + subagents
    has_stale = False

    for tier in all_tiers:
        status_line = check_tier(tier, rates, args.tolerance)
        print(f"  {status_line}")
        if "STALE:" in status_line:
            has_stale = True

    print()
    sys.exit(1 if has_stale else 0)


if __name__ == "__main__":
    main()
