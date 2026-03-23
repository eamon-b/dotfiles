#!/usr/bin/env python3
"""Claude Code HTTP Hooks Server.

Tracks sessions, tool calls, permissions, and costs.
Provides a web dashboard and REST API.
"""

import asyncio
import csv
import io
import json
import os
import re
import sqlite3
import subprocess
from collections import Counter
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import aiosqlite
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, Response

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DB_PATH = Path(
    os.environ.get("CLAUDE_HOOKS_DB", Path.home() / ".claude" / "hooks-server.db")
)
SECURITY_RULES_PATH = Path(
    os.environ.get(
        "CLAUDE_HOOKS_SECURITY_RULES",
        Path(__file__).parent / "security-rules.json",
    )
)
DASHBOARD_PATH = Path(__file__).parent / "dashboard.html"
PORT = int(os.environ.get("CLAUDE_HOOKS_PORT", 6271))

# Anthropic published pricing (USD per million tokens)
PRICING = {
    "claude-opus-4": {"input": 15.0, "output": 75.0, "cache_write": 18.75, "cache_read": 1.50},
    "claude-sonnet-4": {"input": 3.0, "output": 15.0, "cache_write": 3.75, "cache_read": 0.30},
    "claude-haiku-4": {"input": 0.25, "output": 1.25, "cache_write": 0.30, "cache_read": 0.025},
    "default": {"input": 3.0, "output": 15.0, "cache_write": 3.75, "cache_read": 0.30},
}

# ---------------------------------------------------------------------------
# Database schema & migrations
# ---------------------------------------------------------------------------

DB_SCHEMA = """
PRAGMA journal_mode=WAL;

CREATE TABLE IF NOT EXISTS sessions (
    session_id    TEXT PRIMARY KEY,
    project       TEXT,
    cwd           TEXT,
    permission_mode TEXT,
    started_at    TEXT NOT NULL,
    last_activity TEXT NOT NULL,
    status        TEXT DEFAULT 'active',
    tool_call_count INTEGER DEFAULT 0,
    prompt_count  INTEGER DEFAULT 0,
    estimated_cost_usd REAL DEFAULT 0.0,
    model         TEXT DEFAULT '',
    input_tokens  INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    cache_write_tokens INTEGER DEFAULT 0,
    cache_read_tokens INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS tool_calls (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,
    tool_name   TEXT NOT NULL,
    tool_input  TEXT,
    tool_output TEXT,
    hook_event  TEXT NOT NULL,
    success     INTEGER DEFAULT 1,
    timestamp   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS permissions (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,
    tool_name   TEXT NOT NULL,
    tool_input  TEXT,
    timestamp   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS blocked_actions (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id   TEXT NOT NULL,
    tool_name    TEXT NOT NULL,
    tool_input   TEXT,
    rule_matched TEXT NOT NULL,
    reason       TEXT,
    timestamp    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS prompts (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,
    prompt_text TEXT,
    timestamp   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_stats (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    date             TEXT NOT NULL,
    project          TEXT NOT NULL DEFAULT 'unknown',
    model            TEXT NOT NULL DEFAULT '',
    sessions_count   INTEGER DEFAULT 0,
    tool_calls_count INTEGER DEFAULT 0,
    prompt_count     INTEGER DEFAULT 0,
    failure_count    INTEGER DEFAULT 0,
    cost             REAL DEFAULT 0.0,
    tool_breakdown   TEXT DEFAULT '{}',
    UNIQUE(date, project, model)
);

CREATE INDEX IF NOT EXISTS idx_tc_session   ON tool_calls(session_id);
CREATE INDEX IF NOT EXISTS idx_tc_ts        ON tool_calls(timestamp);
CREATE INDEX IF NOT EXISTS idx_perm_session ON permissions(session_id);
CREATE INDEX IF NOT EXISTS idx_blk_session  ON blocked_actions(session_id);
CREATE INDEX IF NOT EXISTS idx_prompts_session ON prompts(session_id);
CREATE INDEX IF NOT EXISTS idx_prompts_ts   ON prompts(timestamp);
"""

