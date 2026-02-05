---
name: review-implementation
description: Review the implementation against the plan to verify correctness
argument-hint: "[path-to-plan-file]"
---

Review the implementation against the plan at: $ARGUMENTS

## Review Process

1. **Read the plan** - Understand what was supposed to be built
2. **Examine the changes** - Look at what was actually implemented
3. **Compare against goals** - Does the implementation achieve the plan's goals?
4. **Check quality** - Look for bugs, edge cases, and code quality issues

## Review Checklist

- [ ] All planned steps were implemented
- [ ] Implementation matches the plan's intent
- [ ] Code follows project conventions
- [ ] No obvious bugs or logic errors
- [ ] Edge cases are handled
- [ ] Tests pass (if applicable)
- [ ] No unintended side effects

## Output

Provide a review summary:

1. **Implementation Status**: Complete / Partial / Needs Changes
2. **Matches Plan**: Yes / Mostly / No
3. **Issues Found**: List any bugs, gaps, or concerns
4. **Recommendations**: What should be fixed or improved

If issues are found, be specific about what needs to change and where.
