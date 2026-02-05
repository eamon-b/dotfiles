#!/bin/bash
# Claude Code notification hook
# Usage: notify.sh <type> [message]
# Types: permission, complete
# Click on notification to focus the correct terminal

TYPE="${1:-notification}"
MESSAGE="${2:-Claude Code notification}"

# Get the working directory for context in notifications
WORK_DIR="${PWD/#$HOME/~}"
PROJECT_NAME=$(basename "$PWD")

# Find the exact terminal window that spawned this hook
get_parent_terminal_window() {
    # Method 1: Use CLAUDE_TERMINAL_WINDOW (set by wrapper function in bashrc)
    # This is the most reliable because it captures window ID at Claude launch time
    if [ -n "$CLAUDE_TERMINAL_WINDOW" ]; then
        echo "$CLAUDE_TERMINAL_WINDOW"
        return
    fi

    # Method 2: Use WINDOWID if available (may not be inherited through to hooks)
    if [ -n "$WINDOWID" ]; then
        echo "$WINDOWID"
        return
    fi

    # Method 3: Walk up the process tree to find the parent Terminator process
    local pid=$$
    local terminator_pid=""

    while [ "$pid" -gt 1 ]; do
        local parent_pid parent_name
        parent_pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$parent_pid" ] && break

        parent_name=$(ps -o comm= -p "$parent_pid" 2>/dev/null)

        # Terminator is Python-based, check for python or terminator
        if [[ "$parent_name" == "terminator" || "$parent_name" == "python"* ]]; then
            local cmdline
            cmdline=$(ps -o args= -p "$parent_pid" 2>/dev/null)
            if [[ "$cmdline" == *"terminator"* ]]; then
                terminator_pid="$parent_pid"
                break
            fi
        fi

        pid="$parent_pid"
    done

    if [ -n "$terminator_pid" ]; then
        local win
        win=$(xdotool search --pid "$terminator_pid" 2>/dev/null | head -1)
        if [ -n "$win" ]; then
            echo "$win"
            return
        fi
    fi

    # Method 4: Fall back to searching by title (least reliable with multiple terminals)
    local win
    win=$(xdotool search --name "claude" --class "Terminator" 2>/dev/null | head -1)
    if [ -z "$win" ]; then
        win=$(xdotool search --class "Terminator" 2>/dev/null | head -1)
    fi
    echo "$win"
}

focus_terminal() {
    local win="$1"
    if [ -n "$win" ]; then
        xdotool windowactivate "$win" 2>/dev/null
    fi
}

send_notification() {
    local urgency="$1"
    local title="$2"
    local body="$3"
    local sound="$4"

    # Capture window ID now, while we're still in the right process context
    local win
    win=$(get_parent_terminal_window)

    # Add project context to the notification body
    local full_body="$body"
    if [ -n "$PROJECT_NAME" ]; then
        full_body="[$PROJECT_NAME] $body"
    fi

    # Play sound if available
    if [ -n "$sound" ] && command -v paplay &>/dev/null && [ -f "$sound" ]; then
        paplay "$sound" &
    fi

    # Use dunstify if available (supports click actions), otherwise fall back to notify-send
    if command -v dunstify &>/dev/null; then
        # Use window ID as notification ID so each terminal gets its own notification slot
        local notify_id="${win:-0}"
        # Truncate to valid range (dunst uses 32-bit signed int)
        notify_id=$((notify_id % 2147483647))

        # dunstify returns action name on stdout when clicked
        local action
        action=$(dunstify -a "Claude Code" -u "$urgency" \
            -r "$notify_id" \
            --action="focus,Focus Terminal" \
            "$title" "$full_body")

        if [ "$action" = "focus" ]; then
            focus_terminal "$win"
        fi
    else
        notify-send -u "$urgency" -a "Claude Code" "$title" "$full_body"
    fi
}

case "$TYPE" in
    permission)
        send_notification "critical" "Permission Required" "$MESSAGE" \
            "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
        ;;
    complete)
        send_notification "normal" "Task Complete" "$MESSAGE" \
            "/usr/share/sounds/freedesktop/stereo/complete.oga"
        ;;
    *)
        send_notification "normal" "Claude Code" "$MESSAGE" ""
        ;;
esac
