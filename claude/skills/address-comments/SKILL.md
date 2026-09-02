---
name: address-comments
description: Pull review comments on a PR, address each one with a code change or reply, and push
argument-hint: "[PR number — defaults to the PR for the current branch]"
disable-model-invocation: true
allowed-tools: Bash(git *), Bash(gh *), Read, Edit, Write, Grep, Glob
---

Address review comments on a pull request end-to-end. Designed for handling reviewer feedback from a phone.

$ARGUMENTS

## Steps

1. **Identify the PR**:
   - If a number is given in arguments, use it.
   - Otherwise: `gh pr view --json number,title,headRefName,url` to find the PR for the current branch.
   - If no PR is found, stop and tell the user.

2. **Sync local with remote**:
   - `gh pr checkout <number>` (idempotent — also works if already on the branch)
   - `git pull --ff-only`

3. **Fetch comments** (parallel):
   - Inline review comments: `gh api repos/{owner}/{repo}/pulls/<number>/comments`
   - General PR comments: `gh api repos/{owner}/{repo}/issues/<number>/comments`
   - Review summaries: `gh pr view <number> --json reviews`

   Filter to comments authored by users other than the PR author, and to those without a later resolution/reply from the PR author.

4. **Triage each comment** into one of:
   - **Code change** — clear, actionable, you can do it safely
   - **Reply only** — questions, clarifications, or "won't fix" with a reason
   - **Needs user input** — ambiguous, requires a design call, or risk-flagged

5. **Make the code changes**. Group related changes into one commit. Use clear messages referencing the comment intent (not the comment ID).

6. **Push** to the PR branch.

7. **Reply to comments you addressed** (optional, ask user if uncertain):
   - For inline: `gh api repos/{owner}/{repo}/pulls/<number>/comments/<comment-id>/replies -f body="Addressed in <sha>."`
   - For general: `gh pr comment <number> --body "..."`
   - Don't mark anything resolved — leave that to the reviewer.

8. **Report** in chat (compact, phone-readable):

```
## PR #N — addressed M of K comments

**Code changes (X):**
- Comment by @reviewer on file.py:42 — "..." → fixed by <sha>
- ...

**Replied without code change (Y):**
- Comment by @reviewer — "..." → replied: "..."

**Needs your input (Z):**
- Comment by @reviewer on file.py:99 — "..." → why you skipped it

**New commits pushed:** <sha1>, <sha2>
**PR:** <url>
```

## Rules

- Never mark a reviewer's comment resolved
- If a comment is unsafe to address autonomously (e.g. "rewrite the auth module"), put it under "Needs your input" and skip — don't guess
- If there are no unresolved comments, say so and stop
- Don't force-push; the PR branch should accept normal pushes
- One commit per logical group, or follow the repo's existing commit-message style (check `git log --oneline -5`)
