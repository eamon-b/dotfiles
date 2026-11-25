#!/usr/bin/env bash
# fedora/bootstrap.sh
#
# One-shot setup for a fresh Fedora (Cinnamon spin) install: system updates,
# third-party repos, packages, flatpaks, user toolchains, then ../install.sh
# for the dotfiles themselves. Run as your normal user (it calls sudo itself).
#
# Idempotent: safe to re-run; already-done steps are skipped or no-ops.
# Non-critical steps warn and carry on, and failures are listed at the end.
#
#   ./fedora/bootstrap.sh
#
# Edit the lists below to change what gets installed.

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DNF_PACKAGES=(
    # core / shell
    git git-lfs gh curl wget jq unzip p7zip p7zip-plugins zstd
    vim neovim tmux htop fzf ripgrep bat fd-find zoxide xclip
    # build tooling (rust linking, native node/python modules)
    @development-tools
    # desktop apps
    kitty code google-chrome-stable claude-desktop
    flameshot variety dunst libnotify parcellite
    seahorse gnome-keyring git-credential-libsecret
    # sync / network
    rclone fuse3 syncthing tailscale sshfs
    # containers
    podman podman-compose
    python3-pip
)

FLATPAKS=(
    org.signal.Signal
    com.calibre_ebook.calibre
)

NPM_GLOBALS=(vercel wrangler)
UV_TOOLS=(ruff)

# --------------------------------------------------------------------------

FAILED=()
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; FAILED+=("$*"); }
try()  { "$@" || warn "failed: $*"; }

if [[ $EUID -eq 0 ]]; then
    echo "Run as your normal user, not root (sudo is called where needed)." >&2
    exit 1
fi
if ! grep -q '^ID=fedora' /etc/os-release; then
    echo "This script is for Fedora." >&2
    exit 1
fi

FEDORA_VER=$(rpm -E %fedora)
sudo -v || exit 1
# keep sudo alive for the duration of the script
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ---------------------------------------------------------------- system --

step "Updating system"
try sudo dnf upgrade --refresh -y

step "Enabling RPM Fusion + codecs"
if ! rpm -q rpmfusion-free-release &>/dev/null; then
    try sudo dnf install -y \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
fi
try sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1
rpm -q ffmpeg &>/dev/null || try sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
try sudo dnf group install -y multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin

# Hardware video decode (big battery win for browsing / video)
if lspci -nn | grep -iE 'vga|3d|display' | grep -qi intel; then
    try sudo dnf install -y intel-media-driver
fi
if lspci -nn | grep -iE 'vga|3d|display' | grep -qiE 'amd|ati'; then
    try sudo dnf swap -y mesa-va-drivers mesa-va-drivers-freeworld --allowerasing
fi

step "Adding third-party repos (VS Code, Chrome, Tailscale, Claude Desktop)"
if [[ ! -f /etc/yum.repos.d/vscode.repo ]]; then
    try sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo >/dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
fi
if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
    sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null <<'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF
else
    try sudo dnf config-manager setopt google-chrome.enabled=1
fi
if [[ ! -f /etc/yum.repos.d/tailscale.repo ]]; then
    try sudo dnf config-manager addrepo --from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
fi
if [[ ! -f /etc/yum.repos.d/claude-desktop.repo ]]; then
    sudo tee /etc/yum.repos.d/claude-desktop.repo >/dev/null <<'EOF'
[claude-desktop]
name=Claude Desktop for Fedora/RHEL
baseurl=https://aaddrick.github.io/claude-desktop-debian/rpm/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://aaddrick.github.io/claude-desktop-debian/KEY.gpg
EOF
fi

step "Installing packages"
try sudo dnf install -y "${DNF_PACKAGES[@]}"

step "Flatpaks"
try flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
try flatpak install -y --noninteractive flathub "${FLATPAKS[@]}"

step "Services"
try sudo systemctl enable --now tailscaled

step "Firmware updates (fwupd)"
sudo fwupdmgr refresh --force &>/dev/null
sudo fwupdmgr update -y --no-reboot-check || echo "  (no firmware updates, or some need a reboot)"

# ------------------------------------------------------------------ user --

export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"

step "Rust (rustup)"
if ! command -v rustup &>/dev/null; then
    try bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path"
