---
name: handoff
description: Summarize current task and write a handoff document for the next agent
argument-hint: "[optional filename or notes]"
---

Create a comprehensive handoff document for continuing this task in a new session.

$ARGUMENTS

## Your Task

Analyze the current conversation and work context to create a handoff document that enables another agent (or yourself in a fresh session) to continue the work effectively.

## Process

1. **Review the conversation** - Understand what was requested and what work has been done
2. **Identify the current state** - What's completed, what's in progress, what remains
3. **Note important context** - Key decisions, constraints, and relevant files
4. **Document failed approaches** - Only include if they provide useful "don't go here" signals

## Handoff Document Format

Write to `HANDOFF.md` in the current working directory (or use the filename provided in arguments).

Use this structure:

```markdown
# Task Handoff

## Original Request
What the user originally asked for (quote or paraphrase accurately).

## Current Status
- **Completed**: What has been finished
- **In Progress**: What was being worked on when the handoff occurred
- **Remaining**: What still needs to be done

## Key Files
List the most important files for this task with brief descriptions:
- `path/to/file.ext` - why it matters

## Context and Decisions
Important decisions made, constraints discovered, or context the next agent needs:
- Decision/context item 1
- Decision/context item 2

## Approaches That Didn't Work
Only include if genuinely helpful to avoid wasted effort:
- What was tried and why it failed (be specific)

## Recommended Next Steps
Concrete actions to continue the work:
1. First thing to do
2. Second thing to do
3. ...

## Commands and Environment
Any relevant commands, environment setup, or configuration:
```bash
# Example commands that were useful
```
```

## Guidelines

- Be concise but complete - the next agent should be able to continue without re-reading the entire conversation
- Focus on actionable information, not narrative
- Include file paths and line numbers where relevant
- If approaches failed, explain *why* they failed so the next agent doesn't repeat them
- Don't include dead ends that aren't instructive
- Prioritize the "Recommended Next Steps" section - this is the most important part

## For ephemeral/sandbox environments

If the working directory may not persist between sessions (typical when working from the Claude mobile app against a remote sandbox), also push the handoff somewhere durable:

- If a PR is open for this work: `gh pr comment <number> --body-file HANDOFF.md`
- Otherwise: `gh gist create -d "Handoff: <short title>" HANDOFF.md`

Capture the resulting URL.

## On Completion

Print a 3-bullet summary in chat (don't echo the full handoff content):
- What's done
- What's next (top 1-2 actions)
- Where the handoff lives — file path and, if pushed, the gist or PR-comment URL
