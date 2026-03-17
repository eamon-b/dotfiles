---
name: deploy-preview
description: Check Vercel preview deployment status for the current branch
argument-hint: "[PR number]"
allowed-tools: Bash(gh *), Bash(git *), Bash(curl *)
---

Check the status of Vercel preview deployments for the current branch or a specific PR.

$ARGUMENTS

## Steps

1. **Get context**: Determine the current branch and find the associated PR:
   ```bash
   git branch --show-current
   gh pr list --head $(git branch --show-current) --json number,title,url,statusCheckRollup --limit 1
   ```

2. **Check deployment status**: Get the PR's check runs which include Vercel deployments:
   ```bash
   gh pr checks [PR-NUMBER]
   ```

3. **Find preview URL**: Look for the Vercel deployment URL in:
   - PR check runs (Vercel bot creates deployment checks)
   - PR comments (Vercel bot posts preview URLs as comments):
     ```bash
     gh pr view [PR-NUMBER] --comments
     ```

4. **Report status**:
   - PR title and URL
   - Deployment status (pending / building / ready / failed)
   - Preview URL (if available)
   - Any failed checks

## Rules

- If no PR exists for the current branch, say so and suggest creating one
- If `gh` is not authenticated, provide instructions to authenticate
- If Vercel is not configured for the repo, explain what to look for
