---
name: commit-push-pr
description: Stage, commit, push, and create a pull request in one step
argument-hint: "[description of changes or PR title]"
---

Automate the full commit-to-PR workflow for the current changes.

$ARGUMENTS

## Steps

1. **Assess changes**: Run `git status` and `git diff --staged` and `git diff` to understand what has changed.

2. **Stage changes**: Add relevant files. Prefer `git add` with specific files over `git add -A`. Never stage `.env`, credentials, or large binary files.

3. **Commit**: Write a concise commit message that explains the *why* not just the *what*. Follow the repository's existing commit message style (check `git log --oneline -10`).

4. **Push**: Push to the remote. If on `main`/`master`, create a feature branch first:
   ```bash
   git checkout -b <descriptive-branch-name>
   ```
   Push with `-u` to set upstream tracking.

5. **Create PR**: Use `gh pr create` with:
   - A short title (under 70 chars)
   - A body with `## Summary` (2-3 bullet points) and `## Test plan`
   - Appropriate labels if the repo uses them

6. **Report**: Print the PR URL when done.

## Rules

- NEVER force push
- NEVER push directly to main/master without creating a branch first
- NEVER commit files that contain secrets or credentials
- If there are no changes to commit, say so and stop
- If `gh` is not installed, stop after pushing and tell the user to create the PR manually
