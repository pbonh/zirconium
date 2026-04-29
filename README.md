# zirconium

Personal customization layer on top of [zirconium](https://github.com/zirconium-dev/zirconium), built with [BlueBuild](https://blue-build.org).

Upstream zirconium provides niri (tiling Wayland compositor), DankMaterialShell, the Fedora-bootc base, and the broader desktop session. This image adds:

- **Browsers:** Brave
- **Terminals:** Ghostty, WezTerm-nightly, Kitty
- **Editors:** Neovim, [Zed](https://zed.dev) (via Terra), [Cursor](https://cursor.com) (via AppImage)
- **AI coding CLIs:** `claude` ([Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code)), `codex` ([OpenAI Codex CLI](https://www.npmjs.com/package/@openai/codex)), `pi` ([Pi coding agent](https://www.npmjs.com/package/@mariozechner/pi-coding-agent))
- **Container/dev tooling:** Docker CE, distrobox, Node.js, gcc/make, Ansible
- **Shell stack additions:** atuin, carapace, nu, syncthing, yazi, qt6ct
- **Personal flatpaks:** Bitwarden, Obsidian, Collabora Office, Alpaca, etc.
- **Dotfiles:** auto-applied via [chezmoi](https://chezmoi.io) from [pbonh/zdots](https://github.com/pbonh/zdots) on first login

Everything else (DE, shell stack baseline, theme, base hardware support) flows through from upstream automatically.

## Install

From any existing Fedora bootc / Silverblue / Kinoite system:

    sudo bootc switch ghcr.io/pbonh/zirconium:latest
    sudo systemctl reboot

If you don't yet have a bootc-capable Fedora install, install Fedora Silverblue from the [official ISO](https://fedoraproject.org/silverblue/) first, then run the command above.

## Update

Updates are pulled automatically by `bootc-fetch-apply-updates.timer`. To trigger an update manually:

    sudo bootc upgrade
    sudo systemctl reboot

To roll back to the previous deployment:

    sudo bootc rollback

## Verify image signature

The image is signed with cosign. To verify against the public key in this repo:

    cosign verify --key cosign.pub ghcr.io/pbonh/zirconium:latest

## Build locally

Install the BlueBuild CLI (requires Rust):

    cargo install --locked bluebuild

Then:

    just submodule-init    # one-time setup for the zdots submodule
    just build             # full build → localhost/zirconium:latest
    just generate          # render the Containerfile without building
    just lint              # validate the recipe

To install your local build instead of the published image:

    just switch-local

## Customize

Most changes are edits to one of the `recipes/NN-*.yml` module files, or new files added under `files/system/`. See the [BlueBuild docs](https://blue-build.org/learn/) for module reference.

For changes that should affect the upstream image (niri configs, DMS configs, base packages), open a PR or issue at [zirconium-dev/zirconium](https://github.com/zirconium-dev/zirconium) instead — this repo is intentionally a thin layer.

## License

MIT — see [LICENSE](LICENSE).
