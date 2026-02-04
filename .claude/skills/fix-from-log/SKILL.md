---
name: fix-from-log
description: Fix a bug given log output, error message, or observed behavior
argument-hint: "<error/log output or description of incorrect behavior>"
---

Fix the bug described by the following log output, error message, or behavior:

$ARGUMENTS

## Process

1. **Analyze the error** - Parse the log/error to identify:
   - Error type and message
   - Stack trace or file/line references
   - Relevant variable values or state

2. **Locate the source** - Find the code responsible:
   - Use stack traces if available
   - Search for error messages, function names, or unique strings
   - Trace the code path that leads to the error

3. **Understand the root cause** - Before fixing:
   - Read the surrounding code for context
   - Identify why the error occurs, not just where
   - Consider edge cases that trigger the bug

4. **Implement the fix** - Make minimal, targeted changes:
   - Fix only the identified bug
   - Don't refactor or improve unrelated code
   - Preserve existing behavior for non-buggy cases

5. **Verify** - If possible:
   - Run the code path that triggered the error
   - Check that the fix doesn't break other functionality

## Guidelines

- If the error references a file and line number, start there
- If the error message is unique, grep for it to find where it's raised
- Consider whether the bug is in the code or the input/environment
- If multiple potential causes exist, address the most likely one first
- Ask for clarification if the error is ambiguous or could have multiple interpretations
