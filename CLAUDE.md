# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Zirconium is a fork of the upstream [zirconium-dev/zirconium](https://github.com/zirconium-dev/zirconium) project — an opinionated Fedora-bootc atomic Linux distribution using Niri (tiling WM) and DankMaterialShell. This fork adds personal dotfiles ([pbonh/zdots](https://github.com/pbonh/zdots)), developer tools, and preinstalled flatpaks. Images are published to `ghcr.io/pbonh/zirconium` (base) and `ghcr.io/pbonh/zirconium-nvidia` (NVIDIA variant).

## Build System

The image is built with **mkosi** (systemd's image builder) targeting Fedora 44. The `Justfile` wraps the full workflow.

### Key Commands

```bash
# Full pipeline: build → load → lint → rechunk → disk image → boot in VM
just

# Individual steps:
just build                  # mkosi build (auto-inits submodules)
sudo just load              # Load OCI image into podman as localhost/zirconium:latest
sudo just lint              # Run bootc container lint
sudo just ostree-rechunk    # Rechunk to max 120 layers
sudo env BUILD_BASE_DIR=/tmp just disk-image  # Create 20GB bootable disk image
just clean                  # Remove mkosi build artifacts and caches
```

Build output lands in `mkosi.output/` (configured via `OutputDirectory=` in `mkosi.conf`).

### Environment Variables

- `IMAGE_FULL` — Override image tag (default: `localhost/zirconium:latest`)
- `BUILD_FILESYSTEM` — Filesystem for disk image (default: `btrfs`)
- `BUILD_BASE_DIR` — Directory for disk image output (default: `.`)

## Architecture

### mkosi Configuration Layering

Configuration is composed via mkosi's include/profile system:

1. **`mkosi.conf`** — Root config: Fedora 44, build resources (4 CPU, 4GB RAM), profile selection
2. **`mkosi.conf.d/`** — Modular package manifests and repo definitions, each focused on a concern (theme packages, niri WM, DMS shell, UBlue utilities, Terra repos, etc.)
3. **`mkosi.profiles/`** — Stacked build profiles:
   - `base-desktop` → broad hardware support and firmware
   - `bootc-ostree` → image-based deployment (symlinks /home,/root,/opt,/srv → /var, dracut initramfs)
   - `fedora-bootc-ostree` → Fedora-specific systemd presets, SELinux
   - `nvidia` → DKMS drivers, kernel module loading
4. **`mkosi.extra/`** — Files copied verbatim into the image (systemd units, scripts, configs, dotfiles)

### Customization Entry Points

- **Package repos** — `repos/` directory contains `.repo` files for COPR and custom repos; referenced by configs in `mkosi.conf.d/`
- **Shell integrations** — `mkosi.extra/usr/share/factory/etc/profile.d/` (atuin, fzf, starship, zoxide, ble.sh, brew, mise, carapace). `/etc` overrides live in `/usr/share/factory/etc/` and are materialized via tmpfiles.d on first boot (`mkosi.extra/usr/lib/tmpfiles.d/99-zirconium-factory.conf`).
- **Systemd services** — `mkosi.extra/usr/lib/systemd/system/` and `user/` (flatpak preinstall, chezmoi auto-update, fcitx5, udiskie)
- **Custom scripts** — `mkosi.extra/usr/bin/` (zjust, zfetch, glorpfetch, zmotd, zocr)
- **Build hooks** — `mkosi.postinst.chroot` and `mkosi.prepare.chroot` run during image build

### Submodules

Managed via `.gitmodules` — run `just ensure-submodules` if builds fail on missing content:
- `assets/` — wallpapers, logos, ISO branding (pointed at [pbonh/assets](https://github.com/pbonh/assets))
- `mkosi.extra/usr/share/zirconium/zdots/` — chezmoi dotfiles (pointed at [pbonh/zdots](https://github.com/pbonh/zdots))
- `subprojects/ublue-brew` — Homebrew integration from ublue-os
- `subprojects/bluefin-common` — shared utilities from Project Bluefin

### CI/CD

GitHub Actions workflows in `.github/workflows/`:
- **build-standard.yaml** / **build-nvidia.yaml** — Triggered on push, PR, weekly schedule (Tuesday 1am UTC), or manual dispatch. Build both amd64 and arm64.
- **build-rawhide.yaml** — Rawhide variant builds.
- **reusable-build.yaml** — Shared build template: mkosi build → podman load → rechunk → bootc lint → cosign sign → push to GHCR
- **build-disk.yml** — ISO generation via osbuild, branded with mkksiso, checksums uploaded to S3

Images are signed with cosign. The public key is at `cosign.pub` and installed into the image at `/usr/share/pki/containers/zirconium.pub`.

## Working With This Repo

- Most changes involve editing mkosi config files (`.conf`), adding/removing packages, or modifying files in `mkosi.extra/`.
- Package removal uses mkosi's `RemovePackages=` directive (see `mkosi.conf.d/theme.conf` for examples).
- To add a new COPR repo: create a `.repo` file in `repos/`, add a corresponding `.conf` in `mkosi.conf.d/` with `RepositoryDirectories=` and `Packages=`.
- The `mkosi.postinst.chroot` script runs post-install customizations (enabling services, setting up flatpak repos, etc.) — this is where imperative setup goes.
- When adding `/etc` configuration files, place them under `mkosi.extra/usr/share/factory/etc/` — upstream migrated all `/etc` overrides to the factory directory and uses tmpfiles.d to materialize them on first boot.
- Two image flavors exist: base and nvidia. The nvidia variant adds the `nvidia` profile and uses separate workflow/ISO configs (`iso-nvidia.toml`).
