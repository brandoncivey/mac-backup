# mac-backup

`backup.sh` copies dotfiles and Mac configuration into a timestamped directory under `backups/`. This README covers how to **restore** from one of those backups. For how the backup works, see the header of `backup.sh` and `CLAUDE.md`.

## Backup layout

```
backups/
  latest -> 2026-10-21_093636        # symlink to the newest run
  2026-10-21_093636/
    MANIFEST.txt                     # what was captured, and whether secrets are included
    home/                            # files relative to $HOME (e.g. home/.zshrc, home/.config/gh/)
    homebrew/Brewfile
    vscode/                          # settings.json, keybindings.json, snippets/, extensions.txt
    preferences/*.plist              # macOS `defaults export` files
    system/                          # system-info.txt, applications.txt, npm-globals.txt (reference only)
```

Check `MANIFEST.txt` first. Its second line says `Secrets included: yes|no`. A backup made with `--include-secrets` contains SSH private keys and cloud credentials, so keep it encrypted and never commit it.

## Before you start

Set the backup to restore from (adjust the path if you used `-d`):

```sh
export BK=~/devel/mac-backup/backups/latest
cat "$BK/MANIFEST.txt"
```

On a fresh Mac, first install the Xcode Command Line Tools and Homebrew:

```sh
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

## 1. Restore dotfiles and `~/.config`

Everything under `home/` mirrors the layout of `$HOME`. Preview first with a dry run, then restore:

```sh
rsync -avn "$BK/home/" ~/      # dry run: shows what would change
rsync -av  --backup --suffix=".pre-restore" "$BK/home/" ~/
```

`--backup --suffix` keeps any file that would be overwritten as `<name>.pre-restore`. To restore a single file or directory:

```sh
rsync -av "$BK/home/.zshrc" ~/
rsync -av "$BK/home/.config/gh/" ~/.config/gh/
```

Notes:
- **oh-my-zsh**: only `~/.oh-my-zsh/custom` is backed up. Install the framework first, then restore, or the installer may clobber `custom`:
  ```sh
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
  rsync -av "$BK/home/.oh-my-zsh/custom/" ~/.oh-my-zsh/custom/
  ```
- **tfenv**: only `~/.config/tfenv/version` is saved. After installing tfenv, run `tfenv install` to fetch the pinned version.
- **gh**: `hosts.yml` (auth tokens) is not backed up by default. Run `gh auth login` after restoring.
- **gcloud, 1Password (`op`)**: credentials are not backed up by default. Sign in again.

## 2. Restore secrets (only if the backup has them)

Applies only when `MANIFEST.txt` says `Secrets included: yes`. The `rsync` in step 1 already copies `.ssh/`, `.aws/credentials`, `.kube/config` and `.zsh_history`. Then fix permissions, since SSH refuses keys that are too open:

```sh
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_* ~/.ssh/config 2>/dev/null
chmod 644 ~/.ssh/*.pub ~/.ssh/known_hosts 2>/dev/null
chmod 600 ~/.aws/credentials ~/.kube/config 2>/dev/null
```

If the backup excluded secrets, regenerate or re-download SSH keys, run `aws configure` / `aws sso login`, and re-fetch kube config.

## 3. Restore Homebrew packages

```sh
brew bundle --file="$BK/homebrew/Brewfile"
```

Add `--no-upgrade` to avoid upgrading packages that are already installed. Mac App Store entries (`mas`) need you to be signed in to the App Store.

## 4. Restore VS Code

Quit VS Code first.

```sh
VSC=~/Library/Application\ Support/Code/User
mkdir -p "$VSC"
cp "$BK/vscode/settings.json" "$BK/vscode/keybindings.json" "$VSC/"
rsync -av "$BK/vscode/snippets/" "$VSC/snippets/"
xargs -n1 code --install-extension < "$BK/vscode/extensions.txt"
```

## 5. Restore macOS preferences and iTerm2

Quit the affected apps (iTerm2, Terminal, Finder) first. `defaults import` replaces the whole domain.

```sh
for p in "$BK"/preferences/*.plist; do
  domain="$(basename "$p" .plist)"
  defaults import "$domain" "$p"
done
killall Dock Finder SystemUIServer cfprefsd 2>/dev/null
```

To restore one domain only (for example iTerm2):

```sh
defaults import com.googlecode.iterm2 "$BK/preferences/com.googlecode.iterm2.plist"
```

Some changes (keyboard shortcuts in `com.apple.symbolichotkeys`, trackpad, `NSGlobalDomain`) need a **logout/login or reboot** to take effect. Restoring `NSGlobalDomain` across macOS versions can bring over stale settings, so import it selectively if the new Mac runs a different major version (compare with `system/system-info.txt`).

## 6. Reinstall other tools (reference files)

`system/` is informational and is not restored automatically:

- `system/applications.txt`: apps that were in `/Applications`. Install any that aren't covered by the Brewfile.
- `system/npm-globals.txt`: reinstall with `npm install -g <package>`.
- `system/system-info.txt`: the macOS version and shell of the original machine.

## Verify

```sh
zsh -ic 'echo shell ok'        # new shell loads without errors
git config --list --show-origin | head
ssh -T git@github.com          # if SSH keys were restored
brew bundle check --file="$BK/homebrew/Brewfile"
```

Open a new terminal window after restoring so the shell and iTerm2 settings are reloaded.