else
    try rustup update
fi

step "Node (nvm + LTS)"
export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    # PROFILE=/dev/null: .bashrc already loads nvm, don't let the installer append to it
    try bash -c 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash'
fi
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    try nvm install --lts
    try nvm alias default 'lts/*'
    try npm install -g "${NPM_GLOBALS[@]}"
fi

step "Python (uv)"
if ! command -v uv &>/dev/null; then
    try bash -c 'curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh'
else
    try uv self update
fi
for t in "${UV_TOOLS[@]}"; do try uv tool install --upgrade "$t"; done

step "eza (not packaged for Fedora 43; prebuilt binary to ~/.local/bin)"
if ! command -v eza &>/dev/null; then
    mkdir -p "$HOME/.local/bin"
    try bash -c 'curl -fsSL https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-gnu.tar.gz | tar -xz -C "$HOME/.local/bin"'
fi

step "Claude Code (native installer)"
if ! command -v claude &>/dev/null; then
    try bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
else
    try claude update
fi

step "Dotfiles (install.sh)"
try "$DOTFILES_DIR/install.sh"

step "VS Code extensions"
if command -v code &>/dev/null; then
    while IFS= read -r ext; do
        [[ -n "$ext" ]] && try code --install-extension "$ext" --force >/dev/null
    done < "$DOTFILES_DIR/vscode/extensions.txt"
fi

step "Claude Code plugins"
if command -v claude &>/dev/null; then
    try claude plugin marketplace add cloudflare/skills
    for p in $(jq -r '.enabledPlugins | keys[]' "$DOTFILES_DIR/claude/settings.json"); do
        try claude plugin install "$p"
    done
fi

step "Desktop (Cinnamon settings, autostart, defaults)"
if [[ "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* ]]; then
    try dconf load /org/cinnamon/ < "$DOTFILES_DIR/cinnamon/cinnamon.dconf"
fi
mkdir -p "$HOME/.config/autostart"
for app in kitty variety; do
    [[ -f /usr/share/applications/$app.desktop && ! -f $HOME/.config/autostart/$app.desktop ]] && \
        cp "/usr/share/applications/$app.desktop" "$HOME/.config/autostart/"
done
try xdg-settings set default-web-browser google-chrome.desktop

step "User services (dunst, syncthing, Google Drive mount)"
try systemctl --user enable --now dunst.service
try systemctl --user enable --now syncthing.service
mkdir -p "$HOME/.config/systemd/user"
cp "$DOTFILES_DIR/gdrive/rclone-gdrive.service" "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
GDRIVE_READY=0
if grep -q '^\[gdrive\]' "$HOME/.config/rclone/rclone.conf" 2>/dev/null; then
    try systemctl --user enable --now rclone-gdrive.service && GDRIVE_READY=1
fi

# ------------------------------------------------------------------ done --

step "Done"
if ((${#FAILED[@]})); then
    printf '\033[1;31mThese steps failed (re-run the script once fixed):\033[0m\n'
    printf '  - %s\n' "${FAILED[@]}"
fi

cat <<EOF

Remaining manual steps:
  1. Reboot (kernel/firmware/codec updates).
  2. git identity:     edit ~/.gitconfig.local  ([user] name/email)
  3. Tailscale:        sudo tailscale up --operator=\$USER
  4. Claude Code:      run 'claude' and log in (then re-run this script once
                       to install plugins if that step failed above)
EOF
if ((GDRIVE_READY == 0)); then
cat <<'EOF'
  5. Google Drive:     copy ~/.config/rclone/rclone.conf from the old machine
                       (scp/tailscale, chmod 600) OR run 'rclone config' and
                       add a 'drive' remote named 'gdrive'; then
                       systemctl --user enable --now rclone-gdrive
EOF
fi
cat <<'EOF'
  6. Syncthing:        open http://127.0.0.1:8384, add the phone + old laptop
                       as devices, share the "Obsidian Blog" folder
                       (path ~/projects/obsidian-blog)
  7. Sign in:          Chrome (restores extensions/bookmarks), VS Code
                       (GitHub, for Copilot/Settings if wanted), Signal, gh
                       is already done if you used it to clone
EOF
