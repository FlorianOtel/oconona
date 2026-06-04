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
  ${session_dir}/.parent-snapshot-start  — OC parent snapshot at T1 (v7.5+)
  ${session_dir}/.parent-snapshot-end    — OC parent snapshot at T2 (v7.5+)

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
from typing import Any, Dict, Optional


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


def _read_snapshot(path: Path) -> dict:
    """
    Read a snapshot sidecar JSON file.

    Returns the parsed dict, or {} if missing/invalid/empty.
    """
    if not path.exists():
        return {}
    try:
        text = path.read_text().strip()
        if not text:
            return {}
        data = json.loads(text)
        if not data:  # Empty JSON object {}
            return {}
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _compute_parent_delta(snap_start: dict, snap_end: dict) -> Dict[str, Any]:
    """
    Compute per-segment delta from start and end snapshots.

    Returns dict with six fields (cost, tokens_input, tokens_output, tokens_reasoning,
    tokens_cache_read, tokens_cache_write) as deltas (end - start, floored at 0).
    All-zeros dict on any failure.

    Also extracts timestamps: started_at_oc_ms and ended_at_oc_ms from snapshot time_updated.
    """
    delta = {
        "cost": 0.0,
        "tokens_input": 0,
        "tokens_output": 0,
        "tokens_reasoning": 0,
        "tokens_cache_read": 0,
        "tokens_cache_write": 0,
    }

    try:
        if not snap_start or not snap_end:
            return delta

        # Compute deltas, floor at 0
        delta["cost"] = max(0.0, float(snap_end.get("cost", 0)) - float(snap_start.get("cost", 0)))
        delta["tokens_input"] = max(0, int(snap_end.get("tokens_input", 0)) - int(snap_start.get("tokens_input", 0)))
        delta["tokens_output"] = max(0, int(snap_end.get("tokens_output", 0)) - int(snap_start.get("tokens_output", 0)))
        delta["tokens_reasoning"] = max(0, int(snap_end.get("tokens_reasoning", 0)) - int(snap_start.get("tokens_reasoning", 0)))
        delta["tokens_cache_read"] = max(0, int(snap_end.get("tokens_cache_read", 0)) - int(snap_start.get("tokens_cache_read", 0)))
        delta["tokens_cache_write"] = max(0, int(snap_end.get("tokens_cache_write", 0)) - int(snap_start.get("tokens_cache_write", 0)))
    except Exception:
        pass

    return delta


