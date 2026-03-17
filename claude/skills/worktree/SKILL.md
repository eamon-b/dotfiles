---
name: worktree
description: Create a git worktree for parallel Claude Code sessions
argument-hint: "<branch-name> [base-branch]"
---

Create a new git worktree for running a parallel Claude Code session.

> **Note:** Claude Code natively supports `claude --worktree <name>` (creates worktrees at `<repo>/.claude/worktrees/<name>`, branches from default remote). Use this skill when you want sibling-directory placement (`../project--<branch>`) or need to specify a custom base branch.

$ARGUMENTS

## Steps

1. **Parse arguments**: Extract the branch name (required) and optional base branch (defaults to current branch).

2. **Create worktree directory**: Use a sibling directory structure:
   ```bash
   # If repo is at /path/to/project, create worktree at /path/to/project--<branch>
   git worktree add "../$(basename $(pwd))--<branch-name>" -b <branch-name> [base-branch]
   ```

3. **List worktrees**: Show all active worktrees with `git worktree list`.

4. **Print instructions**:
   ```
   Worktree created. To start a parallel Claude session:

     cd <worktree-path>
     claude

   To remove the worktree when done:

     git worktree remove <worktree-path>
   ```

## Rules

- If the branch already exists, check it out instead of creating with `-b`
- If no branch name is provided, ask the user for one
- Never create worktrees inside the current repo directory
- Show existing worktrees so the user can see what's already running
