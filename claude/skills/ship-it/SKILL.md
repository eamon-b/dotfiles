---
name: ship-it
description: Take a small change from idea to PR in one shot — implement, verify, commit, push, open PR. For small, well-scoped personal-project work; not for large or design-heavy changes.
argument-hint: "<description of the change>"
allowed-tools: Bash(git *), Bash(gh *), Read, Edit, Write, Grep, Glob, Bash(npm *), Bash(npx *), Bash(uv *), Bash(uvx *), Bash(pytest *), Bash(cargo *), Bash(python *), Bash(node *), Bash(make *), Bash(ruff *), Bash(prettier *), Bash(eslint *), Bash(tsc *)
---

End-to-end small-change workflow. Designed for phone use against a remote sandbox.

Change to make:

$ARGUMENTS

## Process

1. **Scope check** — this skill is for *small* changes:
   - Single feature, single bug fix, or small refactor
   - Roughly ≤5 files, no architectural decisions
   - If the change looks larger or genuinely ambiguous, **stop** and recommend `/create-plan` instead.

2. **Clarify if blocked** — if the description is too vague to act on safely (e.g. "make it faster", "fix the thing"), ask **one** focused question and stop. Don't guess.

3. **Branch** — if currently on `main`/`master`/`develop`, create a feature branch:
   ```bash
   git checkout -b <kebab-case-summary>
   ```

4. **Implement** — read relevant files first, follow existing patterns, keep the diff focused. Don't refactor unrelated code.

5. **Verify** — auto-detect and run what's reasonable:
   - Tests: pytest / vitest / jest / cargo test (only the affected subset if obvious)
   - Typecheck: `tsc --noEmit`, `mypy`, etc.
   - Linter/formatter: only if pre-existing in repo; don't introduce one
   - If verification fails, fix and retry up to **2** times. After that, commit what works and surface the remaining failures in the PR description.

6. **Commit, push, open PR**:
   - Commit message follows repo style (check `git log --oneline -5`)
   - PR title ≤70 chars
   - PR body: 1-3 bullet `## Summary`, plus a `## Test plan` section describing what was verified (and what wasn't)

7. **Report** — final chat output is exactly:
   ```
   Shipped <PR title> — <PR URL>
   <one-line note about anything skipped or left for the user>
   ```
   Nothing else. If there are no caveats, omit the second line.

## Rules

- Never push directly to `main`/`master`
- Never force-push
- Never commit secrets, `.env` files, or large binaries
- If verification fails irrecoverably, still push and open the PR with a clear "⚠ tests failing" note in the body — the user is on a phone and shouldn't be left with uncommitted work in a sandbox that may evaporate
- If `gh` isn't authenticated, push the branch and report the push URL with instructions to open the PR manually
- Keep all chat output phone-readable: short bullets, no walls of code
