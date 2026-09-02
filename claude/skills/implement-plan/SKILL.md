---
name: implement-plan
description: Implement a plan from .claude/plans/ by following its steps, ticking them off in the plan file as you go
argument-hint: "[path-to-plan-file]"
disable-model-invocation: true
---

Implement an existing plan.

**Resolve the plan path:**
- If `$ARGUMENTS` is non-empty, use that path.
- Otherwise use the most recently modified file in `.claude/plans/`:
  `ls -t .claude/plans/*.md 2>/dev/null | head -1`
- If no plan is found, ask the user for the path and stop.

The plan file is the source of truth and the progress record. The user may
have edited it since it was written or reviewed; read it fresh.

## Implementation Process

1. **Read the entire plan first** - Understand the full scope before starting
2. **Set `**Status:** implementing`** in the plan file
3. **Follow the steps in order** - Execute each step as described
4. **Verify as you go** - Check that each step works before moving on
5. **Tick each step off in the plan file** (`- [ ]` → `- [x]`) as soon as it is
   done, so progress survives a compaction or a handoff to another session
6. **Log deviations as they happen** under a `## Implementation Log` section
   (create it on first use): one bullet per deviation, with the step, what was
   done instead, and why

## Guidelines

- Follow the plan's approach unless you discover a clear problem
- If a step can't be implemented as written, note why in the log and adapt
- Keep changes focused on what the plan specifies
- Run tests after implementation if a testing strategy is defined
- Don't add features or improvements not in the plan

## On Completion

1. Finish the `## Implementation Log` with: files changed, test results, and
   any follow-up work identified
2. Set `**Status:** implemented`
3. In chat (under 15 lines): what was implemented, deviations, test results,
   and suggest `/review-implementation` as the next step
