#!/usr/bin/env bash
# Claude Code notification hook
# Usage: notify.sh <type> [message]
# Types: permission, denied, complete
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

IS_MAC=0
[[ "$(uname -s)" == Darwin ]] && IS_MAC=1

play_sound() {
    local sound="$1"
    [ -n "$sound" ] && [ -f "$sound" ] || return 0
    if command -v paplay &>/dev/null; then
        paplay "$sound" &
    elif command -v afplay &>/dev/null; then
        afplay "$sound" &
    fi
}

# Map the freedesktop sound names used below to built-in macOS sounds
sound_for() {
    if ((IS_MAC)); then
        case "$1" in
            warning)  echo /System/Library/Sounds/Funk.aiff ;;
            complete) echo /System/Library/Sounds/Glass.aiff ;;
        esac
    else
        case "$1" in
            warning)  echo /usr/share/sounds/freedesktop/stereo/dialog-warning.oga ;;
            complete) echo /usr/share/sounds/freedesktop/stereo/complete.oga ;;
        esac
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

    if command -v notify-send &>/dev/null; then
        notify-send -u "$urgency" -a "Claude Code" "$title" "$body" 2>/dev/null
    elif command -v terminal-notifier &>/dev/null; then
        # brew install terminal-notifier: clicking it focuses the terminal
        terminal-notifier -title "Claude Code" -subtitle "$title" -message "$body" \
            -group claude-code ${__CFBundleIdentifier:+-activate "$__CFBundleIdentifier"} >/dev/null 2>&1
    elif command -v osascript &>/dev/null; then
        # Pass strings as argv so quotes in the message can't break the AppleScript
        osascript -e 'on run argv' \
                  -e 'display notification (item 2 of argv) with title "Claude Code" subtitle (item 1 of argv)' \
                  -e 'end run' "$title" "$body" >/dev/null 2>&1
    fi
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
        send_notification "critical" "Permission Required" "$BODY" "$(sound_for warning)"
        ;;
    denied)
        send_notification "normal" "Action Denied" "$BODY" "$(sound_for warning)"
        ;;
    complete)
        send_notification "normal" "Task Complete" "$BODY" "$(sound_for complete)"
        ;;
    *)
        send_notification "normal" "Claude Code" "$BODY" ""
        ;;
esac
