#!/bin/bash

# Dotfiles installation script
# Copies dotfiles from this repo to their proper system locations

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup"

# Files to install (source -> destination)
declare -A FILES=(
    [".bashrc"]="$HOME/.bashrc"
    [".editorconfig"]="$HOME/.editorconfig"
    [".gitconfig"]="$HOME/.gitconfig"
    [".gitignore_global"]="$HOME/.gitignore_global"
    [".inputrc"]="$HOME/.inputrc"
    [".vimrc"]="$HOME/.vimrc"
    ["terminator_config"]="$HOME/.config/terminator/config"
    ["kitty.conf"]="$HOME/.config/kitty/kitty.conf"
)

# Directories to install (source -> destination)
declare -A DIRS=(
    ["claude/hooks"]="$HOME/.claude/hooks"
    ["claude/skills"]="$HOME/.claude/skills"
)

# Claude settings are merged, not copied: the repo owns every key it defines,
# but plugins/marketplaces registered on this machine (via `claude plugin
# install`, `/plugin`, or the marketplace UI) are unioned in so an install
# never un-registers them.
CLAUDE_SETTINGS_SRC="claude/settings.json"
CLAUDE_SETTINGS_DEST="$HOME/.claude/settings.json"

# ~/.claude/skills is shared with skills installed from marketplaces and
# `npx skills`, so the repo only ever touches the skill directories it
# installed itself. This manifest records which those are, so a skill removed
# from the repo is removed from ~/.claude/skills on the next install without
# touching anything else in there.
SKILLS_MANIFEST="$HOME/.claude/skills/.dotfiles-managed"

# Systemd user service for Claude Code hooks server
HOOKS_SERVICE_SRC="claude/hooks/server/claude-hooks.service"
HOOKS_SERVICE_DEST="$HOME/.config/systemd/user/claude-hooks.service"

