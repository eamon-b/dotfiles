#!/bin/bash
# Claude Code review-on-stop hook (Stop event, synchronous)
#
# When enabled, the first time Claude tries to end a turn that leaves
# uncommitted changes, this hook blocks the stop and asks Claude to run the
# bundled /code-review skill on those changes and fix confirmed findings.
# /code-review spawns fresh reviewer subagents, so the review still gets
# "fresh eyes" without a detached `claude --print` process or a REVIEW.md.
#
# Activation: CLAUDE_REVIEW_ON_STOP=1 claude "implement feature X"
#
# Loop protection: Claude Code sets stop_hook_active=true when it is already
# continuing because of a Stop hook, so we only ever block once per turn.

if [[ "${CLAUDE_REVIEW_ON_STOP:-0}" != "1" ]]; then
    exit 0
fi

INPUT=$(cat)

# Never block twice in a row.
if [[ "$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" == "true" ]]; then
    exit 0
fi

WORK_DIR=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
WORK_DIR="${WORK_DIR:-$(pwd)}"

if ! git -C "$WORK_DIR" rev-parse --git-dir &>/dev/null; then
    exit 0
fi

# Nothing to review if the tree is clean (staged, unstaged, or untracked).
if git -C "$WORK_DIR" diff --quiet && git -C "$WORK_DIR" diff --cached --quiet \
   && [[ -z "$(git -C "$WORK_DIR" ls-files --others --exclude-standard)" ]]; then
    exit 0
fi

jq -n '{
  decision: "block",
  reason: "Before finishing: review the uncommitted changes in this repository with the bundled /code-review skill (medium effort). Fix findings you are confident are real bugs; leave stylistic suggestions alone. Then summarize what the review found and what you changed, and stop."
}'
exit 0