MIGRATIONS = [
    ("sessions", "model", "ALTER TABLE sessions ADD COLUMN model TEXT DEFAULT ''"),
    ("sessions", "input_tokens", "ALTER TABLE sessions ADD COLUMN input_tokens INTEGER DEFAULT 0"),
    ("sessions", "output_tokens", "ALTER TABLE sessions ADD COLUMN output_tokens INTEGER DEFAULT 0"),
    ("sessions", "cache_write_tokens", "ALTER TABLE sessions ADD COLUMN cache_write_tokens INTEGER DEFAULT 0"),
    ("sessions", "cache_read_tokens", "ALTER TABLE sessions ADD COLUMN cache_read_tokens INTEGER DEFAULT 0"),
    ("tool_calls", "tool_output", "ALTER TABLE tool_calls ADD COLUMN tool_output TEXT"),
]


async def _run_migrations(db: aiosqlite.Connection):
    for _table, _col, sql in MIGRATIONS:
        try:
            await db.execute(sql)
        except sqlite3.OperationalError:
            pass
    await db.commit()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _truncate(obj, limit: int = 2000) -> str:
    s = json.dumps(obj) if isinstance(obj, dict) else str(obj)
    return s[:limit]


# ---------------------------------------------------------------------------
# Security rules
# ---------------------------------------------------------------------------

_rules_cache: dict | None = None
_rules_mtime: float = 0


def _load_security_rules() -> dict:
    global _rules_cache, _rules_mtime
    if not SECURITY_RULES_PATH.exists():
        return {"deny_commands": [], "deny_file_patterns": []}
    mtime = SECURITY_RULES_PATH.stat().st_mtime
    if _rules_cache is not None and mtime == _rules_mtime:
        return _rules_cache
    with open(SECURITY_RULES_PATH) as f:
        _rules_cache = json.load(f)
    _rules_mtime = mtime
    return _rules_cache


def check_security(tool_name: str, tool_input: dict) -> tuple[bool, str | None]:
    """Return (allowed, reason).  If blocked, reason describes the matched rule."""
    rules = _load_security_rules()

    if tool_name == "Bash":
        command = tool_input.get("command", "")
        for rule in rules.get("deny_commands", []):
            if re.search(rule["pattern"], command, re.IGNORECASE):
                return False, rule.get("description", f"Matched: {rule['pattern']}")

    if tool_name in ("Read", "Write", "Edit"):
        file_path = tool_input.get("file_path", "")
        for rule in rules.get("deny_file_patterns", []):
            if re.search(rule["pattern"], file_path, re.IGNORECASE):
                return False, rule.get("description", f"Matched: {rule['pattern']}")

    return True, None


# ---------------------------------------------------------------------------
# Cost estimation
# ---------------------------------------------------------------------------


def estimate_cost_detailed(transcript_path: str | None) -> dict:
    """Returns {cost, model, input_tokens, output_tokens, cache_write_tokens, cache_read_tokens}."""
    defaults = {
        "cost": 0.0,
        "model": "",
        "input_tokens": 0,
        "output_tokens": 0,
        "cache_write_tokens": 0,
        "cache_read_tokens": 0,
    }
    if not transcript_path:
        return defaults
    path = Path(transcript_path)
    if not path.exists():
        return defaults

    total_cost = 0.0
    total_input = 0
    total_output = 0
    total_cache_write = 0
    total_cache_read = 0
    model_counts: Counter = Counter()

    try:
        with open(path) as f:
            for line in f:
                try:
                    entry = json.loads(line)
                except json.JSONDecodeError:
                    continue
                msg = entry.get("message")
                if not isinstance(msg, dict):
                    continue
                usage = msg.get("usage")
                if not usage:
                    continue
                model = msg.get("model", "")
                if model:
                    model_counts[model] += 1
                pricing_key = "default"
                for key in PRICING:
                    if key != "default" and key in model:
                        pricing_key = key
                        break
                prices = PRICING[pricing_key]
                inp = usage.get("input_tokens", 0)
                cache_write = usage.get("cache_creation_input_tokens", 0)
                cache_read = usage.get("cache_read_input_tokens", 0)
                out = usage.get("output_tokens", 0)
                total_input += inp
                total_output += out
                total_cache_write += cache_write
                total_cache_read += cache_read
                total_cost += (
                    inp * prices["input"]
                    + cache_write * prices["cache_write"]
                    + cache_read * prices["cache_read"]
                    + out * prices["output"]
                ) / 1_000_000
    except Exception:
        pass

    most_common_model = model_counts.most_common(1)[0][0] if model_counts else ""

    return {
        "cost": round(total_cost, 4),
        "model": most_common_model,
        "input_tokens": total_input,
        "output_tokens": total_output,
        "cache_write_tokens": total_cache_write,
        "cache_read_tokens": total_cache_read,
    }


