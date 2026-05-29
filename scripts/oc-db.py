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
from pathlib import Path
from typing import Optional


_DB_PATH = Path.home() / ".local" / "share" / "opencode" / "opencode.db"
_REQUIRED_COLUMNS = {
    "id", "parent_id", "cost", "tokens_input", "tokens_output", "tokens_reasoning",
    "tokens_cache_read", "tokens_cache_write", "model", "agent",
    "time_created", "time_updated", "time_archived", "directory",
}
_schema_checked = False


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
        "agent": row["agent"] or "brain",
        "model": _parse_model(row["model"]),
        "cost": float(row["cost"] or 0),
        "tokens_input": int(row["tokens_input"] or 0),
        "tokens_output": int(row["tokens_output"] or 0),
        "tokens_reasoning": int(row["tokens_reasoning"] or 0),
        "tokens_cache_read": int(row["tokens_cache_read"] or 0),
        "tokens_cache_write": int(row["tokens_cache_write"] or 0),
    }


def get_session_telemetry(session_id: str) -> dict:
    """
    Fetch complete telemetry data for an orchestra session.

    Returns dict with keys:
      - parent: tier dict for the parent session
      - subagents: list of tier dicts for child sessions
      - totals: aggregated cost and token counts
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
        }

        return {
            "parent": parent,
            "subagents": subagents,
            "totals": totals,
        }
    except Exception as e:
        raise RuntimeError(f"oc_db.get_session_telemetry failed: {e}") from e
