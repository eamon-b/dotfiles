# ~/.bashrc - Bash configuration file

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# ==============================================================================
# History Configuration
# ==============================================================================

HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups
HISTTIMEFORMAT="%Y-%m-%d %H:%M:%S  "
shopt -s histappend

# ==============================================================================
# Persistent Command Log (with datetime and directory)
# ==============================================================================

COMMAND_LOG="$HOME/.command_history.log"

# Log every command with timestamp and working directory
log_command() {
    local cmd
    cmd=$(history 1 | sed 's/^ *[0-9]* *//')
    if [[ -n "$cmd" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$(pwd)] $cmd" >> "$COMMAND_LOG"
    fi
}

PROMPT_COMMAND="log_command${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

# Search through persistent history log
hgrep() {
    if [[ -z "$1" ]]; then
        echo "Usage: hgrep <pattern>"
        echo "Search through persistent command history log"
        return 1
    fi
    grep --color=auto -i "$@" "$COMMAND_LOG"
}

# ==============================================================================
# PS1 Prompt (full path with colors)
# ==============================================================================

# Colors
RED='\[\033[0;31m\]'
GREEN='\[\033[0;32m\]'
YELLOW='\[\033[0;33m\]'
BLUE='\[\033[0;34m\]'
PURPLE='\[\033[0;35m\]'
CYAN='\[\033[0;36m\]'
WHITE='\[\033[0;37m\]'
BOLD='\[\033[1m\]'
RESET='\[\033[0m\]'

# Git branch in prompt (if in a git repo) with dirty state indicator
git_prompt() {
    local branch
    branch=$(git branch 2>/dev/null | grep '^*' | sed 's/* //')
    if [[ -n "$branch" ]]; then
        local dirty=""
        git diff --quiet 2>/dev/null || dirty="*"
        git diff --cached --quiet 2>/dev/null || dirty="${dirty}+"
        echo " ($branch$dirty)"
    fi
}

# Prompt: user@host:full/path (git-branch)$
PS1="${GREEN}\u${RESET}@${CYAN}\h${RESET}:${YELLOW}\w${RESET}${PURPLE}\$(git_prompt)${RESET}\$ "

# ==============================================================================
# Terminal Title (shows running command for notification click-to-focus)
# ==============================================================================

# Set terminal title
set_title() {
    printf '\033]0;%s\007' "$*"
}

# Show running command in terminal title (via DEBUG trap)
# This runs before each command executes
show_command_in_title() {
    # Skip if this is the PROMPT_COMMAND execution
    [[ "$BASH_COMMAND" == "$PROMPT_COMMAND" ]] && return
    # Skip internal commands
    [[ "$BASH_COMMAND" == "log_command"* ]] && return
    [[ "$BASH_COMMAND" == "set_title"* ]] && return
    # Set title to the running command
    set_title "$BASH_COMMAND"
}

# Reset title to directory when at prompt
reset_title_to_dir() {
    set_title "${PWD/#$HOME/~}"
}

# Enable command-in-title feature
trap 'show_command_in_title' DEBUG
PROMPT_COMMAND="reset_title_to_dir; ${PROMPT_COMMAND}"

# ==============================================================================
# Shell Options
# ==============================================================================

shopt -s checkwinsize   # Update window size after each command
shopt -s cdspell        # Autocorrect minor cd typos
shopt -s dirspell       # Autocorrect directory spelling during completion
shopt -s globstar       # Enable ** for recursive globbing
shopt -s nocaseglob     # Case-insensitive globbing

# ==============================================================================
# ls Aliases
# ==============================================================================

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias lt='ls -alFt'          # Sort by time
alias lS='ls -alFS'          # Sort by size

# ==============================================================================
# General Aliases
# ==============================================================================

# Safety nets
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'

# Grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Disk usage
alias df='df -h'
alias du='du -h'
alias dud='du -d 1 -h'       # Disk usage for current directory children

# Misc
alias c='clear'
alias h='history'
alias j='jobs -l'
alias now='date +"%Y-%m-%d %H:%M:%S"'
alias path='echo -e ${PATH//:/\\n}'
alias mkdir='mkdir -pv'
alias wget='wget -c'         # Resume downloads by default

# ==============================================================================
# Git Aliases
# ==============================================================================

alias g='git'
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gpl='git pull'
alias gd='git diff'
alias gds='git diff --staged'
alias gl='git log --oneline --graph --decorate -20'
alias gla='git log --oneline --graph --decorate --all'
alias gco='git checkout'
alias gb='git branch'
alias gst='git stash'
alias gstp='git stash pop'

# ==============================================================================
# Podman Aliases
# ==============================================================================

alias docker='podman'
alias p='podman'
alias pps='podman ps'
alias ppsa='podman ps -a'
alias pimg='podman images'
alias prun='podman run -it --rm'
alias pexec='podman exec -it'
alias plogs='podman logs -f'
alias pstop='podman stop'
alias prm='podman rm'
alias prmi='podman rmi'
alias ppull='podman pull'
alias pbuild='podman build'
alias pprune='podman system prune -af'
alias pvolume='podman volume'
alias pnetwork='podman network'

# Podman compose (if using podman-compose)
alias pcompose='podman-compose'
alias pup='podman-compose up -d'
alias pdown='podman-compose down'
alias prestart='podman-compose restart'

# ==============================================================================
# Python Development
# ==============================================================================

export PYTHONDONTWRITEBYTECODE=1  # No .pyc files
export PYTHONUNBUFFERED=1         # Unbuffered output

alias py='python3'
alias pip='python3 -m pip'
alias venv='python3 -m venv'
alias activate='source venv/bin/activate'

# Quick venv creation and activation
mkvenv() {
    python3 -m venv "${1:-venv}" && source "${1:-venv}/bin/activate"
}

# pyenv (if installed)
if [[ -d "$HOME/.pyenv" ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
fi

# ==============================================================================
# Node/JavaScript Development
# ==============================================================================

# nvm (Node Version Manager)
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && . "$NVM_DIR/nvm.sh"
[[ -s "$NVM_DIR/bash_completion" ]] && . "$NVM_DIR/bash_completion"

alias nr='npm run'
alias ni='npm install'
alias nid='npm install --save-dev'
alias nig='npm install -g'
alias nup='npm update'
alias nout='npm outdated'

# ==============================================================================
# C Development
# ==============================================================================

export CC=gcc
export CFLAGS="-Wall -Wextra -Wpedantic -std=c11"
export LDFLAGS=""

alias gccw='gcc -Wall -Wextra -Wpedantic -g'
alias gccr='gcc -Wall -Wextra -Wpedantic -O2'
alias valgrind='valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes'
alias makec='make clean && make'

# ==============================================================================
# Utility Functions
# ==============================================================================

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract various archive formats
extract() {
    if [[ -f "$1" ]]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.tar.xz)    tar xJf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *.zst)       unzstd "$1"      ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Check permissions along a path (shows full chain from root)
perm() {
    namei -l "$(realpath "${1:-.}")"
}

# Quick find file
ff() {
    find . -type f -iname "*$1*"
}

# Quick find directory (renamed from fd to avoid conflict with fd-find)
fdir() {
    find . -type d -iname "*$1*"
}

# Serve current directory over HTTP
serve() {
    local port="${1:-8000}"
    echo "Serving on http://localhost:$port"
    python3 -m http.server "$port"
}

# Quick backup of a file
backup() {
    cp "$1" "$1.bak.$(date +%Y%m%d_%H%M%S)"
}

# ==============================================================================
# Modern CLI Tools (if installed)
# ==============================================================================

# fzf - fuzzy finder
if command -v fzf &>/dev/null; then
    eval "$(fzf --bash 2>/dev/null)" || source /usr/share/fzf/shell/key-bindings.bash 2>/dev/null
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
    export FZF_CTRL_R_OPTS='--sort --exact'
fi

# bat as cat replacement
if command -v bat &>/dev/null; then
    alias cat='bat --paging=never'
    alias catp='bat'
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
fi

# eza as ls replacement
if command -v eza &>/dev/null; then
    alias ls='eza --color=auto --group-directories-first'
    alias ll='eza -la --group-directories-first --git'
    alias lt='eza -la --sort=modified'
    alias tree='eza --tree'
fi

# ripgrep
if command -v rg &>/dev/null; then
    alias rg='rg --smart-case'
fi

# zoxide for smart cd
if command -v zoxide &>/dev/null; then
    eval "$(zoxide init bash)"
fi

# fd-find (Fedora package name is fd-find, binary is 'fd')
if command -v fd &>/dev/null; then
    # fd is already available, no alias needed
    # Use: fd <pattern> to find files
    :
fi

# ==============================================================================
# Environment Variables
# ==============================================================================

export EDITOR=vim
export VISUAL=vim
export PAGER=less
export LESS='-R'

# Colored man pages
export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# XDG Base Directory (some apps respect these)
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# ==============================================================================
# PATH additions
# ==============================================================================

# Add local bin directories to PATH (if they exist)
[[ -d "$HOME/.local/bin" ]] && export PATH="$HOME/.local/bin:$PATH"
[[ -d "$HOME/bin" ]] && export PATH="$HOME/bin:$PATH"

# Cargo (Rust)
[[ -f "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Go
if [[ -d "$HOME/go" ]]; then
    export GOPATH="$HOME/go"
    export PATH="$GOPATH/bin:$PATH"
fi

# ==============================================================================
# Bash Completion
# ==============================================================================

if [[ -f /etc/bash_completion ]]; then
    . /etc/bash_completion
elif [[ -f /usr/share/bash-completion/bash_completion ]]; then
    . /usr/share/bash-completion/bash_completion
fi

# ==============================================================================
# Local Configuration (load if exists)
# ==============================================================================

if [[ -f ~/.bashrc.local ]]; then
    . ~/.bashrc.local
fi

. "$HOME/.local/share/../bin/env"
