---
name: create-plan
description: Create a detailed implementation plan for a feature or issue, saved as a living document in .claude/plans/
argument-hint: "[description of feature or issue]"
disable-model-invocation: true
---

Create a detailed implementation plan for the following:

$ARGUMENTS

## Requirements

1. **Analyze the request** - Understand what needs to be built or fixed
2. **Explore the codebase** - Find relevant files, patterns, and dependencies
3. **Design the approach** - Break down into concrete steps

## Where plans live

Plans are living documents in `.claude/plans/` inside the project (the same
directory native plan mode uses via `plansDirectory`). The file is created
here, edited by the user, annotated by `/review-plan`, checked off by
`/implement-plan`, and closed out by `/review-implementation`, so it stays a
single record of what was intended, what was done, and what was verified.

Write the plan to `.claude/plans/<topic>.md` where `<topic>` is 1-3 lowercase
hyphenated words describing the work (`user-auth.md`, `cache-layer.md`).
Create the directory if needed. If a file with that name exists, append a
short date suffix (`user-auth-2026-09-02.md`) rather than overwriting.

## Plan Format

```markdown
# <Title>

**Status:** draft
**Created:** <YYYY-MM-DD>

## Summary
Brief description of what will be implemented/fixed.

## Goals
- What this plan aims to achieve
- Success criteria

## Current State
- Relevant existing code/files
- Current behavior (if fixing a bug)

## Implementation Steps

- [ ] **Step 1: [Title]**
  - Files: [list]
  - Changes: [description]
- [ ] **Step 2: [Title]**
  ...

## Testing Strategy
How to verify the implementation works correctly.

## Risks and Considerations
Potential issues or edge cases to watch for.
```

The `Status` line moves through `draft` → `reviewed` → `implementing` →
`implemented` → `verified` (or `needs-changes`) as the other plan skills run.
Later sections (`## Review Notes`, `## Implementation Log`,
`## Implementation Review`) are appended by those skills; do not add them here.

After writing the plan file, **report in chat** (keep under 15 lines so it's readable on a phone):

- The file path
- A 3-5 bullet summary of the plan
- Estimated size: **S** (≤5 files, no design decisions), **M**, or **L**
- If size is **S**, suggest `/ship-it` may be a faster end-to-end alternative
- Remind the user they can edit the file directly before running `/review-plan` or `/implement-plan`

Don't echo the full plan in chat — the file has it.
