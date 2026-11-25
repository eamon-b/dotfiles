#!/bin/bash
# macos/bootstrap.sh
#
# One-shot setup for a fresh Mac: Homebrew (+ Xcode Command Line Tools),
# the Brewfile, Homebrew bash as login shell, user toolchains (rustup, nvm,
# uv, Claude Code), then ../install.sh for the dotfiles, VS Code extensions,
# Claude plugins, and some macOS defaults. The macOS counterpart of
# fedora/bootstrap.sh.
#
# Runs under the stock /bin/bash 3.2 (Homebrew's bash doesn't exist yet), so
# no associative arrays or other bash-4 syntax in here.
#
# Idempotent: safe to re-run. Failures are listed at the end.
#
#   ~/projects/dotfiles/macos/bootstrap.sh

set -o pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NPM_GLOBALS=(vercel wrangler)
UV_TOOLS=(ruff)

# --------------------------------------------------------------------------

FAILED=()
step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; FAILED+=("$*"); }
try()  { "$@" || warn "failed: $*"; }

if [[ "$(uname -s)" != Darwin ]]; then
    echo "This script is for macOS (use fedora/bootstrap.sh on Fedora)." >&2
    exit 1
fi
if [[ $EUID -eq 0 ]]; then
    echo "Run as your normal user, not root (sudo is called where needed)." >&2
    exit 1
fi
if ! id -Gn | tr ' ' '\n' | grep -qx admin; then
    cat >&2 <<'EOF'
Your account is not an admin on this Mac. Homebrew needs admin rights to
create /opt/homebrew. On a managed work Mac, ask IT for admin (or for your
company's self-service "make me admin" tool), then re-run this script.
EOF
    exit 1
fi

if [[ "$(uname -m)" == arm64 ]]; then BREW_PREFIX=/opt/homebrew; else BREW_PREFIX=/usr/local; fi

sudo -v || exit 1
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

# ------------------------------------------------------------ homebrew --

step "Homebrew (also installs Xcode Command Line Tools)"
if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
    try env NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if [[ ! -x "$BREW_PREFIX/bin/brew" ]]; then
    echo "Homebrew install failed; can't continue." >&2
    exit 1
fi
eval "$("$BREW_PREFIX/bin/brew" shellenv)"
export HOMEBREW_NO_ANALYTICS=1
try brew update

step "Brewfile packages and apps"
try brew bundle --file="$DOTFILES_DIR/macos/Brewfile"

step "Homebrew bash as login shell"
BREW_BASH="$BREW_PREFIX/bin/bash"
if [[ -x "$BREW_BASH" ]]; then
    grep -qx "$BREW_BASH" /etc/shells || echo "$BREW_BASH" | sudo tee -a /etc/shells >/dev/null
    CURRENT_SHELL="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
    if [[ "$CURRENT_SHELL" != "$BREW_BASH" ]]; then
        # May fail for directory (AD/LDAP) accounts on managed Macs; then set
        # it per-terminal instead (kitty: `shell` in kitty.conf).
        try sudo chsh -s "$BREW_BASH" "$USER"
    fi
fi

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

step "Claude Code (native installer)"
if ! command -v claude &>/dev/null; then
    try bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
else
    try claude update
fi

step "Dotfiles (install.sh)"
# install.sh needs bash 4+; run it with Homebrew's bash explicitly
try "$BREW_BASH" "$DOTFILES_DIR/install.sh"

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

step "macOS defaults"
# Key repeat instead of the accent popup when holding a key (vim, VS Code)
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
# No smart quotes/dashes/autocorrect mangling code pasted into text fields
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
# Finder: show extensions, dotfiles, path bar, list view; search current folder
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder ShowStatusBar -bool true
defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
defaults write com.apple.finder FXDefaultSearchScope -string SCcf
# No .DS_Store files on network shares / USB drives
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
# Screenshots to a folder instead of the Desktop
mkdir -p "$HOME/Pictures/Screenshots"
defaults write com.apple.screencapture location -string "$HOME/Pictures/Screenshots"
killall Finder SystemUIServer 2>/dev/null || true

mkdir -p "$HOME/projects"

# ------------------------------------------------------------------ done --

step "Done"
if ((${#FAILED[@]})); then
    printf '\033[1;31mThese steps failed (re-run the script once fixed):\033[0m\n'
    printf '  - %s\n' "${FAILED[@]}"
fi

cat <<'EOF'

Remaining manual steps:
  1. Log out and back in (login shell + key repeat settings take effect).
  2. git identity:   edit ~/.gitconfig.local ([user] name + WORK email)
  3. Claude Code:    run 'claude' and log in (re-run this script afterwards
                     if the plugin step failed)
  4. Permissions:    System Settings > Notifications > allow kitty and
                     terminal-notifier; Privacy & Security may also ask about
                     kitty accessing folders the first time.
  5. Containers:     podman machine init && podman machine start
                     (or whatever work uses instead; see macos/README.md)
  6. Sign in:        Chrome, VS Code, gh (gh auth login, if not done)

Read macos/README.md for the Linux -> macOS differences.
EOF
