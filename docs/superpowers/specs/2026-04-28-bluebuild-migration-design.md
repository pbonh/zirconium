# BlueBuild Migration Design

**Date:** 2026-04-28
**Status:** Approved (brainstorming complete; ready for implementation planning)

## Summary

Migrate `pbonh/zirconium` from a fork of `zirconium-dev/zirconium` (mkosi-based Fedora bootc image build) to a thin [BlueBuild](https://blue-build.org/learn/getting-started/) customization layer that stacks **on top of** the upstream `ghcr.io/zirconium-dev/zirconium:latest` image. Instead of reproducing zirconium from scratch, the new repo declares only the user's personal additions: extra repos, extra packages, the `zdots` chezmoi dotfiles, custom scripts, and personal flatpak preinstalls. Everything else (niri, DMS, shell stack, theme, base-desktop, bootc wiring) flows through from upstream automatically.

## Goals

- Produce `ghcr.io/pbonh/zirconium:latest` from a BlueBuild recipe whose base image is `ghcr.io/zirconium-dev/zirconium:latest`, signed with cosign, built and published by GitHub Actions on push / PR / weekly schedule / manual dispatch.
- Preserve the user-facing experience: niri + DMS (inherited), chezmoi-applied dotfiles from `pbonh/zdots`, personal additions (Brave, Ghostty, WezTerm-nightly, Docker CE), custom scripts (whichever of `zjust`/`zfetch`/`glorpfetch`/`zmotd`/`zocr` are actually user-owned vs. inherited).
- Install/update via `bootc switch` / `bootc upgrade` — no behavior change for the end user.
- Drop everything no longer needed once we stop maintaining a from-scratch build: nvidia variant, prebuilt ISO, S3 upload, osbuild, mkosi tooling, ublue-brew submodule, bluefin-common submodule, all `mkosi.profiles/` content, all `mkosi.conf.d/` files that re-declared upstream config, all `mkosi.extra/` content that came from upstream.

## Non-goals

- nvidia variant (`ghcr.io/pbonh/zirconium-nvidia`).
- Premade ISO (`iso.toml`, `iso-nvidia.toml`, osbuild workflow, S3 publication).
- Backwards compatibility with existing `mkosi.*` config files or `Justfile` recipes.
- Re-engineering dotfiles or DMS configs themselves — those carry over verbatim.
- Diverging from upstream's DE / shell baseline. If upstream changes niri or DMS, we follow.

## Architecture

### Base image

`ghcr.io/zirconium-dev/zirconium:latest` — the upstream zirconium image itself. This is the entire point of the migration: BlueBuild lets us declaratively layer customizations on a maintained base instead of forking and rebuilding the whole thing.

Implication: we inherit upstream's release cadence and signing chain. Trade-off: less control, far less work, automatic updates from upstream propagate without action.

### Recipe organization

Modular: a short `recipes/recipe.yml` lists `from-file` references. Five module files cover the user's actual additions; everything else comes from the base.

### Repo layout (post-migration)

```
zirconium/
├── recipes/
│   ├── recipe.yml              # base-image: ghcr.io/zirconium-dev/zirconium + from-file refs
│   ├── 01-extra-repos.yml      # Brave, Ghostty, WezTerm-nightly, Docker CE COPRs/repos
│   ├── 02-extra-packages.yml   # brave-browser, ghostty, wezterm, docker-ce + plugins, pbonh-extras pkgs
│   ├── 03-dotfiles.yml         # zdots submodule + chezmoi --user systemd unit/timer
│   ├── 04-custom-scripts.yml   # user-owned scripts copied to /usr/bin (audit-determined subset)
│   └── 05-flatpaks.yml         # personal flatpak preinstall list (delta over upstream)
├── files/
│   ├── system/                 # copied verbatim into image at /
│   │   ├── usr/bin/            # user-owned custom scripts
│   │   ├── usr/lib/systemd/user/  # chezmoi-apply.service + .timer
│   │   └── usr/share/zirconium/zdots/  # populated by submodule via files entry
│   └── scripts/                # any postinst hook still needed (likely empty)
├── zdots/                      # submodule, github.com/pbonh/zdots
├── assets/                     # submodule kept pending audit; drop if fully redundant with upstream
├── cosign.pub                  # NEW key, see Security
├── .github/workflows/
│   └── build.yml               # BlueBuild reusable workflow
├── Justfile                    # ~15 lines: build / generate / lint / switch-* / clean
├── README.md                   # rewritten: install + update + "thin layer on upstream"
└── LICENSE
```

### Submodule disposition

| Submodule | Disposition |
|---|---|
| `mkosi.extra/usr/share/zirconium/zdots` → relocates to `zdots/` | Keep. URL stays `https://github.com/pbonh/zdots.git`. Mounted at `/usr/share/zirconium/zdots/` in the image via the `files` module. |
| `assets` | **Audit during implementation.** If upstream zirconium ships equivalent wallpapers/logos, drop and use upstream's. If `pbonh/assets` adds personal content on top, keep it and copy into `files/system/usr/share/backgrounds/zirconium/`. |
| `subprojects/ublue-brew` | Drop. Brew is provided by upstream zirconium (or by BlueBuild's `brew` module if needed as a delta). |
| `subprojects/bluefin-common` | Drop. Was a vendored library for from-scratch builds; no longer relevant. |

### Dotfiles application

Unchanged: zdots source baked into image at `/usr/share/zirconium/zdots/`; a systemd `--user` service runs `chezmoi apply` from that path on first login, with a sibling `.timer` for periodic reapplication. Both unit files migrate verbatim into `files/system/usr/lib/systemd/user/`. Confirm during audit that upstream zirconium does not already ship its own chezmoi unit at the same path — if so, our unit either replaces it (file shadowing) or is renamed.

### Module mapping (current `pbonh-*` configs → BlueBuild recipes)

The translation table is small because we're only carrying over user-owned content. Upstream-inherited config (niri-git.conf, avengemedia-*.conf, terra*.conf, theme.conf, ublue-os-packages.conf, subprojects.conf, non-rawhide.conf) is **dropped** — upstream supplies it.

| Today (mkosi, user-owned) | Tomorrow (BlueBuild) |
|---|---|
| `mkosi.conf.d/pbonh-brave.conf` + `repos/brave-browser.repo` | `01-extra-repos.yml` (`rpm-ostree.repos`) + `02-extra-packages.yml` (`rpm-ostree.install: brave-browser`) |
| `mkosi.conf.d/pbonh-copr.conf` + `repos/scottames-ghostty.repo` + `repos/wezfurlong-wezterm-nightly.repo` (and any other user COPRs) | Same: repo files via `01-extra-repos.yml`, packages via `02-extra-packages.yml` |
| `mkosi.conf.d/pbonh-docker.conf` + `repos/docker-ce.repo` + `repos/nvidia-container-toolkit.repo` | `01-extra-repos.yml` + `02-extra-packages.yml`. nvidia-container-toolkit dropped (no nvidia variant). |
| `mkosi.conf.d/pbonh-extras.conf` | `02-extra-packages.yml` |
| `mkosi.extra/usr/share/zirconium/zdots/` (submodule) + chezmoi systemd unit + timer | `03-dotfiles.yml` references the submodule path via `files` module; unit files copied to `files/system/usr/lib/systemd/user/` |
| `mkosi.extra/usr/bin/{zjust,zfetch,glorpfetch,zmotd,zocr}` (audit-filtered subset) | `04-custom-scripts.yml` copies via `files` module to `files/system/usr/bin/` |
| Personal flatpak preinstall list (delta over upstream) | `05-flatpaks.yml` (`default-flatpaks` module) |
| `mkosi.postinst.chroot` and `mkosi.prepare.chroot` | Likely empty after migration — most contents were setting up the from-scratch build. Anything genuinely user-specific that survives audit goes to `files/scripts/` invoked by BlueBuild's `script` module. |

### Audit step (precondition for implementation)

Before writing any recipe, diff the current repo against upstream `zirconium-dev/zirconium` (matching commit / latest main) to definitively classify each file as:

- **Inherited from upstream** → drop on the wipe step, do not migrate.
- **User addition** → migrate into the appropriate recipe / `files/system/` location.
- **User override** of an upstream file → decide case-by-case whether to keep the override or drop it.

Specific files needing audit: every `mkosi.conf.d/*.conf` not prefixed `pbonh-`, every file under `mkosi.extra/`, the `assets/` submodule, the custom scripts in `mkosi.extra/usr/bin/`, and the chezmoi systemd unit files.

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

### README outline

1. One-line description: "Personal customization layer on top of [zirconium](https://github.com/zirconium-dev/zirconium), built with BlueBuild."
2. What this adds vs. upstream: bullet list of personal additions (Brave, Ghostty, WezTerm-nightly, Docker CE, dotfiles, custom scripts).
3. Install (from existing Fedora bootc / Silverblue / Kinoite system: `bootc switch ghcr.io/pbonh/zirconium:latest`).
4. Update (`bootc upgrade` + `bootc rollback`).
5. Verify image signature (cosign, with both keyless and key-based examples).
6. Build locally (install bluebuild CLI, `just build`).
7. Customize (pointer to `recipes/` and BlueBuild docs).
8. Note that everything else comes from upstream zirconium; for non-personal customizations, contribute upstream.
9. License.

## Security

Existing `cosign.key` and `cosign.key.b64` files are committed to the repo. Even after the migration wipes the working tree, both files remain in git history and on the `legacy-mkosi` branch — they must be treated as compromised once that branch has been pushed (it has).

Mitigation, executed as part of the migration:

1. Generate a new cosign keypair (`cosign generate-key-pair`).
2. Store the new private key as a GitHub Actions secret named `SIGNING_SECRET`.
3. Commit only the new `cosign.pub` to the repo.
4. Add `cosign.key*` to `.gitignore`.
5. (Optional, best-effort) Use `git-filter-repo` or BFG to scrub the old key from `legacy-mkosi`'s history before pushing the tag/branch. Effectiveness limited because the key has already been pushed.

## Migration sequencing

Work happens on a `bluebuild` branch; `main` only fast-forwards once the new image boots and verifies signature.

1. `git tag legacy-mkosi-v1 main && git push --tags` (belt-and-suspenders alongside the `legacy-mkosi` branch).
2. `git checkout -b bluebuild`.
3. **Audit.** Diff current tree against upstream `zirconium-dev/zirconium`. Classify every file (inherited / user-added / user-override). Output: explicit list of files to migrate vs. drop.
4. **Wipe.** Delete: every `mkosi.*` file, `mkosi.conf.d/`, `mkosi.profiles/`, `mkosi.extra/` (preserving only audit-identified user content), `repos/` (preserving only user-added repo files), `subprojects/`, `iso*.toml`, `cache/`, `.mkosi-private/`, `REBASE_GUIDE.md`, `SIGNATURE_FIX.md`, `artifacthub-repo.yml`, `cosign.key*`, the four old workflows.
5. **Reset submodules.** Remove `subprojects/ublue-brew` and `subprojects/bluefin-common` from `.gitmodules`; relocate `mkosi.extra/usr/share/zirconium/zdots` → `zdots/` in `.gitmodules` (URL unchanged); decide on `assets` based on audit.
6. **Generate cosign key.** New keypair → public commits at repo root, private goes into `SIGNING_SECRET` GH secret (handled outside the migration commit).
7. **Scaffold BlueBuild.** Copy in skeleton from BlueBuild's [template repo](https://github.com/blue-build/template), prune to our needs, set `base-image: ghcr.io/zirconium-dev/zirconium`, commit.
8. **Recipes 01–02** (extra repos + extra packages). First test that the layer builds cleanly on top of upstream.
9. **Recipes 03–05** (dotfiles, custom scripts, flatpaks).
10. **Workflow + Justfile + README.**
11. **Local CI dry run.** `bluebuild validate` + `bluebuild generate` to confirm Containerfile renders.
12. **Push branch, let GHA build.** Iterate on failures.
13. **Boot test the published image.** `bootc switch` from a test Fedora atomic VM. Verify dotfiles apply, custom scripts work, signing verifies, all personal additions present.
14. **Fast-forward `main` → `bluebuild`.** Migration done.

The audit (step 3) is the single most important step and is gating for everything after. Steps 8–9 are the substantive translation work and each becomes its own implementation phase. Steps 1–2 and 4–7 and 10 are mechanical.

## Risks and unknowns

- **Coupling to upstream cadence (primary risk).** If `zirconium-dev/zirconium` breaks, removes a package we depend on, or changes its DE configuration, our image inherits the change. Mitigations: pin `image-version` to a specific tag/digest if we want stability over freshness; subscribe to upstream releases.
- **Audit accuracy.** Misclassifying an upstream file as user-owned (or vice versa) leads to either bloat or missing functionality. Mitigation: do the audit against a specific upstream commit, document which one in the migration commit message, and re-verify on first boot test.
- **Chezmoi unit collision.** If upstream ships its own chezmoi systemd unit, our copy needs a different name or must intentionally shadow it. Audit-identifiable.
- **Custom-scripts provenance.** Names like `zjust`/`zfetch`/`zmotd` follow upstream's `z*` convention and may originate from upstream. The audit must cleanly determine which are user-owned.
- **`assets` submodule fate.** Pending audit; the disposition affects whether the submodule survives the migration.
