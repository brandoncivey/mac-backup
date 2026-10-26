#!/usr/bin/env bash
#
# backup.sh — back up dotfiles and Mac configuration files.
#
# Usage:
#   ./backup.sh                  # back up to ./backups/<timestamp>
#   ./backup.sh -d /path/to/dir  # back up to a custom destination
#   ./backup.sh --include-secrets  # ALSO copy SSH keys, AWS creds, kube/gcloud tokens
#
# What it captures:
#   - Shell dotfiles (zsh, bash, profile) and oh-my-zsh custom dir
#   - Git, SSH (config only), AWS (config only), Docker, kubectl, npm configs
#   - Selected ~/.config tools: gh, git, fish, iterm2, tfenv, op, packer
#   - Homebrew Brewfile (everything installed via brew, casks, taps, MAS apps)
#   - VS Code user settings, keybindings, snippets + extension list
#   - iTerm2 preferences
#   - Key macOS defaults (dock, finder, keyboard, trackpad, global)
#   - A manifest of what was backed up
#
# Secrets (SSH private keys, ~/.aws/credentials, ~/.kube/config, gcloud creds,
# gh auth tokens, shell history) are EXCLUDED unless --include-secrets is given.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP="$(date +%Y-%m-%d_%H%M%S)"
DEST_ROOT="${SCRIPT_DIR}/backups"
INCLUDE_SECRETS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--dest) DEST_ROOT="$2"; shift 2 ;;
    --include-secrets) INCLUDE_SECRETS=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

DEST="${DEST_ROOT}/${TIMESTAMP}"
mkdir -p "$DEST"
MANIFEST="${DEST}/MANIFEST.txt"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

# Copy a file or directory (relative to $HOME) into the backup,
# preserving its relative path. Silently skips paths that don't exist.
copy_home() {
  local rel="$1"
  local src="${HOME}/${rel}"
  [[ -e "$src" ]] || return 0
  local dest_dir
  dest_dir="${DEST}/home/$(dirname "$rel")"
  mkdir -p "$dest_dir"
  if [[ -d "$src" ]]; then
    rsync -a "${EXCLUDE_ARGS[@]}" "$src" "$dest_dir/"
  else
    rsync -a "$src" "$dest_dir/"
  fi
  echo "~/${rel}" >> "$MANIFEST"
}

# rsync excludes applied to directory copies — keeps secrets and junk out.
EXCLUDE_ARGS=(
  --no-specials --no-devices   # skip sockets/devices (op-daemon.sock, iterm2 sockets)
  --exclude '.DS_Store'
  --exclude '*.sock' --exclude 'sockets/'
  --exclude 'cache/' --exclude 'Cache/' --exclude 'logs/'
)
if [[ $INCLUDE_SECRETS -eq 0 ]]; then
  EXCLUDE_ARGS+=(
    --exclude 'id_*'            # ssh private/public key pairs
    --exclude '*.pem' --exclude '*.key'
    --exclude 'credentials'     # ~/.aws/credentials
    --exclude 'hosts.yml'       # gh auth tokens
    --exclude 'legacy_credentials/' --exclude 'access_tokens.db'
    --exclude 'credentials.db'  # gcloud
  )
fi

echo "Mac backup created ${TIMESTAMP} on $(hostname) by $(whoami)" > "$MANIFEST"
echo "Secrets included: $([[ $INCLUDE_SECRETS -eq 1 ]] && echo yes || echo no)" >> "$MANIFEST"
echo "---" >> "$MANIFEST"

# ---------------------------------------------------------------------------
log "Shell dotfiles"
for f in .zshrc .zprofile .zshenv .zlogin .bashrc .bash_profile .profile \
         .aliases .exports .functions .inputrc .hushlogin; do
  copy_home "$f"
done
# oh-my-zsh: only the custom dir (themes/plugins/overrides) — the framework
# itself is reinstallable and huge.
copy_home ".oh-my-zsh/custom"
copy_home ".p10k.zsh"