def _zero_struct() -> Dict[str, Any]:
    """Return a zero-valued telemetry data structure for fallback cases."""
    zero_tier = {
        "agent": "", "model": "", "provider_model_key": "", "cost": 0.0,
        "tokens_input": 0, "tokens_output": 0, "tokens_reasoning": 0,
        "tokens_cache_read": 0, "tokens_cache_write": 0,
    }
    return {
        "parent": zero_tier.copy(),
        "parent_delta": zero_tier.copy(),
        "parent_total": zero_tier.copy(),
        "subagents": [],
        "totals": {"cost_usd_estimate": 0.0, "tokens_input": 0,
                   "tokens_output": 0, "tokens_cache_read": 0},
        "hybrid_attribution": {
            "hybrid_applicable": False,
            "parent_cache_efficiency_pct": 0,
            "ttl_lapse_flag": False,
            "subagent_marginal_costs": [],
            "hidden_hybrid_cost_usd": 0.0,
        },
        "started_at_oc_ms": 0,
        "ended_at_oc_ms": 0,
        "parent_snapshot_start": {},
        "parent_snapshot_end": {},
        "parser_warnings": [],
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

    # Read snapshot sidecars (v7.5+)
    snap_start = _read_snapshot(session_dir / ".parent-snapshot-start")
    snap_end = _read_snapshot(session_dir / ".parent-snapshot-end")

    # Fetch telemetry data from OC SQLite
    db_data = _zero_struct()
    cost_source = "none"
    parser_warnings = []
    started_at_oc_ms = 0
    ended_at_oc_ms = 0

    if oc_session_id:
        try:
            spec = importlib.util.spec_from_file_location(
                "oc_db",
                Path(__file__).parent / "oc-db.py"
            )
            oc_db = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(oc_db)

            # Extract time windows from snapshots
            if snap_start:
                started_at_oc_ms = int(snap_start.get("time_updated", 0))
            if snap_end:
                ended_at_oc_ms = int(snap_end.get("time_updated", 0))

            # Segment-attribution code path: if both snapshots are present and have timestamps
            if snap_start and snap_end and started_at_oc_ms > 0 and ended_at_oc_ms > 0:
                try:
                    parent_row = oc_db.get_session(oc_session_id)
                    if parent_row is None:
                        raise RuntimeError(f"parent session {oc_session_id} not found")

                    parent_total = oc_db._row_to_tier(parent_row)
                    parent_delta = _compute_parent_delta(snap_start, snap_end)

                    # Fetch children in the time window
                    children_rows = oc_db.get_child_sessions_in_window(
                        oc_session_id, started_at_oc_ms, ended_at_oc_ms
                    )
                    subagents = [oc_db._row_to_tier(r) for r in children_rows]

                    # v8.1.2: subagents.jsonl sidecar fallback for OC daemon agent/model regression.
                    # When OC daemon fails to populate agent/model on child sessions (regression in
                    # 0.0.0-fix/subagent-session-directory-inheritance-202606012118), read the
                    # orchestra-dir sidecar that commands/brain.md wrote at dispatch time and patch
                    # empty fields. Match by chronological order (both DB rows and sidecar lines are
                    # ordered by dispatch time within a pipeline).
                    sidecar_path = Path(session_dir) / "subagents.jsonl"
                    if sidecar_path.exists():
                        try:
                            sidecar_entries = []
                            for line in sidecar_path.read_text().splitlines():
                                line = line.strip()
                                if not line:
                                    continue
                                try:
                                    sidecar_entries.append(json.loads(line))
                                except json.JSONDecodeError:
                                    continue  # skip malformed lines silently
                            # Patch empty agent/model in subagents list, matched by index
                            for i, sub in enumerate(subagents):
                                if i >= len(sidecar_entries):
                                    break
                                if not sub.get("agent"):
                                    sub["agent"] = sidecar_entries[i].get("agent", "")
                                if not sub.get("model"):
                                    sub["model"] = sidecar_entries[i].get("model", "")
                                    # provider_model_key may be left empty; the merge below would need
                                    # to mirror it if downstream consumers depend on it.
                                    # For now, set it from the sidecar's model value:
                                    if sub["model"] and not sub.get("provider_model_key"):
                                        sub["provider_model_key"] = sub["model"]
                        except Exception as e:
                            # Record but do not fail the pipeline
                            parser_warnings.append({"code": "sidecar_read_failed", "message": str(e)})

                    # Build parent dict with delta semantics (for compatibility with session-report.py)
                    parent = parent_total.copy()
                    parent["cost"] = parent_delta["cost"]
                    parent["tokens_input"] = parent_delta["tokens_input"]
                    parent["tokens_output"] = parent_delta["tokens_output"]
                    parent["tokens_reasoning"] = parent_delta["tokens_reasoning"]
                    parent["tokens_cache_read"] = parent_delta["tokens_cache_read"]
                    parent["tokens_cache_write"] = parent_delta["tokens_cache_write"]

                    # Compute cost estimate and totals
                    cost_usd_estimate = parent_delta["cost"] + sum(c["cost"] for c in subagents)
                    totals = {
                        "cost_usd_estimate": round(cost_usd_estimate, 6),
                        "tokens_input": parent_delta["tokens_input"] + sum(c["tokens_input"] for c in subagents),
                        "tokens_output": parent_delta["tokens_output"] + sum(c["tokens_output"] for c in subagents),
                        "tokens_cache_read": parent_delta["tokens_cache_read"] + sum(c["tokens_cache_read"] for c in subagents),
                        "tokens_cache_write": parent_delta["tokens_cache_write"] + sum(c["tokens_cache_write"] for c in subagents),
                    }

                    # Compute hybrid attribution (with segment-delta parent)
                    hybrid_attribution = oc_db._compute_hybrid_attribution(parent, subagents)

                    db_data = {
                        "parent": parent,
                        "parent_delta": parent_delta,
                        "parent_total": parent_total,
                        "subagents": subagents,
                        "totals": totals,
                        "hybrid_attribution": hybrid_attribution,
                        "started_at_oc_ms": started_at_oc_ms,
                        "ended_at_oc_ms": ended_at_oc_ms,
                        "parent_snapshot_start": snap_start,
                        "parent_snapshot_end": snap_end,
                        "parser_warnings": [],
                    }
                    cost_source = "oc_sqlite"

                except RuntimeError as e:
                    print(f"telemetry-summarize.py: segment attribution failed: {e}", file=sys.stderr)
                    # Fallback to zero struct
                    db_data = _zero_struct()
                    parser_warnings.append({
                        "code": "segment_attribution_failed",
                        "message": str(e)
                    })
            else:
                # Fallback: no snapshots or incomplete snapshots
                if oc_session_id and (snap_start or snap_end):
                    parser_warnings.append({
                        "code": "snapshot_missing",
                        "message": "snapshot sidecars missing or incomplete; using whole-parent attribution"
                    })

                # Whole-parent attribution (original logic)
                db_data = oc_db.get_session_telemetry(oc_session_id)
                if not db_data.get("not_found"):
                    cost_source = "oc_sqlite"
                else:
                    print(
                        f"telemetry-summarize.py: OC session {oc_session_id!r} not found in DB; cost=0",
                        file=sys.stderr,
                    )

                # v8.1.2: subagents.jsonl sidecar fallback for OC daemon agent/model regression (fallback path).
                subagents = db_data.get("subagents", [])
                sidecar_path = Path(session_dir) / "subagents.jsonl"
                if sidecar_path.exists():
                    try:
                        sidecar_entries = []
                        for line in sidecar_path.read_text().splitlines():
                            line = line.strip()
                            if not line:
                                continue
                            try:
                                sidecar_entries.append(json.loads(line))
                            except json.JSONDecodeError:
                                continue  # skip malformed lines silently
                        # Patch empty agent/model in subagents list, matched by index
                        for i, sub in enumerate(subagents):
                            if i >= len(sidecar_entries):
                                break
                            if not sub.get("agent"):
                                sub["agent"] = sidecar_entries[i].get("agent", "")
                            if not sub.get("model"):
                                sub["model"] = sidecar_entries[i].get("model", "")
                                if sub["model"] and not sub.get("provider_model_key"):
                                    sub["provider_model_key"] = sub["model"]
                    except Exception as e:
                        # Record but do not fail the pipeline
                        parser_warnings.append({"code": "sidecar_read_failed", "message": str(e)})

                # Inject new fields into fallback data
                db_data["parent_delta"] = db_data["parent"].copy()
                db_data["parent_total"] = db_data["parent"].copy()
                db_data["started_at_oc_ms"] = 0
                db_data["ended_at_oc_ms"] = 0
                db_data["parent_snapshot_start"] = snap_start
                db_data["parent_snapshot_end"] = snap_end
                db_data["parser_warnings"] = parser_warnings

        except RuntimeError as e:
            print(f"telemetry-summarize.py: oc_db error: {e}", file=sys.stderr)
            db_data = _zero_struct()
            db_data["parser_warnings"] = parser_warnings
    else:
        print(
            "telemetry-summarize.py: .oc-session-id sidecar missing or empty; "
            "cost_source=none (normal until v7.2 ships)",
            file=sys.stderr,
        )
        db_data = _zero_struct()

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
        "parent_delta": db_data.get("parent_delta", _zero_struct()["parent_delta"]),
        "parent_total": db_data.get("parent_total", _zero_struct()["parent_total"]),
        "subagents": db_data["subagents"],
        "totals": db_data["totals"],
        "cost_usd_estimate": cost_usd_estimate,  # top-level mirror for octmux Stage 8 compat
        "cost_source": cost_source,
        "project_dir": project_dir,
        "status": args.status,
        "hybrid_attribution": db_data.get("hybrid_attribution", {
            "hybrid_applicable": False,
            "parent_cache_efficiency_pct": 0,
            "ttl_lapse_flag": False,
            "subagent_marginal_costs": [],
            "hidden_hybrid_cost_usd": 0.0,
        }),
        "started_at_oc_ms": db_data.get("started_at_oc_ms", 0),
        "ended_at_oc_ms": db_data.get("ended_at_oc_ms", 0),
        "parent_snapshot_start": db_data.get("parent_snapshot_start", {}),
        "parent_snapshot_end": db_data.get("parent_snapshot_end", {}),
        "parser_warnings": db_data.get("parser_warnings", []),
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

    # Extended summary: include "delta=" when segment attribution active
    if started_at_oc_ms > 0 and ended_at_oc_ms > 0:
        print(
            f"telemetry: delta=${cost_usd_estimate:.4f} total=${db_data.get('parent_total', {}).get('cost', 0):.4f} "
            f"source={cost_source} session={session_dir.name}",
            flush=True,
        )
    else:
        print(
            f"telemetry: cost=${cost_usd_estimate:.4f} source={cost_source} "
            f"session={session_dir.name}",
            flush=True,
        )


if __name__ == "__main__":
    main()
