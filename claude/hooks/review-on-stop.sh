#!/bin/bash
# Claude Code review-on-stop hook
# Spawns a fresh Claude agent to review local changes after implementation
#
# Activation: Set CLAUDE_REVIEW_ON_STOP=1 before running claude
# Example: CLAUDE_REVIEW_ON_STOP=1 claude "implement feature X"

# Exit early if not activated
if [[ "$CLAUDE_REVIEW_ON_STOP" != "1" ]]; then
    exit 0
fi

# Get the working directory from the hook context or use current
WORK_DIR="${CLAUDE_WORKING_DIRECTORY:-$(pwd)}"

# Check if we're in a git repo
if ! git -C "$WORK_DIR" rev-parse --git-dir &>/dev/null; then
    exit 0
fi

# Check if there are any changes to review (staged, unstaged, or untracked)
if git -C "$WORK_DIR" diff --quiet && git -C "$WORK_DIR" diff --cached --quiet; then
    # No staged or unstaged changes, check for untracked files
    if [[ -z "$(git -C "$WORK_DIR" ls-files --others --exclude-standard)" ]]; then
        exit 0
    fi
fi

# Unset the env var to prevent infinite loop when review agent stops
export CLAUDE_REVIEW_ON_STOP=0

# Build the review prompt
REVIEW_PROMPT='Review the uncommitted local changes in this repository.

Your task:
1. Run `git diff` and `git diff --cached` to see all changes
2. Run `git status` to see untracked files
3. Review the changes for:
   - Bugs or logic errors
   - Security issues
   - Missing error handling
   - Obvious improvements

4. For issues you are VERY confident about (clear bugs, typos, missing null checks, etc.):
   - Fix them directly using the Edit tool
   - Be conservative - only fix things that are clearly wrong

5. Write a REVIEW.md file in the repository root with:
   - A "Changes Made" section listing any fixes you applied (with file:line references)
   - A "Suggestions" section for things that need human judgment or clarification
   - A "Questions" section for anything unclear about the implementation intent

Keep the review focused and actionable. Do not make stylistic changes or refactors.
Do not add tests, documentation, or features - only review what was implemented.'

# Launch the review agent in background
# Using --print to make it non-interactive, output goes to terminal
# Pass through --dangerously-skip-permissions if the parent session had it
if [[ "$CLAUDE_DANGEROUSLY_SKIP_PERMISSIONS" == "1" ]]; then
    cd "$WORK_DIR" && claude --dangerously-skip-permissions --print "$REVIEW_PROMPT" &
else
    cd "$WORK_DIR" && claude --print "$REVIEW_PROMPT" &
fi

exit 0
