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
)

# Directories to install (source -> destination)
declare -A DIRS=(
    ["claude/hooks"]="$HOME/.claude/hooks"
    ["claude/skills"]="$HOME/.claude/skills"
)

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
echo "Installation complete!"

if [[ -d "$BACKUP_DIR" ]]; then
    echo "Backups saved to: $BACKUP_DIR"
fi

echo ""
echo "Note: You may need to restart your shell or run 'source ~/.bashrc' for changes to take effect."
