#!/usr/bin/env python3
"""
telemetry-summarize.py — produce per-session telemetry.json from OC SQLite.

Usage:
  telemetry-summarize.py <session_dir> <command> <outcome> [ignored_4th_arg]
                          [--status final|in_flight]

Reads:
  ${session_dir}/.oc-session-id  — OC session UUID (written by v7.2+ commands)
  ${session_dir}/.project-dir    — project attribution
  ${session_dir}/.outcome        — outcome (fallback if arg is empty)

Produces:
  ${session_dir}/telemetry.json  — full per-session record (atomic write)
  stdout: one-line summary

Does NOT write to ~/.config/opencode/orchestra/telemetry.jsonl (global log dropped in v7.1).
"""

import argparse
import importlib.util
import json
import os
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict


def to_iso8601(unix_time: float) -> str:
    return datetime.fromtimestamp(unix_time, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def read_outcome(session_dir: Path) -> str:
    outcome_file = session_dir / ".outcome"
    if outcome_file.exists():
        try:
            return outcome_file.read_text().strip()
        except Exception:
            pass
    return "partial"


def _zero_struct() -> Dict[str, Any]:
    """Return a zero-valued telemetry data structure for fallback cases."""
    zero_tier = {
        "agent": "", "model": "", "cost": 0.0,
        "tokens_input": 0, "tokens_output": 0, "tokens_reasoning": 0,
        "tokens_cache_read": 0, "tokens_cache_write": 0,
    }
    return {
        "parent": zero_tier.copy(),
        "subagents": [],
        "totals": {"cost_usd_estimate": 0.0, "tokens_input": 0,
                   "tokens_output": 0, "tokens_cache_read": 0},
    }


def main():
    parser = argparse.ArgumentParser(
        description="Produce per-session telemetry.json from OC SQLite."
    )
    parser.add_argument("session_dir", help="Absolute path to orchestra session subdir")
    parser.add_argument("command", choices=["brain", "duo"], help="Command type")
    parser.add_argument(
        "outcome",
        choices=["pass", "fix-loop", "block", "abandoned", "partial"],
        help="Session outcome",
    )
    parser.add_argument(
        "transcript_session_id",
        nargs="?",
        default="",
        help="Vestigial positional argument (ignored in v7.1+; .oc-session-id sidecar used instead)",
    )
    parser.add_argument(
        "--status",
        choices=["final", "in_flight"],
        default="final",
        help="Write status field in telemetry.json. 'in_flight' marks as in-progress.",
    )
    args = parser.parse_args()

    session_dir = Path(args.session_dir)
    if not session_dir.exists():
        print(f"telemetry-summarize.py: session_dir not found: {session_dir}", file=sys.stderr)
        sys.exit(1)

    # Project attribution from sidecar
    project_dir_file = session_dir / ".project-dir"
    project_dir = project_dir_file.read_text().strip() if project_dir_file.exists() else ""

    # OC session ID from sidecar (written by v7.2+ commands; absent until then)
    oc_id_file = session_dir / ".oc-session-id"
    oc_session_id = ""
    if oc_id_file.exists():
        try:
            oc_session_id = oc_id_file.read_text().strip()
        except Exception:
            pass

    # Timestamps: started_at from session_dir basename; ended_at from .outcome mtime
    started_at_unix = time.time()
    m = re.match(r"^(\d{8}T\d{6}Z)-\d+$", session_dir.name)
    if m:
        try:
            dt = datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
            started_at_unix = dt.timestamp()
        except Exception:
            pass

    outcome_path = session_dir / ".outcome"
    if outcome_path.exists():
        try:
            ended_at_unix = outcome_path.stat().st_mtime
        except Exception:
            ended_at_unix = time.time()
    else:
        ended_at_unix = time.time()

    # Fetch telemetry data from OC SQLite
    db_data = _zero_struct()
    cost_source = "none"

    if oc_session_id:
        try:
            spec = importlib.util.spec_from_file_location(
                "oc_db",
                Path(__file__).parent / "oc-db.py"
            )
            oc_db = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(oc_db)
            db_data = oc_db.get_session_telemetry(oc_session_id)
            if not db_data.get("not_found"):
                cost_source = "oc_sqlite"
            else:
                print(
                    f"telemetry-summarize.py: OC session {oc_session_id!r} not found in DB; cost=0",
                    file=sys.stderr,
                )
        except RuntimeError as e:
            print(f"telemetry-summarize.py: oc_db error: {e}", file=sys.stderr)
    else:
        print(
            "telemetry-summarize.py: .oc-session-id sidecar missing or empty; "
            "cost_source=none (normal until v7.2 ships)",
            file=sys.stderr,
        )

    cost_usd_estimate = db_data["totals"]["cost_usd_estimate"]
    outcome = args.outcome if args.outcome else read_outcome(session_dir)

    telemetry = {
        "session_id": session_dir.name,
        "oc_session_id": oc_session_id,
        "command": args.command,
        "started_at": to_iso8601(started_at_unix),
        "ended_at": to_iso8601(ended_at_unix),
        "duration_s": int(ended_at_unix - started_at_unix),
        "outcome": outcome,
        "parent": db_data["parent"],
        "subagents": db_data["subagents"],
        "totals": db_data["totals"],
        "cost_usd_estimate": cost_usd_estimate,  # top-level mirror for octmux Stage 8 compat
        "cost_source": cost_source,
        "project_dir": project_dir,
        "status": args.status,
    }

    # Atomic write
    telemetry_path = session_dir / "telemetry.json"
    telemetry_tmp = session_dir / "telemetry.json.tmp"
    try:
        with open(telemetry_tmp, "w") as f:
            json.dump(telemetry, f, indent=2)
        os.replace(telemetry_tmp, telemetry_path)
    except Exception as e:
        print(f"telemetry-summarize.py: failed to write telemetry.json: {e}", file=sys.stderr)
        sys.exit(1)

    print(
        f"telemetry: cost=${cost_usd_estimate:.4f} source={cost_source} "
        f"session={session_dir.name}",
        flush=True,
    )


if __name__ == "__main__":
    main()
