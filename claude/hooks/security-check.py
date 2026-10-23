#!/usr/bin/env python3
"""PreToolUse hook: block tool calls that match security-rules.json.

Runs as a command hook so the rules apply even when the HTTP hooks server is
down (HTTP hook connection failures are non-blocking) and in the cloud
sandbox, which has no server. The server still evaluates the same rules for
its blocked-actions log and dashboard.

Exit 2 blocks the call and shows stderr to Claude. Anything unexpected (bad
payload, missing or invalid rules file) exits 0 so a broken rules file never
wedges every tool call.
"""

import json
import re
import sys
from pathlib import Path

RULES_PATH = Path(__file__).parent / "security-rules.json"


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        rules = json.loads(RULES_PATH.read_text())
    except (OSError, ValueError):
        return 0

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}

    if tool_name == "Bash":
        subject, rule_set = tool_input.get("command", ""), rules.get("deny_commands", [])
    elif tool_name in ("Read", "Write", "Edit"):
        subject, rule_set = tool_input.get("file_path", ""), rules.get("deny_file_patterns", [])
    else:
        return 0

    for rule in rule_set:
        try:
            matched = re.search(rule["pattern"], subject, re.IGNORECASE)
        except (KeyError, re.error):
            continue
        if matched:
            reason = rule.get("description", f"Matched: {rule['pattern']}")
            print(f"Blocked by security rule: {reason}", file=sys.stderr)
            return 2

    return 0


if __name__ == "__main__":
    sys.exit(main())