# ---------------------------------------------------------------------------
log "Tool configs"
copy_home ".gitconfig"
copy_home ".gitignore_global"
copy_home ".gitattributes"
copy_home ".ssh/config"
copy_home ".ssh/known_hosts"
copy_home ".aws/config"
copy_home ".npmrc"
copy_home ".docker/config.json"
copy_home ".tmux.conf"
copy_home ".vimrc"
copy_home ".ideavimrc"
copy_home ".tool-versions"
copy_home ".gradle/gradle.properties"
copy_home ".m2/settings.xml"
copy_home ".claude/settings.json"
copy_home ".claude/CLAUDE.md"
copy_home ".claude/keybindings.json"
if [[ $INCLUDE_SECRETS -eq 1 ]]; then
  copy_home ".ssh"
  copy_home ".aws/credentials"
  copy_home ".kube/config"
  copy_home ".zsh_history"
fi

# Selected ~/.config subdirectories (skip caches and credential stores).
for cfg in gh git fish iterm2 op packer pagerduty-cli; do
  copy_home ".config/${cfg}"
done
# tfenv: the versions/ dir holds full terraform binaries — only the pinned
# version file is configuration.
copy_home ".config/tfenv/version"

# ---------------------------------------------------------------------------
if command -v brew >/dev/null 2>&1; then
  log "Homebrew Brewfile"
  mkdir -p "${DEST}/homebrew"
  brew bundle dump --file="${DEST}/homebrew/Brewfile" --force
  echo "homebrew/Brewfile" >> "$MANIFEST"
fi

# ---------------------------------------------------------------------------
VSCODE_USER="${HOME}/Library/Application Support/Code/User"
if [[ -d "$VSCODE_USER" ]]; then
  log "VS Code settings"
  mkdir -p "${DEST}/vscode"
  for f in settings.json keybindings.json; do
    [[ -f "${VSCODE_USER}/${f}" ]] && cp "${VSCODE_USER}/${f}" "${DEST}/vscode/"
  done
  [[ -d "${VSCODE_USER}/snippets" ]] && rsync -a "${VSCODE_USER}/snippets" "${DEST}/vscode/"
  if command -v code >/dev/null 2>&1; then
    code --list-extensions > "${DEST}/vscode/extensions.txt" 2>/dev/null || true
  fi
  echo "vscode/ (settings, keybindings, snippets, extensions.txt)" >> "$MANIFEST"
fi

# ---------------------------------------------------------------------------
log "App preferences (plists)"
mkdir -p "${DEST}/preferences"
for domain in \
    com.googlecode.iterm2 \
    com.apple.Terminal \
    com.apple.dock \
    com.apple.finder \
    com.apple.Safari.SandboxBroker \
    NSGlobalDomain \
    com.apple.AppleMultitouchTrackpad \
    com.apple.symbolichotkeys; do
  # `defaults export` writes a readable, re-importable plist.
  defaults export "$domain" "${DEST}/preferences/${domain}.plist" 2>/dev/null \
    && echo "preferences/${domain}.plist" >> "$MANIFEST" \
    || note "skipped ${domain} (no prefs found)"
done

# ---------------------------------------------------------------------------
log "System snapshot (for reference when restoring)"
mkdir -p "${DEST}/system"
{
  sw_vers
  echo
  echo "Hostname: $(hostname)"
  echo "Shell: $SHELL"
  xcode-select -p 2>/dev/null && echo "(Xcode CLT installed)"
} > "${DEST}/system/system-info.txt"
ls /Applications > "${DEST}/system/applications.txt"
npm ls -g --depth=0 > "${DEST}/system/npm-globals.txt" 2>/dev/null || true
echo "system/ (system-info, applications list, npm globals)" >> "$MANIFEST"

# ---------------------------------------------------------------------------
# Update the "latest" symlink and finish up.
ln -sfn "$DEST" "${DEST_ROOT}/latest"
COUNT=$(( $(wc -l < "$MANIFEST") - 3 ))
SIZE=$(du -sh "$DEST" | cut -f1)

log "Done: ${COUNT} items, ${SIZE} → ${DEST}"
if [[ $INCLUDE_SECRETS -eq 1 ]]; then
  printf '\033[1;33mWARNING:\033[0m backup contains secrets (SSH keys, credentials). Store it encrypted.\n'
else
  note "Secrets were excluded. Re-run with --include-secrets to capture SSH keys/credentials."
fi
