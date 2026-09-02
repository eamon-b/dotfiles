# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a personal dotfiles repository for Fedora/Linux development environments. It manages configuration files for bash, vim, git, and Claude Code settings via a single install script.

## Installation

### Local machine

```bash
./install.sh
```

This backs up existing files to `~/.dotfiles_backup/`, copies configurations to their target locations, sets up the hooks server virtualenv, and enables the systemd service. After installation, run `source ~/.bashrc` or restart your shell.

Two things are merged rather than overwritten so machine-local plugin state survives a reinstall:

- `~/.claude/settings.json` — the repo file is authoritative, but `enabledPlugins` and `extraKnownMarketplaces` are unioned with whatever is already registered locally (plugins installed via `/plugin` or `claude plugin install`).
- `~/.claude/skills/` — the repo's skills are copied in; skills from marketplaces or `npx skills` are left alone. A manifest (`~/.claude/skills/.dotfiles-managed`) records which directories the repo installed, and only those are removed when a skill is deleted from the repo.

### Claude Code cloud sandbox (mobile-app workflow)

For the cloud environment behind `claude.ai/code` / the Claude mobile app, use `setup-sandbox.sh` instead. Paste this into the environment's **Setup script** field:

```bash
curl -sf https://raw.githubusercontent.com/eamon-b/dotfiles/main/setup-sandbox.sh | bash
```

The sandbox variant skips systemd, the HTTP hooks server, terminator/kitty, and `.bashrc` (none of which are useful in a cloud container) and uses `claude/settings.sandbox.json` — same permissions, but no `localhost:6271` hooks. It installs the Claude skills, the `format-on-edit` and `compact-reminder` hooks, gitconfig, and editorconfig.

**Adding files to the sandbox install:** if a file in `install.sh` should also be present in the cloud sandbox, add it to `setup-sandbox.sh` too. Things to deliberately skip: anything depending on systemd, the local hooks server, desktop notifications, or terminal emulators.

## Repository Structure

- **Root dotfiles** (`.bashrc`, `.vimrc`, `.gitconfig`, etc.) - Source files copied to `$HOME`
- **`claude/`** - Claude Code configuration (copied to `~/.claude/`)
  - `settings.json` - Permissions (auto mode), model, HTTP hooks, shell hooks, plugins, `plansDirectory`
  - `hooks/` - Shell hooks (format-on-edit, notify, review-on-stop, compact-reminder)
  - `hooks/server/` - HTTP hooks server (FastAPI + SQLite)
  - `skills/` - Custom slash commands
- **`terminator_config`** - Copied to `~/.config/terminator/config`

## Adding New Dotfiles

1. Add the file to the repository root (or appropriate subdirectory)
2. Add an entry to either `FILES` or `DIRS` associative array in `install.sh`
3. Run `./install.sh` to deploy

## Claude Code Hooks

### Shell Hooks

