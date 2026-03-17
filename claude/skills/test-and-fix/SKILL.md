---
name: test-and-fix
description: Run tests, analyze failures, fix them, and re-run until green
argument-hint: "[test command or file pattern]"
---

Run the project's test suite, analyze any failures, fix them, and iterate until all tests pass.

$ARGUMENTS

## Steps

1. **Detect test framework**: Look at the project to determine the right test command:
   - Python: `pytest`, `uv run pytest`, `python -m pytest`
   - JavaScript/TypeScript: `npm test`, `npx vitest`, `npx jest`
   - Rust: `cargo test`
   - Or use whatever the user specified in arguments

2. **Run tests**: Execute the test command and capture output.

3. **Analyze failures**: If tests fail:
   - Read the failing test files to understand what's being tested
   - Read the source code being tested
   - Identify the root cause (bug in source, not in test, unless the test is clearly wrong)

4. **Fix**: Make targeted fixes to the source code. Do NOT modify tests unless:
   - The test itself has a bug
   - The test is testing removed/renamed functionality
   - The user explicitly asked to update tests

5. **Re-run tests**: Run the test suite again. Repeat steps 3-4 up to 3 times.

6. **Report**: Summarize what was fixed and current test status.

## Rules

- Fix source code, not tests (unless tests are wrong)
- Make minimal, targeted fixes
- Do not refactor code that isn't related to the failing tests
- If you cannot fix a test after 3 attempts, report what you've tried and stop
