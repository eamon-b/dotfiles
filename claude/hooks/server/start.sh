#!/bin/bash
# Start the Claude Code HTTP hooks server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
PID_FILE="$SCRIPT_DIR/.pid"
PORT="${CLAUDE_HOOKS_PORT:-6271}"

# Create venv and install deps if needed
if [[ ! -d "$VENV_DIR" ]]; then
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    "$VENV_DIR/bin/pip" install -q -r "$SCRIPT_DIR/requirements.txt"
fi

# Check if already running
if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        echo "Server already running (PID $pid) at http://localhost:$PORT/dashboard"
        exit 0
    fi
    rm -f "$PID_FILE"
fi

# Start server
cd "$SCRIPT_DIR"
"$VENV_DIR/bin/python" -m uvicorn app:app \
    --host 127.0.0.1 \
    --port "$PORT" \
    --log-level warning &
echo $! > "$PID_FILE"
echo "Claude Code hooks server started (PID $!) at http://localhost:$PORT/dashboard"
