#!/bin/bash
# setup-sandbox.sh
#
# Bootstrap dotfiles into a Claude Code cloud sandbox (the env behind claude.ai/code,
# accessed from the Claude mobile app). Designed to be the "Setup script" of a
# Claude Code on the web environment.
#
# Differences from install.sh:
#   - No systemd user service (sandbox usually has no systemd-user)
#   - No HTTP hooks server (settings.sandbox.json strips those hooks)
#   - No terminator/kitty configs, no .bashrc (the sandbox provides its own shell setup)
#   - Self-clones the dotfiles repo if not already present, so this script can be
#     pasted as a one-liner via curl
#
# Idempotent: safe to re-run.
#
# Usage as a Claude Code on the web setup script:
#
#   curl -sf https://raw.githubusercontent.com/eamon-b/dotfiles/main/setup-sandbox.sh | bash
#
# Or, after the repo has been cloned:
#
#   bash ~/.dotfiles/setup-sandbox.sh

set -e

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/eamon-b/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

log() { echo "[setup-sandbox] $*"; }

# ---------------------------------------------------------------------------
# 1. Ensure the dotfiles repo is present
# ---------------------------------------------------------------------------
if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
    log "Cloning dotfiles into $DOTFILES_DIR"
    git clone --depth 1 "$DOTFILES_REPO" "$DOTFILES_DIR"
else
    log "Updating dotfiles in $DOTFILES_DIR"
    git -C "$DOTFILES_DIR" pull --ff-only 2>/dev/null || \
        log "Note: could not fast-forward dotfiles (not fatal)"
fi

cd "$DOTFILES_DIR"

# ---------------------------------------------------------------------------
# 2. Claude skills
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.claude/skills"
cp -r "$DOTFILES_DIR/claude/skills/." "$HOME/.claude/skills/"
log "Installed Claude skills -> ~/.claude/skills/"

# External skills (cloned from git)
declare -A EXTERNAL_SKILLS=(
    ["napkin"]="https://github.com/blader/napkin.git"
)
for skill in "${!EXTERNAL_SKILLS[@]}"; do
    skill_dir="$HOME/.claude/skills/$skill"
    repo_url="${EXTERNAL_SKILLS[$skill]}"
    if [[ -d "$skill_dir/.git" ]]; then
        git -C "$skill_dir" pull --ff-only 2>/dev/null || \
            log "Note: could not update $skill"
    else
        rm -rf "$skill_dir"
        git clone --depth 1 "$repo_url" "$skill_dir" 2>/dev/null || \
            log "Note: could not clone $skill"
    fi
done

# ---------------------------------------------------------------------------
# 3. Claude settings (sandbox variant — no localhost hooks server)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.claude"
if [[ -f "$DOTFILES_DIR/claude/settings.sandbox.json" ]]; then
    cp "$DOTFILES_DIR/claude/settings.sandbox.json" "$HOME/.claude/settings.json"
    log "Installed sandbox Claude settings -> ~/.claude/settings.json"
else
    log "Warning: settings.sandbox.json missing, falling back to local settings.json"
    cp "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
fi

# ---------------------------------------------------------------------------
# 4. Claude hooks (only the scripts referenced by sandbox settings)
# ---------------------------------------------------------------------------
mkdir -p "$HOME/.claude/hooks"
for hook in format-on-edit.sh compact-reminder.sh; do
    src="$DOTFILES_DIR/claude/hooks/$hook"
    if [[ -f "$src" ]]; then
        cp "$src" "$HOME/.claude/hooks/$hook"
        chmod +x "$HOME/.claude/hooks/$hook"
    fi
done
# format-on-edit reads its config from ~/.claude/format-config.json if present;
# copy if the dotfiles repo ships one
if [[ -f "$DOTFILES_DIR/claude/format-config.json" ]]; then
    cp "$DOTFILES_DIR/claude/format-config.json" "$HOME/.claude/format-config.json"
fi
log "Installed Claude hooks -> ~/.claude/hooks/"

# ---------------------------------------------------------------------------
# 5. Git config and ignore
# ---------------------------------------------------------------------------
[[ -f "$DOTFILES_DIR/.gitignore_global" ]] && \
    cp "$DOTFILES_DIR/.gitignore_global" "$HOME/.gitignore_global" && \
    git config --global core.excludesfile "$HOME/.gitignore_global"

# Keep the existing GitHub-integrated user identity in the cloud env if already set;
# otherwise apply a sensible default for personal projects.
if [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
    git config --global user.email "${GIT_USER_EMAIL:-barretteamon@gmail.com}"
fi
if [[ -z "$(git config --global user.name 2>/dev/null)" ]]; then
    git config --global user.name "${GIT_USER_NAME:-eamon-b}"
fi
git config --global init.defaultBranch main
git config --global pull.ff only
log "Configured git"

# ---------------------------------------------------------------------------
# 6. Editor config + vim
# ---------------------------------------------------------------------------
[[ -f "$DOTFILES_DIR/.editorconfig" ]] && cp "$DOTFILES_DIR/.editorconfig" "$HOME/.editorconfig"
[[ -f "$DOTFILES_DIR/.vimrc" ]] && cp "$DOTFILES_DIR/.vimrc" "$HOME/.vimrc"

# ---------------------------------------------------------------------------
# 7. Sanity output
# ---------------------------------------------------------------------------
log "Sandbox setup complete."
log "Skills available: $(ls "$HOME/.claude/skills" | tr '\n' ' ')"
log "Settings: $HOME/.claude/settings.json"
log ""
log "Suggested first prompt: /sitrep"
