#!/bin/bash
# Stop the Claude Code HTTP hooks server

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="$SCRIPT_DIR/.pid"

if [[ ! -f "$PID_FILE" ]]; then
    echo "Server not running (no PID file)"
    exit 0
fi

pid=$(cat "$PID_FILE")
if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    rm -f "$PID_FILE"
    echo "Server stopped (PID $pid)"
else
    rm -f "$PID_FILE"
    echo "Server was not running (stale PID file removed)"
fi
