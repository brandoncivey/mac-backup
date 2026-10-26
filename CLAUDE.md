# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single-script project: `backup.sh` backs up the user's dotfiles and Mac configuration files into timestamped directories under `backups/` (with a `backups/latest` symlink and a `MANIFEST.txt` per run). There is no build, lint, or test tooling — verify changes by running the script and inspecting the output.

## Commands

```sh
./backup.sh                    # back up to ./backups/<timestamp>
./backup.sh -d <dir>           # custom destination root
./backup.sh --include-secrets  # also copy SSH keys, AWS creds, kube config, shell history
```

To verify a change: `rm -rf backups && ./backup.sh`, then check the reported size and `cat backups/latest/MANIFEST.txt`. A healthy secrets-excluded backup is ~200K; a sudden jump to megabytes means a binary/cache directory leaked in.

## Design constraints (learned the hard way)

- **Secrets are excluded by default** (SSH private keys, `~/.aws/credentials`, gh `hosts.yml`, gcloud credential DBs). Anything newly added to the backup set must respect the `INCLUDE_SECRETS` flag and the `EXCLUDE_ARGS` rsync excludes. Never move a credential file into the default set.
- **rsync must skip special files**: `--no-specials --no-devices` is load-bearing — `~/.config/op` and `~/.config/iterm2` contain live sockets that otherwise abort the run (exit 23).
- **Copy config, not installed artifacts**: e.g. only `~/.config/tfenv/version` is backed up because `tfenv`'s `versions/` dir holds 700MB of Terraform binaries; only `~/.oh-my-zsh/custom` is backed up, not the whole framework. Apply the same judgment to new entries.
- `copy_home` silently skips nonexistent paths, so it's safe to list files the machine may not have; it preserves paths relative to `$HOME` under `<dest>/home/`.
- Every added item must be recorded in `MANIFEST.txt` (`copy_home` does this automatically; ad-hoc sections like Homebrew/VS Code append manually).

## Machine-specific notes

The backup set was tailored to this machine (zsh + oh-my-zsh, Homebrew, VS Code, iTerm2, and `~/.config` tools: gh, fish, iterm2, op, packer, pagerduty-cli, tfenv). When adding coverage for a new tool, check what actually exists on disk first rather than adding speculative paths.
