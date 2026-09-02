#!/usr/bin/env python3
"""Backfill: recompute historical session costs under the current pricing.

Run this after any change to ``MODEL_PRICING`` or the cost parser. It rewrites
every session's cost and per-category cost breakdown, then rebuilds
``daily_stats.cost`` from the corrected sessions. It also repairs sessions
recorded before the server:
  * priced subagent transcripts (``<session>/subagents/*.jsonl``) at all,
  * priced 1-hour-TTL cache writes at the 2x rate instead of 1.25x,
  * knew Opus 5 / Sonnet 5 / Fable 5.1 pricing.

Two recompute paths per session:
  * transcript  — re-read ~/.claude/projects/*/<session_id>.jsonl plus its
                  subagent transcripts and price per message (exact; refreshes
                  token counts too).
  * tokens      — transcript gone: reprice the stored token totals with the
                  session's model (approximate: single-model, 5m cache TTL).

Sessions with neither a transcript nor stored tokens are left untouched.

Usage:
    python backfill_costs.py            # apply the fix
    python backfill_costs.py --dry-run  # preview, write nothing
"""

import argparse
import os
import sqlite3
import sys
from pathlib import Path

import app  # reuse the server's pricing tables and transcript parser

# Claude Code stores transcripts under <config dir>/projects/<encoded-cwd>/.
# Honor CLAUDE_CONFIG_DIR like the CLI does; default to ~/.claude.
_CONFIG_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude"))
TRANSCRIPT_ROOT = _CONFIG_DIR / "projects"

# Columns the fix depends on; add them if the server hasn't migrated yet.
_COST_COLUMNS = ("input_cost", "output_cost", "cache_write_cost", "cache_read_cost")


def _ensure_columns(conn: sqlite3.Connection) -> None:
    existing = {row[1] for row in conn.execute("PRAGMA table_info(sessions)")}
    for col in _COST_COLUMNS:
        if col not in existing:
            conn.execute(f"ALTER TABLE sessions ADD COLUMN {col} REAL DEFAULT 0.0")


def _find_transcript(session_id: str) -> Path | None:
    if not session_id or session_id == "unknown":
        return None
    matches = list(TRANSCRIPT_ROOT.glob(f"*/{session_id}.jsonl"))
    if not matches:
        return None
    # A resumed session can appear under more than one project dir; the largest
    # file is the most complete transcript.
    return max(matches, key=lambda p: p.stat().st_size)


def _recompute(row: sqlite3.Row) -> tuple[dict | None, str]:
    """Return (details, source) or (None, 'skipped') if nothing to price."""
    transcript = _find_transcript(row["session_id"])
    if transcript is not None:
        details = app.estimate_session_cost(str(transcript))
        # A transcript with no usage lines yields cost 0 — don't let that wipe a
        # session that still has stored token counts; fall through to tokens.
        if details["cost"] > 0 or details["input_tokens"] or details["output_tokens"]:
            return details, "transcript"

    tokens = (
        row["input_tokens"] or 0,
        row["output_tokens"] or 0,
        row["cache_write_tokens"] or 0,
        row["cache_read_tokens"] or 0,
    )
    if any(tokens):
        details = app.cost_from_tokens(row["model"] or "", *tokens)
        # cost_from_tokens doesn't touch token totals; carry the stored ones.
        details = {**details, "model": row["model"] or "",
                   "input_tokens": tokens[0], "output_tokens": tokens[1],
                   "cache_write_tokens": tokens[2], "cache_read_tokens": tokens[3]}
        return details, "tokens"

    return None, "skipped"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="report the changes without writing them")
    args = parser.parse_args()

    db_path = app.DB_PATH
    if not db_path.exists():
        print(f"No database at {db_path} — nothing to backfill.")
        return 1

    conn = sqlite3.connect(str(db_path), timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=30000")
    _ensure_columns(conn)

    rows = conn.execute("SELECT * FROM sessions").fetchall()
    counts = {"transcript": 0, "tokens": 0, "skipped": 0}
    old_total = 0.0
    new_total = 0.0

    for row in rows:
        old_cost = row["estimated_cost_usd"] or 0.0
        old_total += old_cost
        details, source = _recompute(row)
        counts[source] += 1
        if details is None:
            new_total += old_cost  # unchanged
            continue
        new_total += details["cost"]
        if not args.dry_run:
            conn.execute(
                """UPDATE sessions SET
                       estimated_cost_usd=?,
                       input_tokens=?, output_tokens=?,
                       cache_write_tokens=?, cache_read_tokens=?,
                       input_cost=?, output_cost=?,
                       cache_write_cost=?, cache_read_cost=?
                   WHERE session_id=?""",
                (details["cost"], details["input_tokens"], details["output_tokens"],
                 details["cache_write_tokens"], details["cache_read_tokens"],
                 details["cost_input"], details["cost_output"],
                 details["cost_cache_write"], details["cost_cache_read"],
                 row["session_id"]),
            )

    # Rebuild daily_stats.cost from the corrected sessions. Matches the keys
    # _aggregate_daily_stats uses: date = started_at[:10], project defaults to
    # 'unknown', model defaults to ''. This also repairs the historical
    # double-count from stop + task-completed both aggregating a session.
    daily_sql = """
        UPDATE daily_stats SET cost = COALESCE((
            SELECT SUM(s.estimated_cost_usd) FROM sessions s
            WHERE substr(s.started_at, 1, 10) = daily_stats.date
              AND COALESCE(NULLIF(s.project, ''), 'unknown') = daily_stats.project
              AND COALESCE(s.model, '') = daily_stats.model
        ), 0)
    """
    daily_rows = conn.execute("SELECT COUNT(*) FROM daily_stats").fetchone()[0]
    if not args.dry_run:
        conn.execute(daily_sql)
        conn.commit()

    mode = "DRY RUN — no changes written" if args.dry_run else "applied"
    print(f"Backfill {mode}")
    print(f"  sessions: {len(rows)} total  "
          f"({counts['transcript']} from transcript, "
          f"{counts['tokens']} from stored tokens, "
          f"{counts['skipped']} skipped)")
    print(f"  session cost total: ${old_total:.4f} -> ${new_total:.4f} "
          f"(delta ${new_total - old_total:+.4f})")
    print(f"  daily_stats rows rebuilt from sessions: {daily_rows}")
    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
