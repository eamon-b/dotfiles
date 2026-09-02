#!/bin/bash
# SessionStart(compact) hook - re-injects critical context after context
# window compression.
#
# Wired as a SessionStart hook with matcher "compact", NOT as PostCompact:
# Claude Code only adds plain-text stdout to the model's context for
# SessionStart, UserPromptSubmit, UserPromptExpansion and PostModelSwitch.
# PostCompact stdout goes to the debug log and never reaches Claude.

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

- Re-read the active plan in `.claude/plans/` (most recent file) and any HANDOFF.md
- Re-read CLAUDE.md for project-specific instructions
- If mid-implementation, re-read the files you were modifying
- Check `git status` and `git diff` to understand current state
- Do not repeat work that has already been completed
REMINDER
