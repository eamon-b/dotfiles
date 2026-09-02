---
name: review-implementation
description: Review the implementation against its plan in .claude/plans/ to verify correctness, and record the verdict in the plan file
argument-hint: "[path-to-plan-file]"
disable-model-invocation: true
---

Review the implementation against the plan.

**Resolve the plan path:**
- If `$ARGUMENTS` is non-empty, use that path.
- Otherwise use the most recently modified file in `.claude/plans/`:
  `ls -t .claude/plans/*.md 2>/dev/null | head -1`
- If no plan is found, ask the user for the path and stop.

## Review Process

1. **Read the plan** - Including its `## Review Notes` and
   `## Implementation Log`, which record what was intended and what deviated
2. **Examine the changes** - `git diff` / `git diff --cached` / `git log` for
   the branch, plus the files the plan names
3. **Compare against goals** - Does the implementation achieve the plan's goals?
4. **Check quality** - Look for bugs, edge cases, and code quality issues

## Review Checklist

- [ ] All planned steps were implemented (every `- [x]` really is done)
- [ ] Implementation matches the plan's intent
- [ ] Deviations in the implementation log are justified
- [ ] Code follows project conventions
- [ ] No obvious bugs or logic errors
- [ ] Edge cases are handled
- [ ] Tests pass (if applicable)
- [ ] No unintended side effects

## Output

Append a `## Implementation Review` section (dated) to the plan file with:

1. **Implementation Status**: Complete / Partial / Needs Changes
2. **Matches Plan**: Yes / Mostly / No
3. **Issues Found**: bugs, gaps, or concerns with `file:line` references
4. **Recommendations**: what should be fixed or improved

Then set `**Status:** verified` (or `needs-changes` if issues must be fixed).

Give the same summary in chat, under 15 lines. If issues are found, be
specific about what needs to change and where.
