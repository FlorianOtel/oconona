#!/usr/bin/env python3
"""
native-session-report.py — cost report for OC sessions that are NOT orchestra-wrapped.

OC-SQLite-sourced (v7.x): lists top-level OC sessions (parent_id IS NULL) whose `id`
does NOT appear in any orchestra session_dir's .oc-session-id sidecar. Cost comes
straight from `session.cost` (OC's authoritative column).

Counterpart to `session-report.py`, which lists ONLY orchestra sessions. Together
they cover the full set of OC sessions on the host.

Usage:
  native-session-report.py [--last N] [--since YYYY-MM-DD] [--month YYYY-MM]
                           [--project PATH] [--min-cost X] [--json]
                           [--exclude-orchestra]

Args:
  --last N             Show the last N sessions (default 20)
  --since YYYY-MM-DD   Show sessions from this date onwards
  --month YYYY-MM      Show sessions in this month (UTC)
  --project PATH       Filter by session.directory prefix (substring match on basename)
  --min-cost X         Filter cost >= X USD
  --json               Output as JSON instead of table
  --exclude-orchestra  Arg-surface parity with claude-orchestra. No-op in OC era —
                       orchestra sessions are already excluded by design.
"""

import argparse
import importlib.util
import json
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Set


# Load the hyphenated oc-db.py via importlib (same pattern as telemetry-summarize.py).
_SPEC = importlib.util.spec_from_file_location(
    "oc_db", Path(__file__).parent / "oc-db.py"
)
oc_db = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(oc_db)


def load_orchestra_session_ids() -> Set[str]:
    """Walk ~/.config/opencode/orchestra/sessions/*/.oc-session-id and collect the set
    of OC session IDs that ARE orchestra-wrapped. Used to exclude from the native report."""
    sessions_root = Path.home() / ".config/opencode/orchestra/sessions"
    ids: Set[str] = set()
    if not sessions_root.is_dir():
        return ids
    for sidecar in sessions_root.glob("*/.oc-session-id"):
        try:
            content = sidecar.read_text().strip()
            if content:
                ids.add(content)
        except Exception:
            pass
    return ids


def load_native_sessions() -> List[Dict[str, Any]]:
    """Query OC's DB for all top-level sessions, excluding orchestra-wrapped ones."""
    orchestra_ids = load_orchestra_session_ids()
    conn = oc_db.open_db()
    try:
        rows = conn.execute(
            "SELECT * FROM session WHERE parent_id IS NULL ORDER BY time_created DESC"
        ).fetchall()
        return [dict(r) for r in rows if r["id"] not in orchestra_ids]
    finally:
        conn.close()


def parse_session_time(row: Dict[str, Any]) -> datetime:
    """OC stores time_created as epoch milliseconds."""
    return datetime.fromtimestamp(row["time_created"] / 1000, tz=timezone.utc)


def apply_filters(rows: List[Dict[str, Any]], args: argparse.Namespace) -> List[Dict[str, Any]]:
    """Apply --since, --month, --project, --min-cost, --last (in that order)."""
    filtered = rows

    if args.since:
        try:
            since_dt = datetime.strptime(args.since, "%Y-%m-%d").replace(tzinfo=timezone.utc)
            filtered = [r for r in filtered if parse_session_time(r) >= since_dt]
        except ValueError:
            pass

    if args.month:
        try:
            month_dt = datetime.strptime(args.month, "%Y-%m").replace(tzinfo=timezone.utc)
            month_next = (month_dt.replace(day=28) + timedelta(days=4)).replace(day=1)
            filtered = [
                r for r in filtered
                if month_dt <= parse_session_time(r) < month_next
            ]
        except ValueError:
            pass

    if args.project:
        needle = args.project.lower()
        filtered = [
            r for r in filtered
            if needle in (r.get("directory") or "").lower()
        ]

    if args.min_cost is not None:
        filtered = [r for r in filtered if (r["cost"] or 0) >= args.min_cost]

    if args.last:
        filtered = filtered[: args.last]

    return filtered


def format_row(row: Dict[str, Any]) -> Dict[str, str]:
    """Convert an OC session row into display-ready string fields."""
    date_str = parse_session_time(row).strftime("%Y-%m-%d--%H-%M")
    project = Path(row.get("directory") or "-").name or "-"
    model_raw = oc_db._parse_model(row["model"])
    duration_ms = (row["time_updated"] or row["time_created"]) - row["time_created"]
    duration_s = max(0, duration_ms // 1000)
    cost = row["cost"] or 0
    tokens = sum([
        row["tokens_input"] or 0,
        row["tokens_output"] or 0,
        row["tokens_cache_read"] or 0,
        row["tokens_cache_write"] or 0,
    ])
    return {
        "date": date_str,
        "project": project[:17],
        "model": model_raw[:23],
        "tokens": f"{tokens:,}" if tokens else "-",
        "cost": f"${cost:.4f}" if cost else "$0.0000",
        "duration": f"{duration_s}s",
        "outcome": "-",  # native sessions have no orchestra outcome
        "id": row["id"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Cost report for OC sessions NOT orchestra-wrapped."
    )
    parser.add_argument("--last", type=int, default=20, help="Show the last N sessions")
    parser.add_argument("--since", help="Show sessions since YYYY-MM-DD")
    parser.add_argument("--month", help="Show sessions in YYYY-MM (UTC)")
    parser.add_argument("--project", help="Filter by session.directory substring")
    parser.add_argument("--min-cost", type=float, dest="min_cost",
                        help="Filter cost >= X USD")
    parser.add_argument("--json", action="store_true",
                        help="Output JSON instead of table")
    parser.add_argument("--exclude-orchestra", action="store_true",
                        help="No-op in OC era (orchestra sessions are already excluded)")
    args = parser.parse_args()

    if args.exclude_orchestra:
        print("# --exclude-orchestra is the default in OC era; flag is a no-op", file=sys.stderr)

    rows = load_native_sessions()
    filtered = apply_filters(rows, args)
    display = [format_row(r) for r in filtered]

    if args.json:
        json.dump(display, sys.stdout, indent=2)
        sys.stdout.write("\n")
        return 0

    print()
    print(f"{'Date':<17} {'Project':<17} {'Model':<23} {'Tokens':>10}  {'Cost':>9}  {'Dur':>6}  Outcome")
    print("-" * 106)
    total_cost = 0.0
    total_tokens = 0
    for rec in display:
        print(
            f"{rec['date']:<17} {rec['project']:<17} {rec['model']:<23} "
            f"{rec['tokens']:>10}  {rec['cost']:>9}  {rec['duration']:>6}  {rec['outcome']}"
        )
        try:
            if rec["cost"].startswith("$"):
                total_cost += float(rec["cost"][1:])
            if rec["tokens"] != "-":
                total_tokens += int(rec["tokens"].replace(",", ""))
        except (ValueError, AttributeError):
            pass

    print()
    print("--- Aggregates ---")
    print(f"Sessions : {len(display)}")
    print(f"Tokens   : {total_tokens:,}")
    print(f"Cost     : ${total_cost:.4f}")
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
