# macOS setup & Linux → Mac field guide

## Setup

```bash
# 1. Command Line Tools: gives you git, needed to clone (a dialog pops up; wait for it)
xcode-select --install

# 2. Clone over HTTPS (it's public), then bootstrap
mkdir -p ~/projects && git clone https://github.com/eamon-b/dotfiles.git ~/projects/dotfiles
~/projects/dotfiles/macos/bootstrap.sh
```

`bootstrap.sh` installs Homebrew, the [Brewfile](Brewfile), Homebrew bash as
your login shell, rustup / nvm / uv / Claude Code, runs `install.sh`, the VS
Code extensions, Claude plugins, and a few `defaults` (key repeat, Finder,
screenshots). It needs your account to be an **admin**. On a managed work Mac,
check that first.

After that, `./install.sh` works the same as on Linux. It detects macOS and:

| Linux | macOS |
|---|---|
| `~/.config/Code/User/settings.json` | `~/Library/Application Support/Code/User/settings.json` |
| systemd `claude-hooks.service` | launchd agent `~/Library/LaunchAgents/com.dotfiles.claude-hooks.plist`, logs in `~/Library/Logs/claude-hooks.log` |
| `credential.helper = libsecret` | `osxkeychain` |
| `kitty.conf` | same, plus [`macos/kitty.conf`](kitty.conf) appended (font, Option-as-Alt, socket path) |
| terminator, dunst | skipped (macOS has its own notification centre) |
| — | `~/.bash_profile` that sources `~/.bashrc` (see "Shell" below) |

`claude-hooks start|stop|restart|status|logs|dashboard` works on both.

Not ported, on purpose, because this is a work machine: Signal, calibre,
syncthing, rclone/Google Drive, tailscale, variety, Cinnamon settings.

---

## What's different, and what to know

### 1. The keyboard: Cmd vs Ctrl

The biggest adjustment. **Cmd (⌘) does what Ctrl does on Linux for GUI
shortcuts**, which leaves Ctrl free for the terminal:

