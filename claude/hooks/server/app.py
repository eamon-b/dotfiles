#!/usr/bin/env python3
"""Claude Code HTTP Hooks Server.

Tracks sessions, tool calls, permissions, and costs.
Provides a web dashboard and REST API.
"""

import json
import os
import re
import sqlite3
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import aiosqlite
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse

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
# Database
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
    estimated_cost_usd REAL DEFAULT 0.0
);

CREATE TABLE IF NOT EXISTS tool_calls (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id  TEXT NOT NULL,
    tool_name   TEXT NOT NULL,
    tool_input  TEXT,
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

CREATE INDEX IF NOT EXISTS idx_tc_session   ON tool_calls(session_id);
CREATE INDEX IF NOT EXISTS idx_tc_ts        ON tool_calls(timestamp);
CREATE INDEX IF NOT EXISTS idx_perm_session ON permissions(session_id);
CREATE INDEX IF NOT EXISTS idx_blk_session  ON blocked_actions(session_id);
"""

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


def estimate_cost(transcript_path: str | None) -> float:
    if not transcript_path:
        return 0.0
    path = Path(transcript_path)
    if not path.exists():
        return 0.0
    total = 0.0
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
                total += (
                    inp * prices["input"]
                    + cache_write * prices["cache_write"]
                    + cache_read * prices["cache_read"]
                    + out * prices["output"]
                ) / 1_000_000
    except Exception:
        pass
    return round(total, 4)


# ---------------------------------------------------------------------------
# FastAPI application
# ---------------------------------------------------------------------------


@asynccontextmanager
async def lifespan(_app: FastAPI):
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    async with aiosqlite.connect(str(DB_PATH)) as db:
        await db.executescript(DB_SCHEMA)
        await db.commit()
    yield


app = FastAPI(title="Claude Code Hooks Server", lifespan=lifespan)


async def _db():
    return await aiosqlite.connect(str(DB_PATH))


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

    db = await _db()
    try:
        await _ensure_session(db, data)
        allowed, reason = check_security(tool, tinput)
        if not allowed:
            await db.execute(
                "INSERT INTO blocked_actions (session_id,tool_name,tool_input,rule_matched,reason,timestamp) VALUES (?,?,?,?,?,?)",
                (sid, tool, _truncate(tinput), reason, reason, _now()),
            )
            await db.commit()
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
    finally:
        await db.close()


@app.post("/hooks/post-tool-use")
async def post_tool_use(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = await _db()
    try:
        await _ensure_session(db, data)
        await db.execute(
            "INSERT INTO tool_calls (session_id,tool_name,tool_input,hook_event,success,timestamp) VALUES (?,?,?,?,1,?)",
            (sid, data.get("tool_name", ""), _truncate(data.get("tool_input", {})), "PostToolUse", _now()),
        )
        await db.execute(
            "UPDATE sessions SET tool_call_count=tool_call_count+1, last_activity=? WHERE session_id=?",
            (_now(), sid),
        )
        await db.commit()
        return JSONResponse({"status": "ok"})
    finally:
        await db.close()


@app.post("/hooks/post-tool-use-failure")
async def post_tool_use_failure(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = await _db()
    try:
        await _ensure_session(db, data)
        await db.execute(
            "INSERT INTO tool_calls (session_id,tool_name,tool_input,hook_event,success,timestamp) VALUES (?,?,?,?,0,?)",
            (sid, data.get("tool_name", ""), _truncate(data.get("tool_input", {})), "PostToolUseFailure", _now()),
        )
        await db.execute(
            "UPDATE sessions SET tool_call_count=tool_call_count+1, last_activity=? WHERE session_id=?",
            (_now(), sid),
        )
        await db.commit()
        return JSONResponse({"status": "ok"})
    finally:
        await db.close()


@app.post("/hooks/permission-request")
async def permission_request(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = await _db()
    try:
        await _ensure_session(db, data)
        await db.execute(
            "INSERT INTO permissions (session_id,tool_name,tool_input,timestamp) VALUES (?,?,?,?)",
            (sid, data.get("tool_name", ""), _truncate(data.get("tool_input", {})), _now()),
        )
        await db.commit()
        return JSONResponse({"status": "ok"})
    finally:
        await db.close()


@app.post("/hooks/user-prompt-submit")
async def user_prompt_submit(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = await _db()
    try:
        await _ensure_session(db, data)
        await db.execute(
            "UPDATE sessions SET prompt_count=prompt_count+1, last_activity=? WHERE session_id=?",
            (_now(), sid),
        )
        await db.commit()
        return JSONResponse({"status": "ok"})
    finally:
        await db.close()


@app.post("/hooks/stop")
async def stop(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = await _db()
    try:
        await _ensure_session(db, data)
        cost = estimate_cost(data.get("transcript_path"))
        await db.execute(
            "UPDATE sessions SET status='stopped', last_activity=?, estimated_cost_usd=? WHERE session_id=?",
            (_now(), cost, sid),
        )
        await db.commit()
        return JSONResponse({"status": "ok"})
    finally:
        await db.close()


@app.post("/hooks/subagent-stop")
async def subagent_stop(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = await _db()
    try:
        await _ensure_session(db, data)
        await db.execute(
            "UPDATE sessions SET last_activity=? WHERE session_id=?",
            (_now(), sid),
        )
        await db.commit()
        return JSONResponse({"status": "ok"})
    finally:
        await db.close()


@app.post("/hooks/task-completed")
async def task_completed(request: Request):
    data = await request.json()
    sid = data.get("session_id", "unknown")
    db = await _db()
    try:
        await _ensure_session(db, data)
        cost = estimate_cost(data.get("transcript_path"))
        await db.execute(
            "UPDATE sessions SET status='completed', last_activity=?, estimated_cost_usd=? WHERE session_id=?",
            (_now(), cost, sid),
        )
        await db.commit()
        return JSONResponse({"status": "ok"})
    finally:
        await db.close()


# ---------------------------------------------------------------------------
# Dashboard & API
# ---------------------------------------------------------------------------


@app.get("/dashboard", response_class=HTMLResponse)
async def dashboard():
    return DASHBOARD_PATH.read_text()


@app.get("/api/sessions")
async def api_sessions(limit: int = 50, status: str | None = None):
    db = await _db()
    try:
        db.row_factory = aiosqlite.Row
        q = "SELECT * FROM sessions"
        p: list = []
        if status:
            q += " WHERE status=?"
            p.append(status)
        q += " ORDER BY last_activity DESC LIMIT ?"
        p.append(limit)
        async with db.execute(q, p) as cur:
            return [dict(r) for r in await cur.fetchall()]
    finally:
        await db.close()


@app.get("/api/tool-calls")
async def api_tool_calls(session_id: str | None = None, limit: int = 200):
    db = await _db()
    try:
        db.row_factory = aiosqlite.Row
        q = "SELECT * FROM tool_calls"
        p: list = []
        if session_id:
            q += " WHERE session_id=?"
            p.append(session_id)
        q += " ORDER BY timestamp DESC LIMIT ?"
        p.append(limit)
        async with db.execute(q, p) as cur:
            return [dict(r) for r in await cur.fetchall()]
    finally:
        await db.close()


@app.get("/api/permissions")
async def api_permissions(session_id: str | None = None, limit: int = 100):
    db = await _db()
    try:
        db.row_factory = aiosqlite.Row
        q = "SELECT * FROM permissions"
        p: list = []
        if session_id:
            q += " WHERE session_id=?"
            p.append(session_id)
        q += " ORDER BY timestamp DESC LIMIT ?"
        p.append(limit)
        async with db.execute(q, p) as cur:
            return [dict(r) for r in await cur.fetchall()]
    finally:
        await db.close()


@app.get("/api/blocked")
async def api_blocked(session_id: str | None = None, limit: int = 100):
    db = await _db()
    try:
        db.row_factory = aiosqlite.Row
        q = "SELECT * FROM blocked_actions"
        p: list = []
        if session_id:
            q += " WHERE session_id=?"
            p.append(session_id)
        q += " ORDER BY timestamp DESC LIMIT ?"
        p.append(limit)
        async with db.execute(q, p) as cur:
            return [dict(r) for r in await cur.fetchall()]
    finally:
        await db.close()


@app.get("/api/stats")
async def api_stats(days: int = 7):
    db = await _db()
    try:
        db.row_factory = aiosqlite.Row
        cutoff = f"-{days} days"

        async with db.execute(
            "SELECT COUNT(*) as total_sessions, COALESCE(SUM(tool_call_count),0) as total_tool_calls, COALESCE(SUM(prompt_count),0) as total_prompts, COALESCE(SUM(estimated_cost_usd),0) as total_cost FROM sessions WHERE started_at >= datetime('now', ?)",
            (cutoff,),
        ) as cur:
            overall = dict(await cur.fetchone())

        async with db.execute(
            "SELECT tool_name, COUNT(*) as count FROM tool_calls WHERE timestamp >= datetime('now', ?) GROUP BY tool_name ORDER BY count DESC",
            (cutoff,),
        ) as cur:
            tool_breakdown = [dict(r) for r in await cur.fetchall()]

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
            "SELECT DATE(timestamp) as date, COUNT(*) as tool_calls FROM tool_calls WHERE timestamp >= datetime('now', ?) GROUP BY DATE(timestamp) ORDER BY date",
            (cutoff,),
        ) as cur:
            daily = [dict(r) for r in await cur.fetchall()]

        return {
            "period_days": days,
            **overall,
            "blocked_count": blocked,
            "permission_count": perms,
            "tool_breakdown": tool_breakdown,
            "daily_activity": daily,
        }
    finally:
        await db.close()


@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": _now()}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=PORT)
