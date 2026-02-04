---
name: review-plan
description: Critique an implementation plan to verify it will achieve its goals
argument-hint: "[path-to-plan-file]"
---

Review and critique the implementation plan at: $ARGUMENTS

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

After reviewing, update the plan file directly with:

1. Add a `## Review Notes` section at the end with your findings
2. Modify any steps that need improvement
3. Add any missing steps
4. Update the risks section if you found new concerns

Summarize the key changes you made and any concerns that remain.
