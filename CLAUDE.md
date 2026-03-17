# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a personal dotfiles repository for Fedora/Linux development environments. It manages configuration files for bash, vim, git, and Claude Code settings via a single install script.

## Installation

```bash
./install.sh
```

This backs up existing files to `~/.dotfiles_backup/`, copies configurations to their target locations, sets up the hooks server virtualenv, and enables the systemd service. After installation, run `source ~/.bashrc` or restart your shell.

## Repository Structure

- **Root dotfiles** (`.bashrc`, `.vimrc`, `.gitconfig`, etc.) - Source files copied to `$HOME`
- **`claude/`** - Claude Code configuration (copied to `~/.claude/`)
  - `settings.json` - Permissions, HTTP hooks, shell hooks, and plugins
  - `hooks/` - Shell hooks (format-on-edit, notify, review-on-stop, post-compact)
  - `hooks/server/` - HTTP hooks server (FastAPI + SQLite)
  - `skills/` - Custom slash commands
- **`terminator_config`** - Copied to `~/.config/terminator/config`

## Adding New Dotfiles

1. Add the file to the repository root (or appropriate subdirectory)
2. Add an entry to either `FILES` or `DIRS` associative array in `install.sh`
3. Run `./install.sh` to deploy

## Claude Code Hooks

### Shell Hooks

- **format-on-edit.sh** - Auto-formats Python (ruff), JS/TS/JSON (prettier), and Rust (rustfmt) after Edit/Write operations. Reads config from `~/.claude/format-config.json`.
- **notify.sh** - Desktop notifications on permission prompts and task completion.
- **review-on-stop.sh** - Spawns a review agent when `CLAUDE_REVIEW_ON_STOP=1` is set.
- **post-compact.sh** - Re-injects critical context after context window compression. Reads project-specific reminders from `.claude/post-compact-reminders.md` if present.

### HTTP Hooks Server

A local FastAPI server at `http://localhost:6271` that receives all hook events via HTTP POST. Tracked data is stored in SQLite at `~/.claude/hooks-server.db`.

**Tracked events:** PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, UserPromptSubmit, Stop, SubagentStop, TaskCompleted.

**Features:**
- Session tracking with cost estimation (Anthropic published pricing)
- Full tool call audit log
- Permission request history
- PreToolUse security rules (`security-rules.json`) that block dangerous commands
- Web dashboard at `http://localhost:6271/dashboard`

**Management:**
```bash
claude-hooks start|stop|restart|status|logs|dashboard
```

## Permissions

The settings use an aggressive allow/deny model:
- **Allow:** All file tools, git, gh, cargo, npm/npx/node, python/uv/ruff/pytest, vercel, podman, make, and common Unix utilities
- **Deny:** Destructive operations (rm -rf /, force push, hard reset), sensitive files (.env, credentials, SSH keys)
- **Second layer:** HTTP PreToolUse hook checks `security-rules.json` regex patterns for more sophisticated blocking

## Skills (Slash Commands)

| Command | Description |
|---------|-------------|
| `/create-plan` | Generate implementation plan |
| `/review-plan` | Critique a plan |
| `/implement-plan` | Execute a plan's steps |
| `/review-implementation` | Verify implementation against plan |
| `/fix-from-log` | Fix bugs from error output |
| `/handoff` | Create handoff document for next session |
| `/commit-push-pr` | Stage, commit, push, and create PR |
| `/test-and-fix` | Run tests, fix failures, iterate until green |
| `/grill` | Adversarial code review |
| `/worktree` | Create git worktree for parallel sessions |
| `/deploy-preview` | Check Vercel preview deployment status |
| `/stats` | Show usage statistics from hooks server |

## Bash Customizations

The `.bashrc` includes:

- Persistent command logging to `~/.command_history.log` (searchable via `hgrep <pattern>`)
- Git branch with dirty indicator in prompt
- Terminal title shows running command (for notification click-to-focus)
- `claude` wrapper function that captures `CLAUDE_TTY` for proper terminal focus
- `claude-hooks` function for hooks server management
- `claude-worktree` function for creating parallel session worktrees
- Alias groups: git (`g`, `gs`, `ga`...), podman (`p`, `pps`...), python/uv (`uvr`, `uva`...), npm (`nr`, `ni`...)
- Utility functions: `mkcd`, `extract`, `ff`, `serve`, `backup`
- Modern CLI tool integration: fzf, bat, eza, ripgrep, zoxide (with fallbacks)
