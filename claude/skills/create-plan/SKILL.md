---
name: create-plan
description: Create a detailed implementation plan for a feature or issue
argument-hint: "[description of feature or issue]"
---

Create a detailed implementation plan for the following:

$ARGUMENTS

## Requirements

1. **Analyze the request** - Understand what needs to be built or fixed
2. **Explore the codebase** - Find relevant files, patterns, and dependencies
3. **Design the approach** - Break down into concrete steps

## Plan Format

Write the plan to a file in the current directory named `PLAN-<topic>.md` where `<topic>` is 1-2 lowercase words (hyphenated) describing what the plan is for. Examples:
- `PLAN-user-auth.md`
- `PLAN-cache-layer.md`
- `PLAN-bug-fix.md`

Use this structure:

```markdown
# Implementation Plan

## Summary
Brief description of what will be implemented/fixed.

## Goals
- What this plan aims to achieve
- Success criteria

## Current State
- Relevant existing code/files
- Current behavior (if fixing a bug)

## Implementation Steps

### Step 1: [Title]
- Files to modify: [list]
- Changes: [description]

### Step 2: [Title]
...

## Testing Strategy
How to verify the implementation works correctly.

## Risks and Considerations
Potential issues or edge cases to watch for.
```

After writing the plan file, **report in chat** (keep under 15 lines so it's readable on a phone):

- The filename
- A 3-5 bullet summary of the plan
- Estimated size: **S** (≤5 files, no design decisions), **M**, or **L**
- If size is **S**, suggest `/ship-it` may be a faster end-to-end alternative

Don't echo the full plan in chat — the file has it.
