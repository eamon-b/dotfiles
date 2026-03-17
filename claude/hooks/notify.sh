#!/bin/bash
# Claude Code notification hook
# Usage: notify.sh <type> [message]
# Types: permission, complete
#
# Uses kitty's OSC 99 for notifications with native click-to-focus.
# Falls back to notify-send when not running inside kitty.

TYPE="${1:-notification}"
MESSAGE="${2:-Claude Code notification}"

PROJECT_NAME=$(basename "$PWD")

# Add project context
BODY="$MESSAGE"
if [ -n "$PROJECT_NAME" ]; then
    BODY="[$PROJECT_NAME] $MESSAGE"
fi

play_sound() {
    local sound="$1"
    if [ -n "$sound" ] && command -v paplay &>/dev/null && [ -f "$sound" ]; then
        paplay "$sound" &
    fi
}

send_kitty_notification() {
    local urgency="$1"
    local title="$2"
    local body="$3"

    # OSC 99 format: \e]99;key=value:key=value;payload\e\\
    # a=focus  — focus the kitty window when the notification is clicked (default)
    # u=0|1|2  — urgency: low, normal, critical
    local u=1
    [ "$urgency" = "critical" ] && u=2

    # Write OSC 99 to the terminal that launched claude, not to this hook's stdout
    if [ -n "$CLAUDE_TTY" ]; then
        printf '\x1b]99;i=claude-code:u=%s:d=0;%s\x1b\\' "$u" "$title" > "$CLAUDE_TTY"
        printf '\x1b]99;i=claude-code:d=1:p=body;%s\x1b\\' "$body" > "$CLAUDE_TTY"
    else
        printf '\x1b]99;i=claude-code:u=%s:d=0;%s\x1b\\' "$u" "$title"
        printf '\x1b]99;i=claude-code:d=1:p=body;%s\x1b\\' "$body"
    fi
}

send_fallback_notification() {
    local urgency="$1"
    local title="$2"
    local body="$3"

    notify-send -u "$urgency" -a "Claude Code" "$title" "$body" 2>/dev/null
}

send_notification() {
    local urgency="$1"
    local title="$2"
    local body="$3"
    local sound="$4"

    play_sound "$sound"

    if [ -n "$KITTY_PID" ]; then
        send_kitty_notification "$urgency" "$title" "$body"
    else
        send_fallback_notification "$urgency" "$title" "$body"
    fi
}

case "$TYPE" in
    permission)
        send_notification "critical" "Permission Required" "$BODY" \
            "/usr/share/sounds/freedesktop/stereo/dialog-warning.oga"
        ;;
    complete)
        send_notification "normal" "Task Complete" "$BODY" \
            "/usr/share/sounds/freedesktop/stereo/complete.oga"
        ;;
    *)
        send_notification "normal" "Claude Code" "$BODY" ""
        ;;
esac