backup_file() {
    local dest="$1"
    if [[ -e "$dest" || -L "$dest" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup_path="$BACKUP_DIR/$(basename "$dest")"
        # Remove existing backup if present
        if [[ -e "$backup_path" || -L "$backup_path" ]]; then
            rm -f "$backup_path"
        fi
        echo "Backing up $dest -> $backup_path"
        mv "$dest" "$backup_path"
    fi
}

backup_dir() {
    local dest="$1"
    if [[ -e "$dest" || -L "$dest" ]]; then
        mkdir -p "$BACKUP_DIR"
        local backup_path="$BACKUP_DIR/$(basename "$dest")"
        # Remove existing backup if present
        if [[ -e "$backup_path" || -L "$backup_path" ]]; then
            rm -rf "$backup_path"
        fi
        echo "Backing up $dest -> $backup_path"
        mv "$dest" "$backup_path"
    fi
}

install_file() {
    local src="$1"
    local dest="$2"

    # Create parent directory if needed
    mkdir -p "$(dirname "$dest")"

    # Backup existing file
    backup_file "$dest"

    # Copy the file
    cp "$src" "$dest"
    echo "Installed $src -> $dest"
}

install_dir() {
    local src="$1"
    local dest="$2"

    # Create parent directory if needed
    mkdir -p "$dest"

    # Merge: copy repo contents into destination without removing existing files
    # (e.g. externally-cloned skills won't be wiped out)
    cp -r "$src"/. "$dest"/
    echo "Installed $src -> $dest (merged)"
}

install_claude_settings() {
    local src="$1"
    local dest="$2"

    mkdir -p "$(dirname "$dest")"

    if [[ -f "$dest" ]] && command -v jq &>/dev/null && jq -e . "$dest" &>/dev/null; then
        local merged
        # The repo file is authoritative (so removed hooks/keys really go
        # away); only the plugin/marketplace registries are unioned.
        merged=$(jq -s '
            .[0] as $existing | .[1] as $repo
            | $repo
            | .enabledPlugins = (($existing.enabledPlugins // {}) + ($repo.enabledPlugins // {}))
            | .extraKnownMarketplaces = (($existing.extraKnownMarketplaces // {}) + ($repo.extraKnownMarketplaces // {}))
        ' "$dest" "$src")
        backup_file "$dest"
        printf '%s\n' "$merged" > "$dest"
        echo "Installed $src -> $dest (merged; kept locally registered plugins/marketplaces)"
    else
        install_file "$src" "$dest"
    fi
}

# Remove skill dirs that a previous install put in ~/.claude/skills but that
# no longer exist in the repo. Only names recorded in the manifest are ever
# deleted, so marketplace/external skills are never touched.
# Skills the repo shipped before the manifest existed; pruned on the first
# run that has no manifest yet, then the manifest takes over.
LEGACY_REPO_SKILLS=(stats grill worktree)

prune_removed_skills() {
    local dest="$HOME/.claude/skills"
    local manifest="$SKILLS_MANIFEST"
    if [[ ! -f "$manifest" ]]; then
        manifest=$(mktemp)
        printf '%s\n' "${LEGACY_REPO_SKILLS[@]}" > "$manifest"
    fi
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        if [[ ! -d "$DOTFILES_DIR/claude/skills/$name" && -d "$dest/$name" && ! -d "$dest/$name/.git" ]]; then
            rm -rf "$dest/$name"
            echo "Removed skill no longer in repo: $name"
        fi
    done < "$manifest"
    [[ "$manifest" != "$SKILLS_MANIFEST" ]] && rm -f "$manifest"
    return 0
}

write_skills_manifest() {
    mkdir -p "$HOME/.claude/skills"
    ls -1 "$DOTFILES_DIR/claude/skills" > "$SKILLS_MANIFEST"
}

echo "Installing dotfiles from $DOTFILES_DIR"
echo "========================================="

for src in "${!FILES[@]}"; do
    src_path="$DOTFILES_DIR/$src"
    dest_path="${FILES[$src]}"

    if [[ -f "$src_path" ]]; then
        install_file "$src_path" "$dest_path"
    else
        echo "Warning: $src_path not found, skipping"
    fi
done

install_claude_settings "$DOTFILES_DIR/$CLAUDE_SETTINGS_SRC" "$CLAUDE_SETTINGS_DEST"

prune_removed_skills

for src in "${!DIRS[@]}"; do
    src_path="$DOTFILES_DIR/$src"
    dest_path="${DIRS[$src]}"

    if [[ -d "$src_path" ]]; then
        install_dir "$src_path" "$dest_path"
    else
        echo "Warning: $src_path not found, skipping"
    fi
done

write_skills_manifest

echo "========================================="
echo ""

# Create ~/.gitconfig.local if it doesn't exist (for [user] and machine-specific git config)
if [[ ! -f "$HOME/.gitconfig.local" ]]; then
    cat > "$HOME/.gitconfig.local" << 'EOF'
# Machine-specific git config (not tracked in dotfiles repo)
# Add your [user] section here, e.g.:
# [user]
#     name = Your Name
#     email = your@email.com
EOF
    echo "Created ~/.gitconfig.local (add your [user] section there)"
else
    echo "~/.gitconfig.local already exists, leaving it alone"
fi

echo ""

# ---------------------------------------------------------------------------
# External skills (cloned from git)
# ---------------------------------------------------------------------------

declare -A EXTERNAL_SKILLS=(
    ["napkin"]="https://github.com/blader/napkin.git"
)

for skill in "${!EXTERNAL_SKILLS[@]}"; do
    skill_dir="$HOME/.claude/skills/$skill"
    repo_url="${EXTERNAL_SKILLS[$skill]}"
    if [[ -d "$skill_dir/.git" ]]; then
        echo "Updating skill $skill..."
        git -C "$skill_dir" pull --ff-only 2>/dev/null || \
            echo "Warning: Could not update $skill (pull failed)"
    else
        echo "Installing skill $skill..."
        rm -rf "$skill_dir"
        git clone "$repo_url" "$skill_dir"
    fi
done

echo ""

# ---------------------------------------------------------------------------
# Claude Code hooks server setup
# ---------------------------------------------------------------------------

echo "Setting up Claude Code hooks server..."

# Install systemd service
mkdir -p "$(dirname "$HOOKS_SERVICE_DEST")"
if [[ -f "$DOTFILES_DIR/$HOOKS_SERVICE_SRC" ]]; then
    cp "$DOTFILES_DIR/$HOOKS_SERVICE_SRC" "$HOOKS_SERVICE_DEST"
    echo "Installed systemd service -> $HOOKS_SERVICE_DEST"
fi

# Create venv and install deps for the hooks server
SERVER_DIR="$HOME/.claude/hooks/server"
if [[ -d "$SERVER_DIR" && -f "$SERVER_DIR/requirements.txt" ]]; then
    if [[ ! -d "$SERVER_DIR/.venv" ]]; then
        echo "Creating hooks server virtualenv..."
        python3 -m venv "$SERVER_DIR/.venv"
    fi
    echo "Installing hooks server dependencies..."
    "$SERVER_DIR/.venv/bin/pip" install -q -r "$SERVER_DIR/requirements.txt"
fi

# Hook scripts the repo no longer ships (renamed or removed)
rm -f "$HOME/.claude/hooks/post-compact.sh"

# Make hook scripts executable
chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
chmod +x "$HOME/.claude/hooks/server/"*.sh 2>/dev/null || true

# Enable and start the systemd service
if command -v systemctl &>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user enable claude-hooks.service 2>/dev/null && \
        echo "Enabled claude-hooks.service"
    # restart (not start) so a running server picks up the new app.py
    systemctl --user restart claude-hooks.service 2>/dev/null && \
        echo "Restarted claude-hooks.service" || \
        echo "Note: Could not start claude-hooks.service (run manually with: systemctl --user start claude-hooks)"
fi

echo ""
echo "========================================="
echo "Installation complete!"

if [[ -d "$BACKUP_DIR" ]]; then
    echo "Backups saved to: $BACKUP_DIR"
fi

echo ""
echo "Note: You may need to restart your shell or run 'source ~/.bashrc' for changes to take effect."
echo ""
echo "Claude Code hooks dashboard: http://localhost:6271/dashboard"
echo "Manage hooks server: systemctl --user {start|stop|status} claude-hooks"
