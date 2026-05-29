#!/usr/bin/env python3
"""
session-report.py — Cost report for orchestra sessions (v7.1+).

Usage: session-report.py [--last N] [--since DATE] [--month YYYY-MM] [--source orchestra|brain|duo|all]

Reads telemetry from ~/.config/opencode/orchestra/sessions/*/telemetry.json

Produces a unified tabular report with filtering and aggregation.

--source options:
  orchestra — any orchestra command (brain, duo, etc.; default)
  brain     — /brain command sessions only
  duo       — /duo command sessions only
  all       — alias for orchestra (for backward compatibility)
"""

import argparse
import json
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


def parse_iso8601(timestamp_str: str) -> datetime:
    """Parse ISO-8601 timestamp to datetime."""
    try:
        return datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))
    except Exception:
        return datetime.now(timezone.utc)


def load_orchestra_telemetry_v2() -> List[Dict[str, Any]]:
    """Load telemetry from ~/.config/opencode/orchestra/sessions/*/telemetry.json (v7.1+)."""
    sessions_root = Path.home() / ".config/opencode/orchestra/sessions"
    records = []
    if sessions_root.is_dir():
        for tf in sorted(sessions_root.glob("*/telemetry.json")):
            try:
                rec = json.loads(tf.read_text())
                rec.setdefault("source", rec.get("command", "orchestra"))
                rec["session_dir"] = str(tf.parent)
                records.append(rec)
            except Exception:
                pass
    return records


def extract_project_name(session_dir: str) -> str:
    """Extract project name from session_dir path.

    Pattern: <project_dir>/.opencode/orchestra/sessions/<session_id>
    Returns: basename of <project_dir>

    Tries to read project_dir from telemetry.json if available.
    Falls back to path-based inference for legacy sessions.
    """
    # Try to read project_dir from telemetry.json if available
    try:
        telemetry_file = Path(session_dir) / "telemetry.json"
        if telemetry_file.exists():
            with open(telemetry_file) as f:
                tel = json.loads(f.read())
                if tel.get("project_dir"):
                    return Path(tel["project_dir"]).name
    except Exception:
        pass

    # Legacy fallback: infer from path
    try:
        path = Path(session_dir)
        # Remove /.opencode/orchestra/sessions/<session_id>
        parts = path.parts
        # Find .opencode index
        if ".opencode" in parts:
            idx = parts.index(".opencode")
            if idx > 0:
                return parts[idx - 1]
    except Exception:
        pass
    return "-"


def format_cost(cost: float, cost_source: str = "") -> str:
    """Format cost as $X.XXXX.

    For cost_source == "oc_sqlite", display $0.0000 even when cost is 0 (flat-rate models).
    For other sources, display '-' when cost is 0.
    """
    if cost is None:
        return "-"
    if cost == 0:
        return "$0.0000" if cost_source == "oc_sqlite" else "-"
    return f"${cost:.4f}"


def format_duration(duration_s: int) -> str:
    """Format duration in seconds as readable string."""
    if duration_s < 0:
        return "-"
    return f"{duration_s}s"


def apply_filters(records: List[Dict[str, Any]], args: argparse.Namespace) -> List[Dict[str, Any]]:
    """Apply --last, --since, --month, --source filters."""
    filtered = records

    # --source filter
    if args.source in ("all", "orchestra"):
        pass  # include everything
    else:
        # specific command: "brain", "duo", etc.
        filtered = [r for r in filtered if r.get("source") == args.source]

    # Sort by started_at descending (most recent first)
    filtered.sort(
        key=lambda r: parse_iso8601(r.get("started_at", "")).timestamp(),
        reverse=True
    )

    # --since filter (date string YYYY-MM-DD)
    if args.since:
        try:
            since_dt = datetime.strptime(args.since, "%Y-%m-%d").replace(tzinfo=timezone.utc)
            filtered = [
                r for r in filtered
                if parse_iso8601(r.get("started_at", "")) >= since_dt
            ]
        except Exception:
            pass

    # --month filter (YYYY-MM)
    if args.month:
        try:
            month_dt = datetime.strptime(args.month, "%Y-%m").replace(tzinfo=timezone.utc)
            month_next = (month_dt.replace(day=28) + timedelta(days=4)).replace(day=1)
            filtered = [
                r for r in filtered
                if month_dt <= parse_iso8601(r.get("started_at", "")) < month_next
            ]
        except Exception:
            pass

    # --last filter
    if args.last:
        filtered = filtered[: args.last]

    return filtered


