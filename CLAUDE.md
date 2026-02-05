# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a personal dotfiles repository for Fedora/Linux development environments. It manages configuration files for bash, vim, git, and Claude Code settings via a single install script.

## Installation

```bash
./install.sh
```

This backs up existing files to `~/.dotfiles_backup/` and copies configurations to their target locations. After installation, run `source ~/.bashrc` or restart your shell.

## Repository Structure

- **Root dotfiles** (`.bashrc`, `.vimrc`, `.gitconfig`, etc.) - Source files copied to `$HOME`
- **`claude/`** - Claude Code configuration (copied to `~/.claude/`)
  - `settings.json` - Hook definitions and enabled plugins
  - `hooks/` - PostToolUse, Notification, and Stop hooks
  - `skills/` - Custom slash commands (create-plan, review-plan, implement-plan, etc.)
- **`terminator_config`** - Copied to `~/.config/terminator/config`

## Adding New Dotfiles

1. Add the file to the repository root (or appropriate subdirectory)
2. Add an entry to either `FILES` or `DIRS` associative array in `install.sh`
3. Run `./install.sh` to deploy

## Claude Code Hooks

The repository includes three hooks configured in `claude/settings.json`:

- **format-on-edit.sh** - Auto-formats Python (ruff) and JS/TS/JSON (prettier) after Edit operations. Reads config from `~/.claude/format-config.json`.
- **notify.sh** - Desktop notifications on permission prompts and task completion. Supports click-to-focus with dunstify.
- **review-on-stop.sh** - Spawns a review agent when `CLAUDE_REVIEW_ON_STOP=1` is set.

## Bash Customizations

The `.bashrc` includes:

- Persistent command logging to `~/.command_history.log` (searchable via `hgrep <pattern>`)
- Git branch with dirty indicator in prompt
- Terminal title shows running command (for notification click-to-focus)
- `claude` wrapper function that captures `CLAUDE_TERMINAL_WINDOW` for proper terminal focus
- Alias groups: git (`g`, `gs`, `ga`...), podman (`p`, `pps`...), python/uv (`uvr`, `uva`...), npm (`nr`, `ni`...)
- Utility functions: `mkcd`, `extract`, `ff`, `serve`, `backup`
- Modern CLI tool integration: fzf, bat, eza, ripgrep, zoxide (with fallbacks)
