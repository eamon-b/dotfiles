---
name: stats
description: Show Claude Code usage statistics from the hooks server dashboard
argument-hint: "[days - default 7]"
allowed-tools: Bash(curl *)
---

Query the Claude Code hooks server and display usage statistics.

$ARGUMENTS

## Steps

1. **Check server**: Verify the hooks server is running:
   ```bash
   curl -sf http://localhost:6271/health
   ```
   If not running, tell the user to start it: `systemctl --user start claude-hooks` or `~/.claude/hooks/server/start.sh`

2. **Fetch stats**: Query the stats API (use the number of days from arguments, default 7):
   ```bash
   curl -s "http://localhost:6271/api/stats?days=7"
   ```

3. **Fetch recent sessions**:
   ```bash
   curl -s "http://localhost:6271/api/sessions?limit=10"
   ```

4. **Fetch blocked actions**:
   ```bash
   curl -s "http://localhost:6271/api/blocked?limit=10"
   ```

5. **Format and display** the results as a readable report:

   ```
   ## Claude Code Usage (Last N Days)

   | Metric          | Value |
   |-----------------|-------|
   | Sessions        | X     |
   | Tool Calls      | X     |
   | Prompts         | X     |
   | Est. Cost       | $X.XX |
   | Blocked Actions | X     |
   | Permission Reqs | X     |

   ### Top Tools
   1. Bash (245 calls)
   2. Edit (183 calls)
   ...

   ### Recent Sessions
   ...

   ### Blocked Actions
   ...
   ```

6. Also mention the dashboard URL: http://localhost:6271/dashboard
