# BlueBuild Migration Design

**Date:** 2026-04-28
**Status:** Approved (brainstorming complete; ready for implementation planning)

## Summary

Migrate `pbonh/zirconium` from a fork of `zirconium-dev/zirconium` (mkosi-based Fedora bootc image build) to a clean-slate [BlueBuild](https://blue-build.org/learn/getting-started/) recipe that produces an equivalent image. The single goal is reproducing the niri + DankMaterialShell desktop with the existing dotfiles, shell stack, dev tooling, terminals, browsers, and theme on a maintained ublue base — with substantially less repo surface area.

## Goals

- Produce `ghcr.io/pbonh/zirconium:latest` from a BlueBuild recipe, signed with cosign, built and published by GitHub Actions on push / PR / weekly schedule / manual dispatch.
- Preserve the existing user-facing experience: niri, DankMaterialShell, chezmoi-applied dotfiles from `pbonh/zdots`, the full shell stack (atuin, fzf, starship, zoxide, ble.sh, mise, carapace, brew, fish), Ghostty + WezTerm, Brave, docker-ce, greetd, theme tweaks, custom scripts (`zjust`, `zfetch`, `glorpfetch`, `zmotd`, `zocr`).
- Install/update via `bootc switch` / `bootc upgrade` — no behavior change for the end user.
- Drop everything not actively used: nvidia variant, prebuilt ISO, S3 upload, osbuild, mkosi tooling, ublue-brew + bluefin-common submodules.

## Non-goals

- nvidia variant (`ghcr.io/pbonh/zirconium-nvidia`).
- Premade ISO (`iso.toml`, `iso-nvidia.toml`, osbuild workflow, S3 publication).
- Backwards compatibility with existing `mkosi.*` config files or `Justfile` recipes.
- Re-engineering the dotfiles or DMS configs themselves — those carry over verbatim.

## Architecture

### Base image

`ghcr.io/ublue-os/base-main` (or upstream Fedora bootc if base-main brings unwanted defaults). Minimal image, no GNOME, supplies bootc/ostree/dracut/systemd-preset wiring that the current `bootc-ostree` and `fedora-bootc-ostree` mkosi profiles assemble manually.

### Recipe organization

Modular: a short `recipes/recipe.yml` lists `from-file` references to a numbered set of module files. Mirrors the current `mkosi.conf.d/*.conf` 1:1ish so the migration is mostly translation.

### Repo layout (post-migration)

```
zirconium/
├── recipes/
│   ├── recipe.yml              # top-level: stages + from-file refs
│   ├── 01-repos.yml            # all COPR / 3rd-party repos enabled
│   ├── 02-niri-dms.yml         # niri + DMS install + configs
│   ├── 03-shell-stack.yml      # atuin/fzf/starship/zoxide/ble.sh/mise/carapace/brew/fish
│   ├── 04-terminals.yml        # ghostty + wezterm-nightly
│   ├── 05-browsers.yml         # brave
│   ├── 06-dev-tooling.yml      # docker-ce, dev packages
│   ├── 07-flatpaks.yml         # default-flatpaks module
│   ├── 08-greetd.yml           # greetd login session
│   ├── 09-theme.yml            # package removals + theme installs
│   ├── 10-zirconium-extras.yml # custom scripts + dotfiles staging
│   └── 99-signing.yml          # cosign pubkey + container policy
├── files/
│   ├── system/                 # copied verbatim into image at /
│   │   ├── usr/bin/            # zjust, zfetch, glorpfetch, zmotd, zocr
│   │   ├── usr/lib/systemd/    # chezmoi-apply user unit, flatpak-preinstall, fcitx5, udiskie
│   │   ├── usr/share/          # dms configs, factory/etc overrides, pki/containers, backgrounds
│   │   └── etc/                # greetd config
│   └── scripts/
│       └── postinst.sh         # what's left of mkosi.postinst.chroot
├── assets/                     # submodule (wallpapers/logos)
├── zdots/                      # submodule (chezmoi dotfiles, github.com/pbonh/zdots)
├── cosign.pub                  # public verification key (NEW key — see Security below)
├── .github/workflows/
│   └── build.yml               # BlueBuild reusable workflow
├── Justfile                    # ~15 lines: build / generate / lint / switch-* / clean
├── README.md                   # install + update docs (rewritten)
└── LICENSE
```

### Submodule disposition

| Submodule | Disposition |
|---|---|
| `assets` | Keep. Wallpapers/logos copied into `files/system/usr/share/backgrounds/zirconium/`. |
| `zdots` (relocated from `mkosi.extra/usr/share/zirconium/zdots/` to `zdots/`) | Keep. URL stays `https://github.com/pbonh/zdots.git`. Mounted at `/usr/share/zirconium/zdots/` in the image via the `files` module. |
| `subprojects/ublue-brew` | Drop. Replaced by BlueBuild's `brew` module. |
| `subprojects/bluefin-common` | Drop. Audit usage during implementation; re-implement any consumed files inline under `files/system/`. |

### Dotfiles application

Unchanged from today: zdots source baked into image at `/usr/share/zirconium/zdots/`; a systemd `--user` service runs `chezmoi apply` from that path on first login, with a sibling `.timer` for periodic reapplication. Both unit files migrate verbatim into `files/system/usr/lib/systemd/user/`.

### Module mapping (mkosi → BlueBuild)

| Today (mkosi) | Tomorrow (BlueBuild) |
|---|---|
| `repos/*.repo` + `RepositoryDirectories=` | `rpm-ostree.repos` |
| `Packages=` | `rpm-ostree.install` |
| `RemovePackages=` | `rpm-ostree.remove` |
| `mkosi.extra/usr/share/factory/etc/...` (factory pattern) | `files` module copies directly to `/etc` (BlueBuild + bootc handles persistence without the factory dance) |
| `mkosi.extra/usr/...` (everything else) | `files` module → `files/system/usr/...` mirrors verbatim |
| `mkosi.postinst.chroot` | `script` module → `files/scripts/postinst.sh` (most contents replaced by `systemd.enabled-services` / `systemd.enabled-user-services` / `default-flatpaks`; script gets thinner) |
| `mkosi.prepare.chroot` | Folded into the same `script` module if anything remains |
| Flatpak `preinstall.d/*` files | `default-flatpaks` module |
| `system-preset/` and `user-preset/` | `systemd.enabled-services` / `systemd.enabled-user-services` |
| `cosign.pub` baked at `/usr/share/pki/containers/zirconium.pub` + container policy | BlueBuild template handles signing scaffolding |
| `mkosi.profiles/{base-desktop,bootc-ostree,fedora-bootc-ostree}` | Mostly absorbed by `base-main`. Gaps (specific dracut conf, kargs, sysusers) move to a `kargs` module + `files` entries, possibly a `00-hardware.yml` for missing firmware/HW packages. |
| `mkosi.profiles/nvidia` | Dropped. |

### CI workflow

Single `.github/workflows/build.yml` calling BlueBuild's reusable workflow:

```yaml
name: build
on:
  push: { branches: [main] }
  pull_request: { branches: [main] }
  schedule: [{ cron: '0 1 * * 2' }]   # Tuesday 1am UTC (matches existing cadence)
  workflow_dispatch:
permissions:
  contents: read
  packages: write
  id-token: write
jobs:
  build:
    uses: blue-build/github-action/.github/workflows/build.yml@v1
    with:
      recipe: recipes/recipe.yml
    secrets:
      SIGNING_SECRET: ${{ secrets.SIGNING_SECRET }}
```

Replaces all five current workflows (`build-standard`, `build-nvidia`, `build-rawhide`, `reusable-build`, `build-disk`). Multi-arch (amd64+arm64) is on by default in BlueBuild's reusable.

### Justfile

```makefile
default: build

build:
    bluebuild build recipes/recipe.yml

generate:
    bluebuild generate recipes/recipe.yml

lint:
    bluebuild validate recipes/recipe.yml

switch-local:
    sudo bootc switch --transport containers-storage localhost/zirconium:latest

switch-remote:
    sudo bootc switch ghcr.io/pbonh/zirconium:latest

clean:
    podman image rm -f localhost/zirconium:latest 2>/dev/null || true
    rm -rf .bluebuild/
```

Gone: `load`, `lint` (replaced by `bluebuild validate`), `ostree-rechunk` (BlueBuild does this in CI), `disk-image`, `ensure-submodules` (callers run `git submodule update --init` themselves; not wired into `build`).

### README outline

Sections (full draft in design discussion, not duplicated here):

1. One-line description
2. Install (from existing Fedora bootc / Silverblue / Kinoite system: `bootc switch ...`)
3. Update (`bootc upgrade` + `bootc rollback`)
4. Verify image signature (cosign, with both keyless and key-based examples)
5. Build locally (install bluebuild CLI, `just build`)
6. What's inside (bullet list)
7. Customize (pointer to `recipes/` and BlueBuild docs)
8. License

## Security

Existing `cosign.key` and `cosign.key.b64` files are committed to the repo. Even after the migration wipes the working tree, both files remain in git history and on the `legacy-mkosi` branch — they must be treated as compromised once that branch has been pushed (it has).

**Mitigation, executed as part of the migration:**

1. Generate a new cosign keypair (`cosign generate-key-pair`).
2. Store the new private key as a GitHub Actions secret named `SIGNING_SECRET`.
3. Commit only the new `cosign.pub` to the repo.
4. Add `cosign.key*` to `.gitignore`.
5. (Optional, best-effort) Use `git-filter-repo` or BFG to scrub the old key from `legacy-mkosi`'s history before pushing the tag/branch. Effectiveness limited because the key has already been pushed.

## Migration sequencing

Work happens on a `bluebuild` branch; `main` only fast-forwards once the new image boots and verifies signature.

1. `git tag legacy-mkosi-v1 main && git push --tags` (belt-and-suspenders alongside the `legacy-mkosi` branch).
2. `git checkout -b bluebuild`.
3. **Wipe.** Delete: all `mkosi.*` files, `mkosi.conf.d/`, `mkosi.profiles/`, `mkosi.extra/`, `repos/`, `subprojects/`, `iso*.toml`, `cache/`, `.mkosi-private/`, `REBASE_GUIDE.md`, `SIGNATURE_FIX.md`, `artifacthub-repo.yml`, `cosign.key*`, the four old workflows.
4. **Reset submodules.** Remove `subprojects/ublue-brew` and `subprojects/bluefin-common` from `.gitmodules`; keep `assets`; relocate `mkosi.extra/usr/share/zirconium/zdots` → `zdots/` in `.gitmodules` (URL unchanged).
5. **Generate cosign key.** New keypair → public commits at repo root, private goes into `SIGNING_SECRET` GH secret (handled outside the migration commit).
6. **Scaffold BlueBuild.** Copy in skeleton from BlueBuild's [template repo](https://github.com/blue-build/template), prune to our needs, commit.
7. **Recipes 01–03** (repos, niri+DMS, shell-stack). First image that should boot end-to-end.
8. **Recipes 04–08** (terminals, browsers, dev-tooling, flatpaks, greetd).
9. **Recipes 09–10** (theme, zirconium-extras + custom scripts + chezmoi unit).
10. **Workflow + Justfile + README.**
11. **Local CI dry run.** `bluebuild validate` + `bluebuild generate` to confirm Containerfile renders.
12. **Push branch, let GHA build.** Iterate on failures.
13. **Boot test the published image.** `bootc switch` from a test Fedora atomic VM. Verify niri+DMS, dotfiles apply, custom scripts work, signing verifies.
14. **Fast-forward `main` → `bluebuild`.** Migration done.

Steps 7–9 are the substantive translation work and each becomes its own implementation phase in the plan. Steps 1–6 and 10 are mechanical.

## Risks and unknowns

- **`base-desktop` profile coverage in `base-main`.** The current `mkosi.profiles/base-desktop` adds broad firmware and hardware-support packages. Need to enumerate that profile's package list during implementation and add a `00-hardware.yml` recipe for anything `base-main` doesn't already supply. Discoverable on first image-build attempt; not a blocker for design.
- **`bluefin-common` usage.** Audit needed during implementation to identify which files we actually consume. If it turns out we depend on more than a couple of scripts, we may want to vendor them inline rather than re-implement.
- **DMS / niri-git COPR availability for ublue base.** Both repos target Fedora 44; should work against `base-main` since it's also Fedora 44, but cross-arch (arm64) availability needs verification on the first multi-arch CI run.
- **chezmoi systemd unit semantics.** Today's per-user unit assumes `/usr/share/zirconium/zdots/` is read-only and writable per-user state lives in `~/.local/share/chezmoi`. That should hold under bootc identically — verify on first boot test.
