---
name: sitrep
description: Fast, mobile-readable status report for the current repo — branch, uncommitted work, your open PRs with CI/review state, and PRs awaiting your review
argument-hint: ""
allowed-tools: Bash(git *), Bash(gh *)
---

Give a tight situation report so the user can decide what to work on next from their phone.

## Steps

1. **Gather data in parallel** (single message, multiple Bash calls):
   - `git status -sb` — branch + dirty state
   - `git log --oneline -5` — recent commits on this branch
   - `gh pr list --author=@me --state=open --json number,title,headRefName,statusCheckRollup,reviewDecision,url --limit 20` — your open PRs
   - `gh pr list --search "review-requested:@me state:open" --json number,title,url,author --limit 10` — PRs waiting on you

2. **For each of your open PRs**, derive a one-line status from `statusCheckRollup` (rolled-up CI: pass / fail / pending) and `reviewDecision` (APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED / null).

3. **Format output** — keep it under ~25 lines, phone-readable:

```
## <repo-name> — <branch>

**Working tree:** <clean | N uncommitted files: a.py, b.ts, ...>

**Your open PRs (N):**
- #123 Short title — CI: ✓  Review: approved  → ready to merge
- #124 Short title — CI: ✗  Review: pending   → fix CI
- #125 Short title — CI: …  Review: changes-requested → address comments

**Awaiting your review (N):**
- #126 Title (author) — <url>

**Recent commits:**
- abc1234 message
- def5678 message
```

4. **Suggest next action** in one line at the end (e.g. "Suggest: fix CI on #124 — try `/fix-from-log` after pasting the failing job log").

## Rules

- If there are no PRs in a category, write "(none)" — don't omit the section
- Use the URL field directly from `gh` — don't construct URLs by hand
- If `gh` isn't authenticated, surface that error and stop
- No PR number → no link required, but include the PR number so the user can act on it (`/address-comments 123`, etc.)
- Keep total output compact: one line per PR, no nested bullets
