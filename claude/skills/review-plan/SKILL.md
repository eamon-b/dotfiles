---
name: review-plan
description: Critique an implementation plan in .claude/plans/ to verify it will achieve its goals
argument-hint: "[path-to-plan-file]"
disable-model-invocation: true
---

Review and critique an implementation plan.

**Resolve the plan path:**
- If `$ARGUMENTS` is non-empty, use that path.
- Otherwise use the most recently modified file in `.claude/plans/`:
  `ls -t .claude/plans/*.md 2>/dev/null | head -1`
- If no plan is found, ask the user for the path and stop.

The user may have edited the plan by hand since it was written. Review the
file as it is now, not as you remember it.

## Review Process

1. **Read the plan thoroughly**
2. **Verify completeness** - Does the plan cover everything needed?
3. **Check feasibility** - Can each step actually be implemented as described?
4. **Identify gaps** - What's missing or unclear?
5. **Validate the approach** - Will this actually solve the problem/build the feature?

## Critique Checklist

- [ ] Are all affected files identified?
- [ ] Are the steps in the right order?
- [ ] Are there missing dependencies or prerequisites?
- [ ] Are edge cases considered?
- [ ] Is the testing strategy sufficient?
- [ ] Are there simpler alternatives?
- [ ] Could any step introduce bugs or break existing functionality?

## Output

Update the plan file directly:

1. Modify any steps that need improvement and add any missing steps (keep the
   `- [ ]` checkbox format so `/implement-plan` can tick them)
2. Update the risks section if you found new concerns
3. Append a `## Review Notes` section (dated) at the end with your findings and
   any open questions for the user
4. Set `**Status:** reviewed`

Summarize the key changes you made and any concerns that remain, in under 15
lines. The user may edit the plan again before implementing.