# ---------------------------------------------------------------------------
# Retention & aggregation
# ---------------------------------------------------------------------------


async def _aggregate_daily_stats(db: aiosqlite.Connection, session: dict):
    started = session.get("started_at", "")
    if not started:
        return
    date = started[:10]
    project = session.get("project", "unknown") or "unknown"
    model = session.get("model", "") or ""
    cost = session.get("estimated_cost_usd", 0.0) or 0.0
    tool_calls_count = session.get("tool_call_count", 0) or 0
    prompt_count = session.get("prompt_count", 0) or 0
    sid = session.get("session_id", "")

    failure_count = 0
    tool_bd: dict = {}
    async with db.execute(
        "SELECT tool_name, success FROM tool_calls WHERE session_id=?", (sid,)
    ) as cur:
        async for row in cur:
            name, success = row[0], row[1]
            tool_bd[name] = tool_bd.get(name, 0) + 1
            if not success:
                failure_count += 1

    await db.execute(
        """INSERT INTO daily_stats (date, project, model, sessions_count, tool_calls_count, prompt_count, failure_count, cost, tool_breakdown)
           VALUES (?,?,?,1,?,?,?,?,?)
           ON CONFLICT(date, project, model) DO UPDATE SET
             sessions_count = sessions_count + 1,
             tool_calls_count = tool_calls_count + excluded.tool_calls_count,
             prompt_count = prompt_count + excluded.prompt_count,
             failure_count = failure_count + excluded.failure_count,
             cost = cost + excluded.cost,
             tool_breakdown = excluded.tool_breakdown""",
        (date, project, model, tool_calls_count, prompt_count, failure_count, cost, json.dumps(tool_bd)),
    )
    await db.commit()


async def _cleanup_old_data(db: aiosqlite.Connection, retention_days: int = 90) -> dict:
    cutoff = f"-{retention_days} days"

    async with db.execute(
        """SELECT DISTINCT DATE(timestamp) as d FROM tool_calls
           WHERE timestamp < datetime('now', ?)
           AND DATE(timestamp) NOT IN (SELECT DISTINCT date FROM daily_stats)""",
        (cutoff,),
    ) as cur:
        old_dates = [row[0] for row in await cur.fetchall()]

    for d in old_dates:
        async with db.execute(
            """SELECT s.session_id, s.project, s.model, s.estimated_cost_usd,
                      s.tool_call_count, s.prompt_count, s.started_at
               FROM sessions s
               WHERE DATE(s.started_at) = ?""",
            (d,),
        ) as cur:
            for row in await cur.fetchall():
                await _aggregate_daily_stats(db, {
                    "session_id": row[0], "project": row[1], "model": row[2],
                    "estimated_cost_usd": row[3], "tool_call_count": row[4],
                    "prompt_count": row[5], "started_at": row[6],
                })

    deleted = {}
    for table in ("tool_calls", "permissions", "blocked_actions", "prompts"):
        async with db.execute(
            f"DELETE FROM {table} WHERE timestamp < datetime('now', ?)", (cutoff,)
        ) as cur:
            deleted[table] = cur.rowcount
    await db.commit()
    return deleted


async def _background_cleanup(app: FastAPI):
    await asyncio.sleep(60)
    while True:
        try:
            db = app.state.db
            await _cleanup_old_data(db)
        except Exception:
            pass
        await asyncio.sleep(86400)


# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(_app: FastAPI):
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = await aiosqlite.connect(str(DB_PATH))
    db.row_factory = aiosqlite.Row
    await db.executescript(DB_SCHEMA)
    await db.commit()
    await _run_migrations(db)
    _app.state.db = db
    cleanup_task = asyncio.create_task(_background_cleanup(_app))
    yield
    cleanup_task.cancel()
    try:
        await cleanup_task
    except asyncio.CancelledError:
        pass
    await db.close()