- **format-on-edit.sh** - Auto-formats Python (ruff), JS/TS/JSON (prettier), and Rust (rustfmt) after Edit/Write operations. Reads the path from `tool_input.file_path` in the hook payload and config from `~/.claude/format-config.json`. Logs to `~/.claude/debug/format-hook.log`.
- **notify.sh** - Desktop notifications on permission prompts and task completion (Kitty OSC 99 with click-to-focus, `notify-send` fallback).
- **review-on-stop.sh** - When `CLAUDE_REVIEW_ON_STOP=1`, blocks the first Stop of a turn that leaves uncommitted changes and asks Claude to run the bundled `/code-review` on them. Honors `stop_hook_active` so it never blocks twice. Runs synchronously (a blocking decision can't come from an async hook).
- **compact-reminder.sh** - Re-injects critical context after context window compression. Wired as a `SessionStart` hook with matcher `compact`, because only SessionStart / UserPromptSubmit stdout reaches the model (PostCompact stdout only goes to the debug log). Reads project-specific reminders from `.claude/post-compact-reminders.md` if present.

Hook payload facts that bit us before (see the hooks reference at code.claude.com/docs/en/hooks): file paths are under `tool_input`, the tool result is `tool_response` (failures use `error`), `SubagentStop` gives the main transcript as `transcript_path` and the subagent's own as `agent_transcript_path`, and `timeout` is in seconds.

### HTTP Hooks Server

A local FastAPI server at `http://localhost:6271` that receives all hook events via HTTP POST. Tracked data is stored in SQLite at `~/.claude/hooks-server.db`.

**Tracked events:** PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, UserPromptSubmit, Stop, SubagentStop, TaskCompleted.

**Features:**
- Session tracking with cost estimation (Anthropic published pricing — see `MODEL_PRICING` in `app.py`). A session's cost is the main transcript plus every subagent transcript under `<project>/<session_id>/subagents/`, recomputed from scratch on Stop / SubagentStop / TaskCompleted.
- Cache writes are priced by TTL from `usage.cache_creation` (1h = 2x input, 5m = 1.25x); transcripts without the breakdown are priced at 5m.
- Per-category cost breakdown (input / output / cache-write / cache-read), shown on the dashboard and in the session drill-down
- Full tool call audit log
- Permission request history
- PreToolUse security rules (`security-rules.json`) that block dangerous commands
- Web dashboard at `http://localhost:6271/dashboard`

**Management:**
```bash
claude-hooks start|stop|restart|status|logs|dashboard
```

**Maintenance:** after changing prices in `MODEL_PRICING`, recompute historical rows with the backfill (re-reads transcripts, falls back to stored token totals, and rebuilds `daily_stats`):
```bash
~/.claude/hooks/server/.venv/bin/python ~/.claude/hooks/server/backfill_costs.py [--dry-run]
```

## Permissions

The settings use an aggressive allow/deny model:
- **Allow:** All file tools, git, gh, cargo, npm/npx/node, python/uv/ruff/pytest, vercel, podman, make, and common Unix utilities
- **Deny:** Destructive operations (rm -rf /, force push, hard reset), sensitive files (.env, credentials, SSH keys)
- **Second layer:** HTTP PreToolUse hook checks `security-rules.json` regex patterns for more sophisticated blocking

## Skills (Slash Commands)

| Command | Description |
|---------|-------------|
| `/create-plan` | Write a plan to `.claude/plans/<topic>.md` (status: draft) |
| `/review-plan` | Critique the plan in place, append Review Notes (status: reviewed) |
| `/implement-plan` | Execute the plan, ticking steps off and logging deviations in the file (status: implemented) |
| `/review-implementation` | Verify the result against the plan, append Implementation Review (status: verified / needs-changes) |
| `/fix-from-log` | Fix bugs from error output |
| `/handoff` | Create handoff document for next session |
| `/commit-push-pr` | Stage, commit, push, and create PR |
| `/test-and-fix` | Run tests, fix failures, iterate until green |
| `/ship-it` | End-to-end small change: implement → verify → commit → PR (phone-friendly) |
| `/sitrep` | Mobile-readable status report: branch, uncommitted, your PRs, CI, review-requested |
| `/address-comments` | Pull PR review comments, address each, push (phone-friendly) |
| `/deploy-preview` | Check Vercel preview deployment status |

Skills with side effects (`commit-push-pr`, `ship-it`, `address-comments`) and the plan skills set `disable-model-invocation: true`, so they only run when typed as a slash command. Adversarial review, usage stats, and worktrees are covered by the bundled `/code-review`, `/security-review`, `/usage` (aliases `/stats`, `/cost`), and `claude --worktree` / `/batch`, so there are no custom skills for them.

### Plan workflow

Plans are living documents in the project's `.claude/plans/` directory. `plansDirectory` in settings points native plan mode (`/plan`) at the same place, so every plan is visible in the working tree, editable by hand between steps, and kept after implementation as a record of intent → review → implementation log → verification. Each plan skill resolves the most recently modified file in `.claude/plans/` when no path is given. The directory is ignored via `.gitignore_global`, so plans stay local to the machine.

## Bash Customizations

The `.bashrc` includes:

- Persistent command logging to `~/.command_history.log` (searchable via `hgrep <pattern>`)
- Git branch with dirty indicator in prompt
- Terminal title shows running command (for notification click-to-focus)
- `claude` wrapper function that captures `CLAUDE_TTY` for proper terminal focus
- `claude-hooks` function for hooks server management
- Alias groups: git (`g`, `gs`, `ga`...), podman (`p`, `pps`...), python/uv (`uvr`, `uva`...), npm (`nr`, `ni`...)
- Utility functions: `mkcd`, `extract`, `ff`, `serve`, `backup`
- Modern CLI tool integration: fzf, bat, eza, ripgrep, zoxide (with fallbacks)
