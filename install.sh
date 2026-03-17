#!/bin/bash

# Dotfiles installation script
# Copies dotfiles from this repo to their proper system locations

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.dotfiles_backup"

# Files to install (source -> destination)
declare -A FILES=(
    [".bashrc"]="$HOME/.bashrc"
    ["claude/settings.json"]="$HOME/.claude/settings.json"
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
    mkdir -p "$(dirname "$dest")"

    # Backup existing directory
    backup_dir "$dest"

    # Copy the directory
    cp -r "$src" "$dest"
    echo "Installed $src -> $dest"
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

for src in "${!DIRS[@]}"; do
    src_path="$DOTFILES_DIR/$src"
    dest_path="${DIRS[$src]}"

    if [[ -d "$src_path" ]]; then
        install_dir "$src_path" "$dest_path"
    else
        echo "Warning: $src_path not found, skipping"
    fi
done

echo "========================================="
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

# Make hook scripts executable
chmod +x "$HOME/.claude/hooks/"*.sh 2>/dev/null || true
chmod +x "$HOME/.claude/hooks/server/"*.sh 2>/dev/null || true

# Enable and start the systemd service
if command -v systemctl &>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user enable claude-hooks.service 2>/dev/null && \
        echo "Enabled claude-hooks.service"
    systemctl --user start claude-hooks.service 2>/dev/null && \
        echo "Started claude-hooks.service" || \
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