app = FastAPI(title="Claude Code Hooks Server", lifespan=lifespan)


async def _ensure_session(db: aiosqlite.Connection, data: dict):
    sid = data.get("session_id", "unknown")
    project = Path(data.get("cwd", "")).name if data.get("cwd") else "unknown"
    now = _now()
    async with db.execute(
        "SELECT session_id FROM sessions WHERE session_id = ?", (sid,)
    ) as cur:
        row = await cur.fetchone()
    if not row:
        await db.execute(
            "INSERT INTO sessions (session_id, project, cwd, permission_mode, started_at, last_activity) VALUES (?,?,?,?,?,?)",
            (sid, project, data.get("cwd", ""), data.get("permission_mode", ""), now, now),
        )
    else:
        await db.execute(
            "UPDATE sessions SET last_activity=?, permission_mode=COALESCE(?, permission_mode) WHERE session_id=?",
            (now, data.get("permission_mode"), sid),
        )
    await db.commit()


# ---------------------------------------------------------------------------
# Hook endpoints
# ---------------------------------------------------------------------------


@app.post("/hooks/pre-tool-use")
async def pre_tool_use(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    tool = data.get("tool_name", "")
    tinput = data.get("tool_input", {})
    db = request.app.state.db

    await _ensure_session(db, data)
    allowed, reason = check_security(tool, tinput)
    if not allowed:
        await db.execute(
            "INSERT INTO blocked_actions (session_id,tool_name,tool_input,rule_matched,reason,timestamp) VALUES (?,?,?,?,?,?)",
            (sid, tool, _truncate(tinput), reason, reason, _now()),
        )
        await db.commit()
        try:
            subprocess.Popen(
                ["notify-send", "-u", "critical", "-t", "5000", "Claude: Blocked", f"{reason}"],
                stderr=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            )
        except Exception:
            pass
        return JSONResponse(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": f"Blocked by security rule: {reason}",
                }
            }
        )
    return JSONResponse({"status": "ok"})