def main():
    parser = argparse.ArgumentParser(
        description="Cost report for orchestra sessions (v7.1+)."
    )
    parser.add_argument("--last", type=int, help="Show last N sessions")
    parser.add_argument("--since", help="Show sessions since DATE (YYYY-MM-DD)")
    parser.add_argument("--month", help="Show sessions in YYYY-MM")
    parser.add_argument(
        "--source", choices=["orchestra", "brain", "duo", "all"], default="orchestra",
        help="Filter by source: brain, duo, or orchestra (any non-native)"
    )
    args = parser.parse_args()

    # Load all records (v7.1+)
    all_records = load_orchestra_telemetry_v2()

    # Apply filters
    filtered_records = apply_filters(all_records, args)

    # Prepare display records
    display_records = []
    for rec in filtered_records:
        # Extract tokens from totals
        totals = rec.get("totals", {})
        tokens_in = totals.get("tokens_input", 0)
        tokens_out = totals.get("tokens_output", 0)
        total_tokens = tokens_in + tokens_out
        tok_str = f"{total_tokens:,}" if total_tokens else "-"

        # Extract model from parent
        parent = rec.get("parent", {})
        raw_model = parent.get("model", "-") if parent else "-"
        if raw_model and raw_model != "-":
            # Clean up model name
            import re
            raw_model = re.sub(r'\[.*?\]$', '', raw_model)
            raw_model = re.sub(r'-\d{8}$', '', raw_model)

        # Extract cost and source
        cost_usd = totals.get("cost_usd_estimate", 0)
        cost_source = rec.get("cost_source", "")

        # Derive project name
        session_dir = rec.get("session_dir", "")
        project = extract_project_name(session_dir) if session_dir else "-"

        display_records.append({
            "date": parse_iso8601(rec.get("started_at", "")).strftime("%Y-%m-%d--%H-%M"),
            "source": rec.get("source", "-"),
            "project": project,
            "model": raw_model,
            "tokens": tok_str,
            "cost": format_cost(cost_usd, cost_source),
            "duration": format_duration(rec.get("duration_s", 0)),
            "outcome": rec.get("outcome", "-"),
        })

    # Print header
    print()
    print(f"{'Date':<17} {'Source':<8} {'Project':<17} {'Model':<23} {'Tokens':>10}  {'Cost':>9}  {'Dur':>6}  Outcome")
    print("-" * 106)

    # Print rows with alignment
    total_cost = 0.0
    total_tokens = 0
    session_count = 0
    for rec in display_records:
        date_str = rec["date"].ljust(17)
        source_str = rec["source"].ljust(8)
        project_str = rec["project"][:17].ljust(17)
        model_str = rec["model"][:23].ljust(23)
        tokens_str = rec["tokens"].rjust(10)
        cost_str = rec["cost"].rjust(9)
        dur_str = rec["duration"].rjust(6)
        outcome_str = rec["outcome"]
        print(f"{date_str} {source_str} {project_str} {model_str} {tokens_str}  {cost_str}  {dur_str}  {outcome_str}")

        # Accumulate cost and tokens
        try:
            if rec["cost"] != "-" and rec["cost"].startswith("$"):
                total_cost += float(rec["cost"][1:])
            if rec["tokens"] != "-":
                total_tokens += int(rec["tokens"].replace(",", ""))
            session_count += 1
        except Exception:
            pass

    # Print aggregates
    print()
    print("--- Aggregates ---")
    print(f"Sessions : {session_count}")
    print(f"Tokens   : {total_tokens:,}")
    print(f"Cost     : ${total_cost:.4f}")
    print()


if __name__ == "__main__":
    main()
