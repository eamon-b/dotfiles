#!/bin/bash
# PostCompact hook - re-injects critical context after context window compression.
# Output from this script is added to the conversation context.

set -euo pipefail

# Project-specific reminders (if the file exists in the current project)
if [[ -f ".claude/post-compact-reminders.md" ]]; then
    cat ".claude/post-compact-reminders.md"
    echo ""
fi

# Default reminders
cat << 'REMINDER'
## Post-Compact Context Reminder

After context compression, key details may have been lost. Before continuing:

- Re-read any active PLAN-*.md or HANDOFF.md files in the working directory
- Re-read CLAUDE.md for project-specific instructions
- If mid-implementation, re-read the files you were modifying
- Check `git status` and `git diff` to understand current state
- Do not repeat work that has already been completed
REMINDER