@app.post("/hooks/post-tool-use")
async def post_tool_use(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = request.app.state.db
    tool_output = _truncate(data.get("tool_output", ""), 1000)

    await _ensure_session(db, data)
    await db.execute(
        "INSERT INTO tool_calls (session_id,tool_name,tool_input,tool_output,hook_event,success,timestamp) VALUES (?,?,?,?,?,1,?)",
        (sid, data.get("tool_name", ""), _truncate(data.get("tool_input", {})), tool_output, "PostToolUse", _now()),
    )
    await db.execute(
        "UPDATE sessions SET tool_call_count=tool_call_count+1, last_activity=? WHERE session_id=?",
        (_now(), sid),
    )
    await db.commit()
    return JSONResponse({"status": "ok"})


@app.post("/hooks/post-tool-use-failure")
async def post_tool_use_failure(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = request.app.state.db
    tool_output = _truncate(data.get("tool_output", ""), 1000)

    await _ensure_session(db, data)
    await db.execute(
        "INSERT INTO tool_calls (session_id,tool_name,tool_input,tool_output,hook_event,success,timestamp) VALUES (?,?,?,?,?,0,?)",
        (sid, data.get("tool_name", ""), _truncate(data.get("tool_input", {})), tool_output, "PostToolUseFailure", _now()),
    )
    await db.execute(
        "UPDATE sessions SET tool_call_count=tool_call_count+1, last_activity=? WHERE session_id=?",
        (_now(), sid),
    )
    await db.commit()
    return JSONResponse({"status": "ok"})


@app.post("/hooks/permission-request")
async def permission_request(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = request.app.state.db

    await _ensure_session(db, data)
    await db.execute(
        "INSERT INTO permissions (session_id,tool_name,tool_input,timestamp) VALUES (?,?,?,?)",
        (sid, data.get("tool_name", ""), _truncate(data.get("tool_input", {})), _now()),
    )
    await db.commit()
    return JSONResponse({"status": "ok"})


@app.post("/hooks/user-prompt-submit")
async def user_prompt_submit(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = request.app.state.db

    await _ensure_session(db, data)
    prompt_text = data.get("content", "") or data.get("prompt", "")
    await db.execute(
        "INSERT INTO prompts (session_id, prompt_text, timestamp) VALUES (?,?,?)",
        (sid, _truncate(prompt_text, 2000), _now()),
    )
    await db.execute(
        "UPDATE sessions SET prompt_count=prompt_count+1, last_activity=? WHERE session_id=?",
        (_now(), sid),
    )
    await db.commit()
    return JSONResponse({"status": "ok"})


@app.post("/hooks/stop")
async def stop(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = request.app.state.db

    await _ensure_session(db, data)
    details = estimate_cost_detailed(data.get("transcript_path"))
    now = _now()
    await db.execute(
        """UPDATE sessions SET status='stopped', last_activity=?, estimated_cost_usd=?,
           model=?, input_tokens=?, output_tokens=?, cache_write_tokens=?, cache_read_tokens=?
           WHERE session_id=?""",
        (now, details["cost"], details["model"], details["input_tokens"],
         details["output_tokens"], details["cache_write_tokens"],
         details["cache_read_tokens"], sid),
    )
    await db.commit()

    async with db.execute("SELECT * FROM sessions WHERE session_id=?", (sid,)) as cur:
        row = await cur.fetchone()
        if row:
            await _aggregate_daily_stats(db, dict(row))

    return JSONResponse({"status": "ok"})


@app.post("/hooks/subagent-stop")
async def subagent_stop(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = request.app.state.db

    await _ensure_session(db, data)
    details = estimate_cost_detailed(data.get("transcript_path"))
    now = _now()
    await db.execute(
        """UPDATE sessions SET last_activity=?,
           estimated_cost_usd=estimated_cost_usd+?,
           input_tokens=input_tokens+?,
           output_tokens=output_tokens+?,
           cache_write_tokens=cache_write_tokens+?,
           cache_read_tokens=cache_read_tokens+?
           WHERE session_id=?""",
        (now, details["cost"], details["input_tokens"], details["output_tokens"],
         details["cache_write_tokens"], details["cache_read_tokens"], sid),
    )
    if details["model"]:
        await db.execute(
            "UPDATE sessions SET model=? WHERE session_id=? AND (model IS NULL OR model='')",
            (details["model"], sid),
        )
    await db.commit()
    return JSONResponse({"status": "ok"})


@app.post("/hooks/task-completed")
async def task_completed(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = request.app.state.db

    await _ensure_session(db, data)
    details = estimate_cost_detailed(data.get("transcript_path"))
    now = _now()
    await db.execute(
        """UPDATE sessions SET status='completed', last_activity=?, estimated_cost_usd=?,
           model=?, input_tokens=?, output_tokens=?, cache_write_tokens=?, cache_read_tokens=?
           WHERE session_id=?""",
        (now, details["cost"], details["model"], details["input_tokens"],
         details["output_tokens"], details["cache_write_tokens"],
         details["cache_read_tokens"], sid),
    )
    await db.commit()

    async with db.execute("SELECT * FROM sessions WHERE session_id=?", (sid,)) as cur:
        row = await cur.fetchone()
        if row:
            await _aggregate_daily_stats(db, dict(row))

    return JSONResponse({"status": "ok"})


# ---------------------------------------------------------------------------
# Dashboard & API
# ---------------------------------------------------------------------------


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    return DASHBOARD_PATH.read_text()


@app.get("/api/sessions")
async def api_sessions(request: Request, limit: int = 50, status: str | None = None, project: str | None = None):
    db = request.app.state.db
    q = "SELECT * FROM sessions"
    p: list = []
    conditions = []
    if status:
        conditions.append("status=?")
        p.append(status)
    if project:
        conditions.append("project=?")
        p.append(project)
    if conditions:
        q += " WHERE " + " AND ".join(conditions)
    q += " ORDER BY last_activity DESC LIMIT ?"
    p.append(limit)
    async with db.execute(q, p) as cur:
        return [dict(r) for r in await cur.fetchall()]


@app.get("/api/sessions/{session_id}")
async def api_session_detail(session_id: str, request: Request):
    db = request.app.state.db

    async with db.execute("SELECT * FROM sessions WHERE session_id=?", (session_id,)) as cur:
        row = await cur.fetchone()
    if not row:
        return JSONResponse({"error": "session not found"}, status_code=404)
    session = dict(row)

    duration_seconds = 0
    try:
        started = datetime.fromisoformat(session["started_at"])
        last = datetime.fromisoformat(session["last_activity"])
        duration_seconds = int((last - started).total_seconds())
    except Exception:
        pass
    session["duration_seconds"] = duration_seconds

    async with db.execute(
        "SELECT * FROM tool_calls WHERE session_id=? ORDER BY timestamp ASC", (session_id,)
    ) as cur:
        tool_calls = [dict(r) for r in await cur.fetchall()]

    async with db.execute(
        "SELECT * FROM permissions WHERE session_id=? ORDER BY timestamp ASC", (session_id,)
    ) as cur:
        permissions = [dict(r) for r in await cur.fetchall()]

    async with db.execute(
        "SELECT * FROM blocked_actions WHERE session_id=? ORDER BY timestamp ASC", (session_id,)
    ) as cur:
        blocked = [dict(r) for r in await cur.fetchall()]

    async with db.execute(
        "SELECT * FROM prompts WHERE session_id=? ORDER BY timestamp ASC", (session_id,)
    ) as cur:
        prompts = [dict(r) for r in await cur.fetchall()]

    return {
        "session": session,
        "tool_calls": tool_calls,
        "permissions": permissions,
        "blocked": blocked,
        "prompts": prompts,
    }


@app.get("/api/tool-calls")
async def api_tool_calls(
    request: Request,
    session_id: str | None = None,
    tool_name: str | None = None,
    search: str | None = None,
    limit: int = 200,
):
    db = request.app.state.db
    q = "SELECT * FROM tool_calls"
    p: list = []
    conditions = []
    if session_id:
        conditions.append("session_id=?")
        p.append(session_id)
    if tool_name:
        conditions.append("tool_name=?")
        p.append(tool_name)
    if search:
        conditions.append("tool_input LIKE ?")
        p.append(f"%{search}%")
    if conditions:
        q += " WHERE " + " AND ".join(conditions)
    q += " ORDER BY timestamp DESC LIMIT ?"
    p.append(limit)
    async with db.execute(q, p) as cur:
        return [dict(r) for r in await cur.fetchall()]


@app.get("/api/permissions")
async def api_permissions(request: Request, session_id: str | None = None, limit: int = 100):
    db = request.app.state.db
    q = "SELECT * FROM permissions"
    p: list = []
    if session_id:
        q += " WHERE session_id=?"
        p.append(session_id)
    q += " ORDER BY timestamp DESC LIMIT ?"
    p.append(limit)
    async with db.execute(q, p) as cur:
        return [dict(r) for r in await cur.fetchall()]


@app.get("/api/blocked")
async def api_blocked(request: Request, session_id: str | None = None, limit: int = 100):
    db = request.app.state.db
    q = "SELECT * FROM blocked_actions"
    p: list = []
    if session_id:
        q += " WHERE session_id=?"
        p.append(session_id)
    q += " ORDER BY timestamp DESC LIMIT ?"
    p.append(limit)
    async with db.execute(q, p) as cur:
        return [dict(r) for r in await cur.fetchall()]


@app.get("/api/stats")
async def api_stats(request: Request, days: int = 7):
    db = request.app.state.db
    cutoff = f"-{days} days"

    async with db.execute(
        "SELECT COUNT(*) as total_sessions, COALESCE(SUM(tool_call_count),0) as total_tool_calls, COALESCE(SUM(prompt_count),0) as total_prompts, COALESCE(SUM(estimated_cost_usd),0) as total_cost FROM sessions WHERE started_at >= datetime('now', ?)",
        (cutoff,),
    ) as cur:
        overall = dict(await cur.fetchone())

    async with db.execute(
        """SELECT tool_name, COUNT(*) as count,
                  SUM(CASE WHEN success=0 THEN 1 ELSE 0 END) as failure_count
           FROM tool_calls WHERE timestamp >= datetime('now', ?)
           GROUP BY tool_name ORDER BY count DESC""",
        (cutoff,),
    ) as cur:
        tool_breakdown = [dict(r) for r in await cur.fetchall()]

    total_tool_calls = sum(t["count"] for t in tool_breakdown)
    total_failures = sum(t["failure_count"] for t in tool_breakdown)
    success_rate = ((total_tool_calls - total_failures) / total_tool_calls) if total_tool_calls > 0 else 1.0

    async with db.execute(
        "SELECT COUNT(*) as count FROM blocked_actions WHERE timestamp >= datetime('now', ?)",
        (cutoff,),
    ) as cur:
        blocked = (await cur.fetchone())[0]

    async with db.execute(
        "SELECT COUNT(*) as count FROM permissions WHERE timestamp >= datetime('now', ?)",
        (cutoff,),
    ) as cur:
        perms = (await cur.fetchone())[0]

    async with db.execute(
        """SELECT DATE(tc.timestamp) as date, COUNT(*) as tool_calls,
                  COALESCE((SELECT SUM(s.estimated_cost_usd) FROM sessions s WHERE DATE(s.started_at)=DATE(tc.timestamp) AND s.started_at >= datetime('now', ?)), 0) as cost
           FROM tool_calls tc WHERE tc.timestamp >= datetime('now', ?)
           GROUP BY DATE(tc.timestamp) ORDER BY date""",
        (cutoff, cutoff),
    ) as cur:
        daily = [dict(r) for r in await cur.fetchall()]

    async with db.execute(
        """SELECT COALESCE(model, '') as model, COUNT(*) as session_count,
                  COALESCE(SUM(estimated_cost_usd), 0) as cost
           FROM sessions WHERE started_at >= datetime('now', ?)
           GROUP BY COALESCE(model, '') ORDER BY session_count DESC""",
        (cutoff,),
    ) as cur:
        model_breakdown = [dict(r) for r in await cur.fetchall()]

    return {
        "period_days": days,
        **overall,
        "blocked_count": blocked,
        "permission_count": perms,
        "success_rate": round(success_rate, 4),
        "tool_breakdown": tool_breakdown,
        "daily_activity": daily,
        "model_breakdown": model_breakdown,
    }


@app.get("/api/active-sessions")
async def api_active_sessions(request: Request):
    db = request.app.state.db
    async with db.execute(
        "SELECT session_id, project, started_at, last_activity, tool_call_count, prompt_count FROM sessions WHERE status='active' ORDER BY last_activity DESC"
    ) as cur:
        sessions = [dict(r) for r in await cur.fetchall()]
    return {"count": len(sessions), "sessions": sessions}


@app.get("/api/export")
async def api_export(request: Request, format: str = "json", days: int = 30):
    db = request.app.state.db
    cutoff = f"-{days} days"
    async with db.execute(
        "SELECT * FROM sessions WHERE started_at >= datetime('now', ?) ORDER BY started_at DESC",
        (cutoff,),
    ) as cur:
        rows = [dict(r) for r in await cur.fetchall()]

    for row in rows:
        duration = 0
        try:
            started = datetime.fromisoformat(row["started_at"])
            last = datetime.fromisoformat(row["last_activity"])
            duration = int((last - started).total_seconds())
        except Exception:
            pass
        row["duration_seconds"] = duration

    if format == "csv":
        output = io.StringIO()
        fieldnames = [
            "session_id", "project", "model", "status", "started_at", "last_activity",
            "duration_seconds", "tool_call_count", "prompt_count", "estimated_cost_usd",
            "input_tokens", "output_tokens", "cache_write_tokens", "cache_read_tokens",
        ]
        writer = csv.DictWriter(output, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
        return Response(content=output.getvalue(), media_type="text/csv")

    return rows


@app.post("/api/cleanup")
async def api_cleanup(request: Request):
    db = request.app.state.db
    deleted = await _cleanup_old_data(db)
    async with db.execute("SELECT COUNT(DISTINCT date) as cnt FROM daily_stats") as cur:
        aggregated_days = (await cur.fetchone())[0]
    return {"deleted": deleted, "aggregated_days": aggregated_days}


@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": _now()}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=PORT)