| Action | Linux | Mac |
|---|---|---|
| Copy / paste in apps | Ctrl+C / V | ⌘C / ⌘V |
| Copy / paste **in the terminal** | Ctrl+Shift+C / V | ⌘C / ⌘V (Ctrl+C is still SIGINT) |
| App launcher | Super | ⌘Space (Spotlight) |
| Switch apps | Alt+Tab | ⌘Tab (apps, not windows) |
| Switch windows of the same app | — | ⌘\` |
| Close window / quit app | Ctrl+W / Alt+F4 | ⌘W / **⌘Q**. Closing the last window usually leaves the app running |
| Hide app | — | ⌘H (use it instead of minimise) |
| Start / end of line (text fields) | Home / End | ⌘← / ⌘→ |
| Word left / right | Ctrl+← / → | ⌥← / ⌥→ (Option) |
| Delete forward | Delete | Fn+Delete (the "delete" key is backspace) |
| Home / End / PgUp / PgDn | keys | Fn+← / → / ↑ / ↓ |
| Screenshot (flameshot) | — | ⌘⇧4 (region), ⌘⇧5 (menu + recording) |
| Force-quit | xkill | ⌘⌥Esc |
| Emoji | — | Fn / 🌐 (Globe key) |

Gotchas:
- **Ctrl+← / → switch Spaces (virtual desktops)** by default, so the
  `.inputrc` Ctrl+arrow word jumps won't reach the terminal. Use ⌥← / ⌥→, or
  turn off the shortcut in System Settings → Keyboard → Keyboard Shortcuts →
  Mission Control.
- **Option is not Alt** in most apps: it types special characters (⌥e → ´).
  The kitty config sets `macos_option_as_alt yes`, so your Alt bindings
  (Alt+arrows between splits, readline's Alt+.) work in kitty. In Terminal.app,
  turn on Settings → Profiles → Keyboard → "Use Option as Meta key".
- Your kitty `ctrl+shift+…` bindings still work. kitty also has the Mac
  defaults (⌘T new tab, ⌘D split, ⌘1-9 tabs).

### 2. Windows and desktops

- No window snapping like Cinnamon unless you use the built-in tiling
  (macOS 15+): drag a window to a screen edge, or **Fn+Ctrl+arrows**. Want
  more control? `brew install --cask rectangle`.
- The green button makes the window full-screen in its own Space. Option-click
  it (or double-click the title bar) to just maximise.
- Mission Control: three-finger swipe up, or Ctrl+↑. Spaces are virtual desktops.
- The menu bar belongs to whichever app is focused, not to the window.
- Clipboard history (parcellite): newer macOS has it in Spotlight (⌘Space,
  then the clipboard section); otherwise `brew install --cask maccy`.

### 3. Shell

- **The default shell is zsh**, and `/bin/bash` is bash **3.2** from 2007
  (kept because of licensing). Bootstrap installs bash 5 from Homebrew and
  makes it your login shell, so your `.bashrc` works unchanged. Check with
  `echo $BASH_VERSION`. Scripts with `#!/bin/bash` still get 3.2, so use
  `#!/usr/bin/env bash` (the repo's scripts now do).
- **Terminals start login shells**, which read `~/.bash_profile`, not
  `~/.bashrc`. The installed `~/.bash_profile` just sources `~/.bashrc`.
- Machine-specific things go in `~/.bashrc.local`, same as on Linux (for
  example the work proxy, `alias docker=…`, or work env vars).

### 4. BSD userland: same commands, different flags

macOS's `sed`, `date`, `stat`, `find`, `xargs`, `grep` and `ls` are the BSD
versions. The ones that bite most often:

| GNU (Linux) | BSD (macOS) |
|---|---|
| `sed -i 's/a/b/' f` | `sed -i '' 's/a/b/' f` (the backup-suffix argument is required) |
| `date -d '1 day ago'` | `date -v-1d` |
| `stat -c %s f` | `stat -f %z f` |
| `grep -P` | not supported. Use `rg` |
| `ls --color` | `ls -G` (you mostly use `eza` anyway) |
| `xargs -r` | default behaviour, no flag needed |
| `free`, `ss`, `ip addr`, `lsblk` | `vm_stat` / `top`, `lsof -i :8080`, `ifconfig`, `diskutil list` |

The Brewfile installs the GNU versions with a `g` prefix (`gsed`, `gdate`,
`gstat`, `gfind`). Use those when you need GNU behaviour; don't alias them
over the BSD ones, because macOS's own scripts expect BSD.

### 5. The filesystem is case-insensitive

APFS defaults to **case-insensitive, case-preserving**, so `README.md` and
`readme.md` are the same file. Consequences:
- Renaming only the case: `git mv Foo.ts foo.ts`, since a plain `mv` won't
  register with git.
- A Linux repo containing both `Makefile` and `makefile` will check out wrong.
- Imports with the wrong case work locally and fail in Linux CI.

### 6. Where things live

| Linux | macOS |
|---|---|
| `/home/you` | `/Users/you` |
| `~/.config/<app>` | often `~/Library/Application Support/<app>` (CLI tools still use `~/.config`) |
| `~/.cache` | `~/Library/Caches` |
| `/var/log`, `journalctl` | `~/Library/Logs`, Console.app, `log show --last 10m` |
| `/usr/share/applications/*.desktop` | `/Applications/*.app` (bundles are just folders) |
| `/usr/bin` (dnf) | `/opt/homebrew/bin` (Apple Silicon) or `/usr/local/bin` (Intel) |
| `/tmp` | `/tmp` → `/private/tmp`; also a per-user `$TMPDIR` |

`~/Library` is hidden in Finder: ⌘⇧. toggles hidden files (bootstrap turns
them on), and ⌘⇧G is "go to path".

### 7. Packages: Homebrew instead of dnf

| dnf | brew |
|---|---|
| `sudo dnf install x` | `brew install x` (**no sudo**, never use sudo with brew) |
| GUI app (repo / flatpak) | `brew install --cask x` |
| `dnf upgrade` | `brew update && brew upgrade` |
| `dnf search` / `info` | `brew search` / `brew info` |
| `dnf list installed` | `brew list`, `brew leaves` (what you asked for) |
| `dnf autoremove` | `brew autoremove && brew cleanup` |

- After `brew install`ing something you want to keep, add it to `macos/Brewfile`
  (or `brew bundle dump --file=- | less` to see everything).
- **macOS itself** updates through System Settings → General → Software Update
  (or `softwareupdate -l`). brew never touches the OS, and on a work Mac IT
  probably forces these updates.

### 8. Services: launchd instead of systemd

| systemd | launchd |
|---|---|
| `~/.config/systemd/user/x.service` | `~/Library/LaunchAgents/x.plist` (XML) |
| `systemctl --user start x` | `launchctl kickstart gui/$(id -u)/x` |
| `systemctl --user enable --now x` | `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/x.plist` |
| `systemctl --user stop/disable x` | `launchctl bootout gui/$(id -u)/x` |
| `systemctl --user status x` | `launchctl print gui/$(id -u)/x` |
| `journalctl -u x` | whatever `StandardOutPath` in the plist says |
| `systemctl --user list-units` | `launchctl list` |

For brew-installed daemons (postgres, redis) there's the much nicer
`brew services start|stop|list postgresql`.

### 9. Handy Mac-only commands

- `pbcopy` / `pbpaste`: clipboard (`yank` in `.bashrc` uses it)
- `open .` (Finder here), `open file.pdf`, `open -a "Visual Studio Code" .`, `open https://…`
- `caffeinate -i long-command`: keep the machine awake while it runs
- `mdfind name`: Spotlight from the CLI (like `locate`)
- `defaults read/write`: the settings database that bootstrap edits
- `security find-generic-password -s name -w`: read a Keychain secret in scripts
- `say done`: speaks out loud (`long-build; say done`)
- `qlmanage -p file`: Quick Look (in Finder, just press Space)

### 10. Security prompts

- **Gatekeeper**: a downloaded app may be "from an unidentified developer".
  Approve it in System Settings → Privacy & Security → "Open Anyway". For a
  downloaded CLI binary: `xattr -d com.apple.quarantine ./binary`.
- **Privacy prompts (TCC)**: the first time kitty or VS Code touches
  Documents / Desktop / Downloads, macOS asks. If a tool fails with "Operation
  not permitted" on your own files, grant the terminal Full Disk Access in
  Privacy & Security, if work policy allows it.
- **SIP**: `/System` and `/usr` (except `/usr/local`) are read-only even for
  root. You never need to change them.
- Credentials go in the **Keychain** (Keychain Access.app), which plays the
  role of gnome-keyring / seahorse. git and gh already use it.

### 11. Apple Silicon and containers

- The Mac is **arm64**. Most things are native; x86 macOS binaries run through
  Rosetta 2 (`softwareupdate --install-rosetta` if prompted).
- **Containers need a Linux VM.** Podman: `podman machine init && podman
  machine start` once, then use it as normal. Images are `linux/arm64` by
  default. Pulling or building `--platform linux/amd64` works but is emulated
  and slow, and sometimes it's the only option for older images.
- **Docker Desktop needs a paid licence at companies with >250 employees or
  >$10M revenue.** Check what work uses (Docker Desktop, Podman, OrbStack,
  Colima, Rancher) before picking. If it's real Docker, add `unalias docker`
  to `~/.bashrc.local` to undo the `.bashrc` alias `docker='podman'`.

### 12. Because it's a work machine

- **MDM** (Jamf, Kandji, Intune…) may block some settings, push its own apps,
  run a VPN or proxy, and lets IT see the machine. Keep personal stuff off it.
  If `brew` or `curl` fail with TLS errors, the corporate proxy probably
  intercepts TLS. Ask IT for the CA bundle and point
  `SSL_CERT_FILE` / `NODE_EXTRA_CA_CERTS` / `REQUESTS_CA_BUNDLE` at it in
  `~/.bashrc.local`.
- **Git identity / GitHub accounts**: see section 13.
- **Claude Code**: the company may ship managed settings
  (`/Library/Application Support/ClaudeCode/managed-settings.json`) that
  override your `~/.claude/settings.json`: permissions, allowed models,
  plugin marketplaces, hooks. Run `/status` inside `claude` to see which
  settings sources are active. Your `autoMode.environment` block says "None
  configured" for org, domains and buckets. On a work machine, Claude's auto
  mode will be more useful (and safer) if those describe the real org; ask
  whether work already provides one.
- The hooks server logs every prompt and tool call to
  `~/.claude/hooks-server.db`. It stays local to the machine, but you should
  know it's there if work has data-retention rules.

### 13. Two GitHub accounts on one machine (work + personal)

The rule: **the folder decides the account.** Everything under `~/work/` is
work, and everything under `~/projects/` is personal (dotfiles already lives
there). Git config switches the commit email *and* the SSH key by folder. That
applies to every git client: terminal, VS Code, and Claude Code. It also
applies while `git clone` runs, so a fresh clone into `~/work/` already uses
the work key.

**1. One SSH key per account**

```bash
ssh-keygen -t ed25519 -C "personal" -f ~/.ssh/id_ed25519_personal
ssh-keygen -t ed25519 -C "work"     -f ~/.ssh/id_ed25519_work
```

Add each `.pub` to its own GitHub account (Settings → SSH and GPG keys). If
the work org uses SAML SSO, also click "Configure SSO" → Authorize next to the
work key. To store the passphrases in the Keychain, create `~/.ssh/config`:

```
Host *
    AddKeysToAgent yes
    UseKeychain yes
```

Don't add a `Host github.com` / `IdentityFile` default. With no default,
anything outside the two folders fails instead of quietly using one of the keys.

**2. Pick the identity by folder.** In `~/.gitconfig.local`, leave out any
top-level `[user]` block and add:

```ini
[user]
    useConfigOnly = true      # outside ~/work and ~/projects: refuse to commit, don't guess
[includeIf "gitdir:~/projects/"]
    path = ~/.gitconfig.personal
[includeIf "gitdir:~/work/"]
    path = ~/.gitconfig.work
```

`~/.gitconfig.work` (and the same shape for `~/.gitconfig.personal`):

```ini
[user]
    name = Your Name
    email = you@company.com
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes
```

The trailing `/` on the `gitdir:` paths matters. Use **SSH remote URLs**
(`git@github.com:org/repo.git`), not HTTPS: the Keychain stores one HTTPS
login per host, so two accounts on github.com would collide. Run
`gh config set git_protocol ssh` so `gh repo clone` uses SSH too.

**3. gh CLI.** gh can hold both accounts: run `gh auth login` once per
account, choose SSH, and say **no** to "authenticate Git with your GitHub
credentials" (git already authenticates with the SSH keys). Then in
`~/.bashrc.local`:

```bash
export GH_PERSONAL_USER=your-personal-login
export GH_WORK_USER=your-work-login
# export GH_WORK_DIR=~/work   # default
```

`.bashrc` then wraps `gh` so it uses the account that matches the folder,
and refuses if that account isn't logged in.

**4. Check it before your first push**

```bash
cd ~/work/some-repo
git config user.email                 # work email
git config core.sshCommand            # work key
ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes -T git@github.com   # "Hi <work-login>!"
gh api user -q .login                 # work login
```

Run the same in a `~/projects/` repo and expect the personal values. To check
Claude Code, ask it to run `gh api user -q .login` in each folder. The git
side is plain git config, so it can't drift, but the `gh` wrapper only
applies if Claude Code picks up your `.bashrc` functions.

**Other places accounts can mix**
- **Browser**: use a separate Chrome profile per GitHub account.
- **VS Code**: its GitHub sign-in (Copilot, the PR extension) is one account
  at a time. This doesn't affect git, which uses the SSH keys.
- **Claude Code**: one login per config directory. If work gives you an
  account, use it for work code. A second login needs `CLAUDE_CONFIG_DIR`
  pointed somewhere else, which the dotfiles don't set up.
- **Policy**: read the employment agreement and IT policy about personal
  projects on company hardware. Some companies forbid it, or claim what you
  build on their equipment. The device is also visible to IT through MDM.

### 14. Keeping both machines in sync

The repo is the source of truth for both. When you change something on the
Mac, check it doesn't break Linux: guard Mac-only bits with
`((IS_MAC))` in `.bashrc` (or `[[ "$(uname -s)" == Darwin ]]` in scripts),
and put Mac-only files in `macos/`.
