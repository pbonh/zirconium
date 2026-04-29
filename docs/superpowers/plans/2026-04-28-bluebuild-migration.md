# BlueBuild Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert `pbonh/zirconium` from a from-scratch mkosi fork of `zirconium-dev/zirconium` into a thin BlueBuild customization layer stacked on `ghcr.io/zirconium-dev/zirconium:latest`, adding personal additions (Brave, Ghostty, WezTerm, Docker, Zed, Cursor, AI CLIs, dotfiles, custom scripts).

**Architecture:** Six BlueBuild module files declare only the user's deltas over upstream zirconium. CI builds and pushes a signed image to `ghcr.io/pbonh/zirconium:latest` via BlueBuild's reusable workflow. End user installs/updates with `bootc switch`/`bootc upgrade` — no behavior change.

**Tech Stack:** BlueBuild (recipe + Containerfile build system), bootc (image-based deployment), cosign (signing), GitHub Actions, Just (task runner), npm (for AI CLI install at build time).

**Reference:** `docs/superpowers/specs/2026-04-28-bluebuild-migration-design.md` (approved spec).

---

## File Structure

**Files created (post-migration end state):**

```
recipes/recipe.yml                          # top-level: base-image + from-file refs
recipes/01-extra-repos.yml                  # COPRs + 3rd-party RPM repos
recipes/02-extra-packages.yml               # all extra RPMs (incl. zed)
recipes/03-dotfiles.yml                     # zdots staging + chezmoi systemd unit refs
recipes/04-custom-scripts.yml               # /usr/bin scripts (audit-determined subset)
recipes/05-flatpaks.yml                     # flatpak preinstall list
recipes/06-extra-tooling.yml                # script module → Cursor + AI CLI installers
files/system/usr/bin/<scripts>              # custom scripts (audit-determined)
files/system/usr/lib/systemd/user/chezmoi-apply.service
files/system/usr/lib/systemd/user/chezmoi-apply.timer
files/system/usr/share/zirconium/zdots/     # populated by submodule
files/scripts/install-cursor.sh             # Cursor AppImage installer
files/scripts/install-ai-clis.sh            # npm install -g for claude/codex/pi
.github/workflows/build.yml                 # BlueBuild reusable workflow caller
Justfile                                    # build / generate / lint / switch / clean
README.md                                   # rewritten install/update docs
cosign.pub                                  # NEW key (rotated)
.gitignore                                  # adds cosign.key*, .bluebuild/, etc.
.gitmodules                                 # zdots URL preserved, others removed
```

**Files deleted:**

Every `mkosi.*` file at root, `mkosi.conf.d/`, `mkosi.profiles/`, `mkosi.extra/` (preserving only audit-identified user content under new paths), `repos/` (preserving only user-added repo files for reference, though most will be replaced by inline URLs in recipes), `subprojects/`, `iso*.toml`, `cache/`, `.mkosi-private/`, `REBASE_GUIDE.md`, `SIGNATURE_FIX.md`, `artifacthub-repo.yml`, `cosign.key`, `cosign.key.b64`, all four old workflows (`build-standard.yaml`, `build-nvidia.yaml`, `build-rawhide.yaml`, `reusable-build.yaml`, `build-disk.yml`).

---

## Pre-flight: Required tools

Before starting, verify these are installed locally:

```bash
git --version           # any recent version
podman --version        # for local image builds
bluebuild --version     # cargo install --locked bluebuild  (see https://blue-build.org/learn/)
cosign version          # for key generation
just --version          # task runner
gh --version            # GitHub CLI for managing secrets and PRs
```

If `bluebuild` is missing: `cargo install --locked bluebuild` (requires Rust toolchain).

---

## Phase 1: Setup branch and tag legacy state

### Task 1.1: Tag the current main as legacy-mkosi-v1 and create the bluebuild branch

**Files:**
- No file changes; git operations only.

- [ ] **Step 1: Verify current branch is clean**

```bash
cd /home/phillip/Boxes/Homes/DotDev/Code/github.com/pbonh/zirconium
git status
```

Expected: working tree clean (or only untracked `.claude/` and `REBASE_GUIDE.md`). If there are uncommitted changes you care about, stash or commit them before proceeding.

- [ ] **Step 2: Tag current main**

```bash
git tag legacy-mkosi-v1 main
git tag -l | grep legacy-mkosi-v1
```

Expected: `legacy-mkosi-v1` printed.

- [ ] **Step 3: Create and check out the bluebuild branch**

```bash
git checkout -b bluebuild
git branch --show-current
```

Expected: `bluebuild`.

- [ ] **Step 4: Push the tag and branch to origin**

```bash
git push origin legacy-mkosi-v1
git push -u origin bluebuild
```

Expected: tag and branch pushed; remote tracking established.

- [ ] **Step 5: Create a `legacy-mkosi` branch pointing at the same commit (belt-and-suspenders)**

```bash
git branch legacy-mkosi main
git push origin legacy-mkosi
```

Expected: `legacy-mkosi` branch exists on remote pointing at the current main commit.

---

## Phase 2: Audit current tree against upstream zirconium

This phase produces an `audit-report.txt` that classifies every file in `mkosi.conf.d/`, `mkosi.extra/`, `repos/`, and `assets/` as **inherited** (from upstream), **user-added** (not in upstream), or **user-override** (in upstream but modified). The wipe phase relies on this report.

### Task 2.1: Clone upstream and capture the audit commit

**Files:**
- Create: `audit-report.txt` (committed to bluebuild branch as a record).
- Create: `scripts/audit-vs-upstream.sh` (committed for reproducibility, deleted at end of migration).

- [ ] **Step 1: Clone upstream zirconium to a known temp location**

```bash
rm -rf /tmp/zirconium-upstream
git clone --depth 1 https://github.com/zirconium-dev/zirconium.git /tmp/zirconium-upstream
UPSTREAM_COMMIT=$(git -C /tmp/zirconium-upstream rev-parse HEAD)
echo "Auditing against upstream commit: $UPSTREAM_COMMIT"
```

Expected: clone succeeds; commit hash printed.

- [ ] **Step 2: Initialize upstream's submodules (need them for full diff)**

```bash
git -C /tmp/zirconium-upstream submodule update --init --recursive
```

Expected: submodules initialized (this may take a minute).

- [ ] **Step 3: Write the audit script**

Create `scripts/audit-vs-upstream.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Classify every file under mkosi.conf.d, mkosi.extra, repos, assets as one of:
#   INHERITED      — identical to upstream
#   USER-OVERRIDE  — present in upstream but modified
#   USER-ADDED     — not present in upstream

UPSTREAM=${1:-/tmp/zirconium-upstream}
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

if [ ! -d "$UPSTREAM" ]; then
    echo "Upstream clone not found at $UPSTREAM" >&2
    exit 1
fi

UPSTREAM_COMMIT=$(git -C "$UPSTREAM" rev-parse HEAD)
echo "# Audit against upstream commit: $UPSTREAM_COMMIT"
echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo

for dir in mkosi.conf.d mkosi.extra repos assets; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' f; do
        upstream_f="$UPSTREAM/$f"
        if [ ! -e "$upstream_f" ]; then
            echo "USER-ADDED: $f"
        elif [ -f "$f" ] && [ -f "$upstream_f" ]; then
            if cmp -s "$f" "$upstream_f"; then
                echo "INHERITED: $f"
            else
                echo "USER-OVERRIDE: $f"
            fi
        elif [ -L "$f" ]; then
            echo "SYMLINK: $f -> $(readlink "$f")"
        fi
    done < <(find "$dir" -type f -print0 2>/dev/null)
done

echo
echo "# Summary:"
echo "# USER-ADDED:    $(grep -c '^USER-ADDED:'    || true)"
echo "# USER-OVERRIDE: $(grep -c '^USER-OVERRIDE:' || true)"
echo "# INHERITED:     $(grep -c '^INHERITED:'     || true)"
```

- [ ] **Step 4: Make the audit script executable and run it**

```bash
mkdir -p scripts
# (paste the script content from Step 3 into scripts/audit-vs-upstream.sh)
chmod +x scripts/audit-vs-upstream.sh
./scripts/audit-vs-upstream.sh /tmp/zirconium-upstream | tee audit-report.txt
```

Expected: `audit-report.txt` populated with classified lines. Spot-check that:
- `mkosi.conf.d/pbonh-*.conf` files are classified `USER-ADDED`.
- `mkosi.conf.d/niri-git.conf`, `terra.conf`, `theme.conf`, `ublue-os-packages.conf`, `subprojects.conf` are classified `INHERITED` (or USER-OVERRIDE if you've modified them).
- `mkosi.extra/usr/share/zirconium/zdots/` shows USER-ADDED contents (the zdots submodule).

- [ ] **Step 5: Manually triage USER-OVERRIDE entries**

For each line classified `USER-OVERRIDE`, decide:
- Keep your override → migrate to BlueBuild
- Drop your override → let upstream win

Append your decision to `audit-report.txt` as a comment after each USER-OVERRIDE line:

```text
USER-OVERRIDE: mkosi.extra/usr/share/factory/etc/foo.conf
# DECISION: keep — adds X behavior
```

- [ ] **Step 6: Manually triage USER-ADDED `mkosi.extra/usr/bin/` scripts**

For each script in `mkosi.extra/usr/bin/`, verify it's actually user-owned vs. inherited:

```bash
diff -q mkosi.extra/usr/bin/zjust /tmp/zirconium-upstream/mkosi.extra/usr/bin/zjust 2>&1
diff -q mkosi.extra/usr/bin/zfetch /tmp/zirconium-upstream/mkosi.extra/usr/bin/zfetch 2>&1
diff -q mkosi.extra/usr/bin/glorpfetch /tmp/zirconium-upstream/mkosi.extra/usr/bin/glorpfetch 2>&1
diff -q mkosi.extra/usr/bin/zmotd /tmp/zirconium-upstream/mkosi.extra/usr/bin/zmotd 2>&1
diff -q mkosi.extra/usr/bin/zocr /tmp/zirconium-upstream/mkosi.extra/usr/bin/zocr 2>&1
```

Expected: each `diff -q` either says "Files differ" (override; keep), "files are identical" (inherited; drop), or "No such file" (user-added; keep). Record the decision for each in `audit-report.txt`.

- [ ] **Step 7: Decide `assets/` submodule fate**

```bash
ls assets/
ls /tmp/zirconium-upstream/assets/
diff -rq assets/ /tmp/zirconium-upstream/assets/ 2>&1 | head
```

If your `assets/` is identical or near-identical to upstream's: drop the submodule (let upstream supply assets). Otherwise: keep it. Record decision in `audit-report.txt`.

- [ ] **Step 8: Decide chezmoi systemd unit collision**

```bash
find /tmp/zirconium-upstream -name 'chezmoi*' -o -name '*zdots*' 2>/dev/null
find mkosi.extra -name 'chezmoi*' -o -name '*zdots*' 2>/dev/null
```

If upstream ships any chezmoi unit at the same path you do, decide whether to (a) shadow it (use the same name, your file wins), or (b) rename yours. Record decision.

- [ ] **Step 9: Commit the audit artifacts**

```bash
git add audit-report.txt scripts/audit-vs-upstream.sh
git commit -m "Audit current tree against upstream zirconium-dev/zirconium

Classifies every user file as INHERITED, USER-OVERRIDE, or USER-ADDED
against upstream commit $(git -C /tmp/zirconium-upstream rev-parse HEAD).
Used as the input to the wipe step in Phase 4."
```

Expected: commit succeeds with the upstream commit recorded in the message.

---

## Phase 3: Cosign key rotation

The current `cosign.key` and `cosign.key.b64` are committed to the repo and must be treated as compromised. Generate a new keypair, store the private key only in GitHub Secrets, and commit only the new public key.

### Task 3.1: Generate new cosign keypair and update GitHub Secret

**Files:**
- Create: `cosign.pub` (overwrites the old one; new public key)
- Modify: `.gitignore` (add `cosign.key*`)
- Delete (in Phase 4 wipe): `cosign.key`, `cosign.key.b64`

- [ ] **Step 1: Generate the new keypair**

In a temporary directory (NOT the repo) — the private key never gets committed:

```bash
mkdir -p ~/cosign-zirconium-new
cd ~/cosign-zirconium-new
cosign generate-key-pair
```

You will be prompted for a password (set one and remember it; it's needed to use the key in CI).

Expected: `cosign.key` and `cosign.pub` written to `~/cosign-zirconium-new/`.

- [ ] **Step 2: Set the GitHub Actions secret**

```bash
cd ~/cosign-zirconium-new
gh secret set SIGNING_SECRET --repo pbonh/zirconium --body "$(cat cosign.key)"
```

Then set the password as a separate secret (BlueBuild's reusable workflow expects it as `COSIGN_PASSWORD` if your key has a password):

```bash
gh secret set COSIGN_PASSWORD --repo pbonh/zirconium --body 'YOUR_KEY_PASSWORD_HERE'
```

Expected: `gh secret list --repo pbonh/zirconium` shows both `SIGNING_SECRET` and `COSIGN_PASSWORD`.

- [ ] **Step 3: Copy the new public key into the repo**

```bash
cd /home/phillip/Boxes/Homes/DotDev/Code/github.com/pbonh/zirconium
cp ~/cosign-zirconium-new/cosign.pub cosign.pub
cat cosign.pub
```

Expected: file present, prints a `-----BEGIN PUBLIC KEY-----` block.

- [ ] **Step 4: Update `.gitignore` to prevent re-committing the private key**

Read the existing `.gitignore`, then append:

```bash
cat >> .gitignore <<'EOF'

# Cosign — never commit private keys
cosign.key
cosign.key.b64
cosign.key.*

# BlueBuild local build artifacts
.bluebuild/
EOF
```

Expected: `.gitignore` ends with the cosign + bluebuild entries.

- [ ] **Step 5: Verify the private key is NOT in the working tree**

```bash
ls cosign.key cosign.key.b64 2>&1
```

Expected: "No such file or directory" for both. (They still exist in git history from previous commits — that's why we rotated. They will be removed from the working tree in Phase 4.)

- [ ] **Step 6: Commit the new public key and gitignore changes**

```bash
git add cosign.pub .gitignore
git commit -m "Rotate cosign key; ignore private key files

Generates a new cosign keypair. Public key committed; private key
stored only as the SIGNING_SECRET GitHub Actions secret with
COSIGN_PASSWORD for the password. Old key files are now compromised
(they remain in git history) and will be removed from the working
tree in the wipe step."
```

Expected: commit succeeds.

- [ ] **Step 7: Securely destroy the local copy of the new private key**

```bash
shred -u ~/cosign-zirconium-new/cosign.key
rmdir ~/cosign-zirconium-new
```

Expected: directory gone. The only copy of the new private key now lives in GitHub Secrets.

---

## Phase 4: Wipe mkosi infrastructure and reset submodules

Destructive phase. Removes every file the audit identified as inherited or no-longer-needed, and resets `.gitmodules` to keep only what we need going forward. The audit report from Phase 2 is the source of truth for what to keep under `mkosi.extra/usr/bin/` and `assets/`.

### Task 4.1: Stage user-owned content for relocation

Before wiping, copy out any USER-ADDED or kept USER-OVERRIDE content that needs to survive into a temp staging area.

**Files:**
- Create: `/tmp/zirconium-staging/` (temporary, not committed)

- [ ] **Step 1: Create staging directory**

```bash
rm -rf /tmp/zirconium-staging
mkdir -p /tmp/zirconium-staging/{usr-bin,systemd-user,scripts}
```

- [ ] **Step 2: Stage user-owned scripts from `mkosi.extra/usr/bin/`**

For each script the audit classified as USER-ADDED or kept USER-OVERRIDE in `mkosi.extra/usr/bin/`:

```bash
# Repeat for each script the audit said to keep:
cp mkosi.extra/usr/bin/<scriptname> /tmp/zirconium-staging/usr-bin/
```

Expected: only the user-owned scripts end up in staging.

- [ ] **Step 3: Stage chezmoi systemd unit files**

```bash
find mkosi.extra -path '*systemd/user*' -name 'chezmoi*' -exec cp {} /tmp/zirconium-staging/systemd-user/ \;
ls /tmp/zirconium-staging/systemd-user/
```

Expected: `chezmoi-apply.service` and `chezmoi-apply.timer` (or whatever they're named in your repo) present.

- [ ] **Step 4: Save the personal flatpak preinstall list as a reference for Phase 10**

```bash
cp mkosi.extra/usr/share/flatpak/preinstall.d/apps.preinstall /tmp/zirconium-staging/scripts/apps.preinstall.ref
cp mkosi.extra/usr/share/flatpak/preinstall.d/zirconium.preinstall /tmp/zirconium-staging/scripts/zirconium.preinstall.ref
```

Expected: both files copied; you'll consult them when writing `recipes/05-flatpaks.yml`.

### Task 4.2: Wipe mkosi infrastructure files and directories

- [ ] **Step 1: Remove mkosi config files at the repo root**

```bash
git rm -r mkosi.conf mkosi.conf.d mkosi.profiles mkosi.extra mkosi.tools mkosi.tools.manifest mkosi.bump mkosi.clean mkosi.postinst.chroot mkosi.prepare.chroot mkosi.version mkosi.keys mkosi.cache cache .mkosi-private
```

Expected: all listed paths removed from index. (`mkosi.cache` and `cache` may not exist; if `git rm` errors on missing paths, drop them from the command.)

- [ ] **Step 2: Remove the `repos/` directory and `subprojects/`**

```bash
git rm -r repos subprojects
```

Expected: removed.

- [ ] **Step 3: Remove ISO build configs and S3-related files**

```bash
git rm iso.toml iso-nvidia.toml artifacthub-repo.yml
```

Expected: removed.

- [ ] **Step 4: Remove the old workflows**

```bash
git rm .github/workflows/build-standard.yaml .github/workflows/build-nvidia.yaml .github/workflows/build-rawhide.yaml .github/workflows/reusable-build.yaml .github/workflows/build-disk.yml
```

Expected: removed. The `.github/workflows/` directory may now be empty; that's fine — Phase 12 adds the new workflow.

- [ ] **Step 5: Remove the legacy guide files at root**

```bash
git rm REBASE_GUIDE.md SIGNATURE_FIX.md
```

Expected: removed.

- [ ] **Step 6: Remove the compromised cosign private key files**

```bash
git rm cosign.key cosign.key.b64
```

Expected: removed from working tree. (They remain in git history — that's the point of rotating.)

- [ ] **Step 7: Verify the working tree state**

```bash
git status
ls
```

Expected: only `.git/`, `.github/` (possibly empty `workflows/`), `.gitignore`, `.gitmodules`, `.editorconfig`, `LICENSE`, `Justfile` (still old contents — replaced in Phase 12), `README.md` (still old — replaced in Phase 12), `cosign.pub`, `audit-report.txt`, `scripts/audit-vs-upstream.sh`, `docs/`, `assets/` (if kept), `mkosi.extra/usr/share/zirconium/zdots/` (will be relocated next).

### Task 4.3: Reset submodules

- [ ] **Step 1: Read current `.gitmodules`**

```bash
cat .gitmodules
```

Expected output (from spec):

```
[submodule "assets"]
        path = assets
        url = https://github.com/pbonh/assets.git
[submodule "mkosi.extra/usr/share/zirconium/zdots"]
        path = mkosi.extra/usr/share/zirconium/zdots
        url = https://github.com/pbonh/zdots.git
[submodule "subprojects/ublue-brew"]
        path = subprojects/ublue-brew
        url = https://github.com/ublue-os/brew
[submodule "subprojects/bluefin-common"]
        path = subprojects/bluefin-common
        url = https://github.com/projectbluefin/common
```

- [ ] **Step 2: Deinit and remove the submodules being dropped**

```bash
git submodule deinit -f subprojects/ublue-brew subprojects/bluefin-common
rm -rf .git/modules/subprojects
```

Expected: submodules deinitialized; their cached metadata removed from `.git/modules/`. (The directories themselves were already removed by `git rm -r subprojects` in Task 4.2.)

- [ ] **Step 3: Relocate the zdots submodule from `mkosi.extra/usr/share/zirconium/zdots` to `zdots`**

```bash
git submodule deinit -f mkosi.extra/usr/share/zirconium/zdots
git rm mkosi.extra/usr/share/zirconium/zdots
rm -rf .git/modules/mkosi.extra
git submodule add https://github.com/pbonh/zdots.git zdots
```

Expected: `zdots/` directory created at repo root with the submodule contents; `.gitmodules` updated.

- [ ] **Step 4: Drop the `assets` submodule if the audit said so; otherwise leave it**

If audit decision was "drop":

```bash
git submodule deinit -f assets
git rm assets
rm -rf .git/modules/assets
```

If audit decision was "keep": no action needed — `assets/` stays as-is.

- [ ] **Step 5: Verify `.gitmodules` contains only the kept submodules**

```bash
cat .gitmodules
```

Expected: contains the `zdots` entry (URL `https://github.com/pbonh/zdots.git`, path `zdots`), and optionally the `assets` entry. No `subprojects/*` or `mkosi.extra/*` entries.

- [ ] **Step 6: Commit the wipe + submodule reset as a single commit**

```bash
git add -A
git status  # double-check nothing unexpected is staged
git commit -m "Wipe mkosi infrastructure and reset submodules

Removes all mkosi.* config, mkosi.profiles, mkosi.extra (preserved
user-owned content is staged in /tmp/zirconium-staging for
re-introduction under files/system in later phases), repos/,
subprojects/, ISO configs, old workflows, the legacy guide files,
and the compromised cosign private key files.

Submodules: dropped subprojects/ublue-brew and subprojects/bluefin-common;
relocated mkosi.extra/usr/share/zirconium/zdots → zdots/ (URL unchanged
at https://github.com/pbonh/zdots.git); assets submodule [kept|dropped]
per audit decision."
```

Expected: commit succeeds. Edit the `assets` parenthetical to reflect your audit decision.

---

## Phase 5: Scaffold BlueBuild

### Task 5.1: Create the directory structure and the top-level recipe

**Files:**
- Create: `recipes/recipe.yml`
- Create: `files/system/usr/bin/.gitkeep` (placeholder so the dir is tracked)
- Create: `files/system/usr/lib/systemd/user/.gitkeep`
- Create: `files/scripts/.gitkeep`

- [ ] **Step 1: Create the directory skeleton**

```bash
mkdir -p recipes files/system/usr/bin files/system/usr/lib/systemd/user files/scripts
touch files/system/usr/bin/.gitkeep files/system/usr/lib/systemd/user/.gitkeep files/scripts/.gitkeep
```

Expected: directories present, `.gitkeep` files in each leaf so git tracks empty dirs.

- [ ] **Step 2: Write `recipes/recipe.yml`**

Create `recipes/recipe.yml` with this exact content:

```yaml
---
name: zirconium
description: Personal customization layer on top of zirconium-dev/zirconium, built with BlueBuild
base-image: ghcr.io/zirconium-dev/zirconium
image-version: latest

modules:
  - from-file: 01-extra-repos.yml
  - from-file: 02-extra-packages.yml
  - from-file: 03-dotfiles.yml
  - from-file: 04-custom-scripts.yml
  - from-file: 05-flatpaks.yml
  - from-file: 06-extra-tooling.yml
```

- [ ] **Step 3: Validate the partial recipe (will fail because module files don't exist yet)**

```bash
bluebuild validate recipes/recipe.yml || true
```

Expected: validation fails with errors about the missing `from-file` modules. That's correct — we add them in subsequent phases.

- [ ] **Step 4: Commit the scaffold**

```bash
git add recipes/ files/
git commit -m "Scaffold BlueBuild recipe structure

Adds recipes/recipe.yml pointing at ghcr.io/zirconium-dev/zirconium
as base, with from-file references to six module files (added
in subsequent phases). Creates the files/system and files/scripts
directory skeleton."
```

Expected: commit succeeds.

---

## Phase 6: Recipe 01 — extra repos

Enables the third-party RPM repos and COPRs that upstream zirconium does not already have. Cross-reference `mkosi.conf.d/pbonh-brave.conf`, `pbonh-copr.conf`, and `pbonh-docker.conf` (deleted in Phase 4 but visible in git history at the `legacy-mkosi-v1` tag if you need to re-check).

**Repos this layer needs to enable** (from the spec and the `pbonh-*.conf` files inspected during brainstorming):
- COPR `atim/starship`
- COPR `scottames/ghostty`
- COPR `wezfurlong/wezterm-nightly`
- 3rd-party YUM repo `brave-browser` (`https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo`)
- 3rd-party YUM repo `docker-ce-stable` (`https://download.docker.com/linux/fedora/docker-ce.repo`)

If any of these are already enabled by upstream zirconium (check by inspecting `/etc/yum.repos.d/` in the upstream image, or by checking the audit report from Phase 2), drop the duplicate from the list.

### Task 6.1: Write recipes/01-extra-repos.yml

**Files:**
- Create: `recipes/01-extra-repos.yml`

- [ ] **Step 1: Write the module file**

Create `recipes/01-extra-repos.yml` with this content:

```yaml
---
modules:
  - type: dnf
    repos:
      copr:
        - atim/starship
        - scottames/ghostty
        - wezfurlong/wezterm-nightly
      files:
        - https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        - https://download.docker.com/linux/fedora/docker-ce.repo
```

- [ ] **Step 2: Validate just this module file**

The `dnf` module accepts a `repos:` block with no `install:` — it will simply enable the repos and exit.

```bash
bluebuild validate recipes/recipe.yml
```

Expected: validation may still fail because recipes 02–06 aren't written yet. Look for errors specific to `01-extra-repos.yml`. If the only errors are about missing 02–06, this file is good.

- [ ] **Step 3: Commit**

```bash
git add recipes/01-extra-repos.yml
git commit -m "Add recipe 01: extra repos (COPRs + Brave + Docker)

Enables atim/starship, scottames/ghostty, wezfurlong/wezterm-nightly
COPRs plus the official Brave and Docker CE yum repos. Upstream
zirconium does not include these, so they belong in the customization
layer."
```

---

## Phase 7: Recipe 02 — extra packages

Installs every RPM the user adds on top of upstream. Cross-reference the deleted `mkosi.conf.d/pbonh-extras.conf`, `pbonh-brave.conf`, `pbonh-copr.conf`, and `pbonh-docker.conf` (visible at the `legacy-mkosi-v1` tag).

**Package list** (consolidated from the four `pbonh-*.conf` files plus the new Zed addition):

```
# Browsers
brave-browser

# Terminals
ghostty
wezterm
kitty

# Editor
neovim
zed                  # NEW — from Terra (already enabled by upstream)

# Shell
starship
zsh

# CLI tools
fd-find
ripgrep
ansible

# Containers
distrobox
fuse
fuse3

# Docker
docker-ce
docker-ce-cli
containerd.io
docker-buildx-plugin
docker-compose-plugin

# Dev tools
glibc-devel
libstdc++-devel
gcc-g++
make

# Node.js (needed by the AI CLIs in Phase 11)
nodejs
npm

# Desktop apps
libreoffice
thunderbird

# Science
octave
```

If any of these are already installed by upstream (check the upstream image), drop the duplicate.

### Task 7.1: Write recipes/02-extra-packages.yml

**Files:**
- Create: `recipes/02-extra-packages.yml`

- [ ] **Step 1: Write the module file**

Create `recipes/02-extra-packages.yml` with this content:

```yaml
---
modules:
  - type: dnf
    install:
      packages:
        # Browsers
        - brave-browser
        # Terminals
        - ghostty
        - wezterm
        - kitty
        # Editors
        - neovim
        - zed
        # Shell
        - starship
        - zsh
        # CLI tools
        - fd-find
        - ripgrep
        - ansible
        # Containers
        - distrobox
        - fuse
        - fuse3
        # Docker
        - docker-ce
        - docker-ce-cli
        - containerd.io
        - docker-buildx-plugin
        - docker-compose-plugin
        # Dev tools
        - glibc-devel
        - libstdc++-devel
        - gcc-g++
        - make
        # Node.js (for AI CLIs in recipe 06)
        - nodejs
        - npm
        # Desktop apps
        - libreoffice
        - thunderbird
        # Science
        - octave
```

- [ ] **Step 2: Validate**

```bash
bluebuild validate recipes/recipe.yml
```

Expected: errors only for missing 03–06.

- [ ] **Step 3: Commit**

```bash
git add recipes/02-extra-packages.yml
git commit -m "Add recipe 02: extra packages

Installs all user-added RPMs on top of upstream zirconium. Includes
the new Zed entry (Terra package; Terra repo is already enabled
by upstream so no new repo entry is required). nodejs+npm are
included here because recipe 06 uses npm to install the AI CLIs
at build time."
```

---

## Phase 8: Recipe 03 — dotfiles staging and chezmoi systemd unit

Bakes the `zdots` submodule into the image at `/usr/share/zirconium/zdots/` (read-only) and installs the per-user systemd unit/timer that runs `chezmoi apply` from that path on first login and periodically thereafter.

### Task 8.1: Restore the chezmoi systemd unit files from staging

**Files:**
- Create: `files/system/usr/lib/systemd/user/chezmoi-apply.service` (from staging)
- Create: `files/system/usr/lib/systemd/user/chezmoi-apply.timer` (from staging)

- [ ] **Step 1: Verify the staged unit files exist and inspect them**

```bash
ls /tmp/zirconium-staging/systemd-user/
cat /tmp/zirconium-staging/systemd-user/*.service
cat /tmp/zirconium-staging/systemd-user/*.timer
```

Expected: the chezmoi service and timer printed. Note the exact filenames — they may be `chezmoi-apply.*`, `chezmoi-update.*`, or similar. Use the actual filenames in the next step.

- [ ] **Step 2: Copy the staged unit files into the BlueBuild file tree**

```bash
cp /tmp/zirconium-staging/systemd-user/* files/system/usr/lib/systemd/user/
ls files/system/usr/lib/systemd/user/
```

Expected: the unit files now under `files/system/usr/lib/systemd/user/`.

- [ ] **Step 3: If the unit files reference `/usr/share/zirconium/zdots/`, verify the path is correct**

```bash
grep -r 'zdots' files/system/usr/lib/systemd/user/
```

Expected: paths inside the units point at `/usr/share/zirconium/zdots/`. If not, edit the unit files so they do.

### Task 8.2: Write recipes/03-dotfiles.yml

**Files:**
- Create: `recipes/03-dotfiles.yml`

- [ ] **Step 1: Write the module file**

The `files` module mirrors `files/system/` into the image. Additionally, we copy the `zdots/` submodule directly into `/usr/share/zirconium/zdots/` via a separate `files` entry.

Create `recipes/03-dotfiles.yml` with this content:

```yaml
---
modules:
  - type: files
    files:
      - source: system
        destination: /
      - source: ../zdots
        destination: /usr/share/zirconium/zdots

  - type: systemd
    system:
      enabled: []
    user:
      enabled:
        - chezmoi-apply.timer
```

If your unit file is named differently (per the audit), substitute the correct timer name in `user.enabled`.

- [ ] **Step 2: Initialize the zdots submodule contents (so the build has files to copy)**

```bash
git submodule update --init zdots
ls zdots/ | head
```

Expected: zdots directory populated with chezmoi source files.

- [ ] **Step 3: Validate**

```bash
bluebuild validate recipes/recipe.yml
```

Expected: errors only for missing 04–06.

- [ ] **Step 4: Commit**

```bash
git add recipes/03-dotfiles.yml files/system/usr/lib/systemd/user/
git commit -m "Add recipe 03: dotfiles staging + chezmoi user timer

Copies the zdots submodule into /usr/share/zirconium/zdots/ and
ships the chezmoi-apply systemd user unit + timer that applies
dotfiles on first login and refreshes them periodically."
```

---

## Phase 9: Recipe 04 — custom scripts

Restores the audit-determined subset of `mkosi.extra/usr/bin/` scripts.

### Task 9.1: Restore staged scripts and write recipes/04-custom-scripts.yml

**Files:**
- Create: `files/system/usr/bin/<scriptname>` for each kept script
- Create: `recipes/04-custom-scripts.yml`

- [ ] **Step 1: Restore the scripts from staging**

```bash
ls /tmp/zirconium-staging/usr-bin/
cp /tmp/zirconium-staging/usr-bin/* files/system/usr/bin/
chmod +x files/system/usr/bin/*
ls -la files/system/usr/bin/
```

Expected: each user-owned script is present and executable.

- [ ] **Step 2: Remove the .gitkeep placeholder if scripts are present**

```bash
[ -f files/system/usr/bin/.gitkeep ] && [ -n "$(ls files/system/usr/bin/ | grep -v '^.gitkeep$')" ] && rm files/system/usr/bin/.gitkeep
```

Expected: `.gitkeep` removed if any real scripts are present.

- [ ] **Step 3: Write `recipes/04-custom-scripts.yml`**

Note: recipe 03 already includes a `files` module entry that mirrors `files/system/` into the image, which means the scripts you just placed will already be installed. This recipe file exists for clarity and as the place to add a `chmod`/`chown` `script` module entry if a script needs setuid or other special handling. If no special handling is needed, this recipe is essentially a no-op.

Create `recipes/04-custom-scripts.yml` with this content:

```yaml
---
# User-owned /usr/bin scripts are mirrored into the image by the files
# module in recipe 03. This recipe file is a placeholder for any scripts
# that need extra setup (chmod, chown, link creation) beyond the verbatim
# copy. If you don't need any of that, keep this empty modules list.
modules: []
```

- [ ] **Step 4: Validate**

```bash
bluebuild validate recipes/recipe.yml
```

Expected: errors only for missing 05–06.

- [ ] **Step 5: Commit**

```bash
git add recipes/04-custom-scripts.yml files/system/usr/bin/
git commit -m "Add recipe 04: custom /usr/bin scripts

Restores the user-owned scripts from mkosi.extra/usr/bin per the
audit. The scripts are mirrored into the image by recipe 03's files
module; this recipe file is a placeholder for any scripts that
require special handling (currently none)."
```

---

## Phase 10: Recipe 05 — flatpak preinstalls

Translates `mkosi.extra/usr/share/flatpak/preinstall.d/apps.preinstall` (the user's personal flatpak list) into BlueBuild's `default-flatpaks` module. The `zirconium.preinstall` file appears to be upstream content (Ignition, GNOME TextEditor, Bazaar) — drop unless the audit said keep.

### Task 10.1: Write recipes/05-flatpaks.yml

**Files:**
- Create: `recipes/05-flatpaks.yml`

- [ ] **Step 1: Confirm the flatpak list from the staged reference**

```bash
cat /tmp/zirconium-staging/scripts/apps.preinstall.ref
```

Expected: list of `[Flatpak Preinstall <app-id>]` entries.

- [ ] **Step 2: Write the module file**

Create `recipes/05-flatpaks.yml` with this content (translates the entries from `apps.preinstall`):

```yaml
---
modules:
  - type: default-flatpaks
    notify: true
    system:
      repo:
        url: https://flathub.org/repo/flathub.flatpakrepo
        name: flathub
      install:
        # Password Manager
        - com.bitwarden.desktop
        # Containers
        - io.github.DenysMb.Kontainer
        - io.github.dvlv.boxbuddyrs
        # Office
        - com.collaboraoffice.Office
        # AI
        - com.jeffser.Alpaca
        # Notes
        - md.obsidian.Obsidian
        # Calculators
        - org.kde.cantor
        - org.kde.kalgebra
        - io.github.Qalculate
        # Terminals
        - app.devsuite.Ptyxis
        # Media
        - org.kde.plasmatube
        # Cloud
        - com.github.zocker_160.SyncThingy
```

- [ ] **Step 3: Validate**

```bash
bluebuild validate recipes/recipe.yml
```

Expected: errors only for missing 06.

- [ ] **Step 4: Commit**

```bash
git add recipes/05-flatpaks.yml
git commit -m "Add recipe 05: flatpak preinstalls

Translates the personal apps.preinstall list (Bitwarden, Kontainer,
BoxBuddy, Collabora, Alpaca, Obsidian, Cantor, KAlgebra, Qalculate,
Ptyxis, Plasmatube, SyncThingy) into the default-flatpaks module.
Drops the upstream-supplied zirconium.preinstall list (Ignition,
GNOME TextEditor, Bazaar) — those are already in the base image."
```

---

## Phase 11: Recipe 06 — Cursor + AI CLI install scripts

Two install scripts are invoked at build time by the `script` module: one downloads the Cursor AppImage, extracts the `.desktop` and icons, and installs to `/opt/cursor/`; the other npm-installs the three AI coding CLIs.

### Task 11.1: Write files/scripts/install-cursor.sh

**Files:**
- Create: `files/scripts/install-cursor.sh`

- [ ] **Step 1: Write the script**

Create `files/scripts/install-cursor.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Installs Cursor from the official AppImage.
# Extracts the .desktop file and icons so Cursor shows up in the launcher,
# installs the AppImage under /opt/cursor/, and creates a /usr/bin/cursor
# wrapper that exec's the AppImage.

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  CURSOR_ARCH=x64   ;;
    aarch64) CURSOR_ARCH=arm64 ;;
    *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac

# Cursor's official "stable, latest" download endpoint.
# If this URL changes upstream, the build fails — that's intentional;
# we want a loud failure rather than silently producing an image without Cursor.
DOWNLOAD_URL="https://api2.cursor.sh/updates/api/download/stable/linux-${CURSOR_ARCH}/cursor"

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "==> Downloading Cursor AppImage from $DOWNLOAD_URL"
curl -fL --retry 3 --retry-delay 5 -o cursor.AppImage "$DOWNLOAD_URL"
chmod +x cursor.AppImage

echo "==> Extracting AppImage contents"
./cursor.AppImage --appimage-extract >/dev/null
test -d squashfs-root || { echo "AppImage extraction produced no squashfs-root" >&2; exit 1; }

echo "==> Installing AppImage to /opt/cursor/"
mkdir -p /opt/cursor
cp cursor.AppImage /opt/cursor/cursor.AppImage
chmod 0755 /opt/cursor/cursor.AppImage

echo "==> Installing .desktop file"
DESKTOP_SRC="$(find squashfs-root -maxdepth 3 -name '*.desktop' | head -n1)"
test -n "$DESKTOP_SRC" || { echo "No .desktop file found in AppImage" >&2; exit 1; }
mkdir -p /usr/share/applications
sed -e 's|^Exec=.*|Exec=/usr/bin/cursor %F|' \
    -e 's|^Icon=.*|Icon=cursor|' \
    -e 's|^TryExec=.*|TryExec=/usr/bin/cursor|' \
    "$DESKTOP_SRC" > /usr/share/applications/cursor.desktop
chmod 0644 /usr/share/applications/cursor.desktop

echo "==> Installing icons"
ICONS_INSTALLED=0
for size in 16 24 32 48 64 96 128 256 512; do
    SRC=$(find squashfs-root -path "*${size}x${size}*" -name '*.png' 2>/dev/null | head -n1)
    if [ -n "$SRC" ] && [ -f "$SRC" ]; then
        DEST=/usr/share/icons/hicolor/${size}x${size}/apps
        mkdir -p "$DEST"
        cp "$SRC" "$DEST/cursor.png"
        ICONS_INSTALLED=$((ICONS_INSTALLED + 1))
    fi
done
if [ "$ICONS_INSTALLED" -eq 0 ]; then
    # Fallback: any PNG icon at the AppImage root
    FALLBACK=$(find squashfs-root -maxdepth 2 -name '*.png' | head -n1)
    if [ -n "$FALLBACK" ]; then
        DEST=/usr/share/icons/hicolor/256x256/apps
        mkdir -p "$DEST"
        cp "$FALLBACK" "$DEST/cursor.png"
        ICONS_INSTALLED=1
    fi
fi
[ "$ICONS_INSTALLED" -gt 0 ] || { echo "No icons found in AppImage" >&2; exit 1; }
echo "    installed $ICONS_INSTALLED icon size(s)"

echo "==> Creating /usr/bin/cursor wrapper"
cat > /usr/bin/cursor <<'WRAPPER'
#!/usr/bin/env bash
exec /opt/cursor/cursor.AppImage --no-sandbox "$@"
WRAPPER
chmod 0755 /usr/bin/cursor

echo "==> Cursor installation complete"
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x files/scripts/install-cursor.sh
```

### Task 11.2: Write files/scripts/install-ai-clis.sh

**Files:**
- Create: `files/scripts/install-ai-clis.sh`

- [ ] **Step 1: Write the script**

Create `files/scripts/install-ai-clis.sh` with this content. Versions are pinned per the spec's mitigation against yanked-latest disruption — bump them by editing this file when you want updates:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Installs three AI coding CLIs system-wide via npm.
# Versions are pinned to insulate against an upstream yank or a
# typosquat slipping through; bump them deliberately when you want
# to update.
#
# WARNING: bare-name `claude`, `codex`, and `pi` packages on npm
# are NOT the AI CLIs — they are unrelated/typosquat packages.
# Always use the scoped/owner-prefixed names below.

PACKAGES=(
    "@anthropic-ai/claude-code@2.1.123"
    "@openai/codex@0.125.0"
    "@mariozechner/pi-coding-agent@0.70.6"
)

command -v npm >/dev/null || { echo "npm not found; recipe 02 must install nodejs+npm" >&2; exit 1; }

for pkg in "${PACKAGES[@]}"; do
    echo "==> Installing $pkg"
    npm install -g --no-fund --no-audit "$pkg"
done

echo "==> Verifying binaries on PATH"
for bin in claude codex pi; do
    BIN_PATH=$(command -v "$bin") || { echo "Binary '$bin' not found after install" >&2; exit 1; }
    echo "    $bin -> $BIN_PATH"
done

echo "==> AI CLI installation complete"
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x files/scripts/install-ai-clis.sh
```

### Task 11.3: Write recipes/06-extra-tooling.yml

**Files:**
- Create: `recipes/06-extra-tooling.yml`

- [ ] **Step 1: Remove the `files/scripts/.gitkeep` placeholder**

```bash
[ -f files/scripts/.gitkeep ] && rm files/scripts/.gitkeep
```

- [ ] **Step 2: Write the module file**

Create `recipes/06-extra-tooling.yml` with this content:

```yaml
---
modules:
  - type: script
    snippets:
      - "echo '==> Running install-cursor.sh'"
    scripts:
      - install-cursor.sh
      - install-ai-clis.sh
```

The `script` module looks for the named scripts under `files/scripts/` relative to the recipe directory.

- [ ] **Step 3: Validate the full recipe — should now pass**

```bash
bluebuild validate recipes/recipe.yml
```

Expected: validation passes (no errors). If it fails, read the error carefully — most likely a YAML indentation issue or a typo'd module type.

- [ ] **Step 4: Render the Containerfile to inspect what BlueBuild generates**

```bash
bluebuild generate recipes/recipe.yml
ls -la Containerfile 2>/dev/null || ls -la .bluebuild/
```

Expected: a `Containerfile` (or under `.bluebuild/`) with the rendered build instructions. Quick spot-check: the Containerfile should `FROM ghcr.io/zirconium-dev/zirconium:latest`, install your package list, copy your `files/system/` tree, run `install-cursor.sh` and `install-ai-clis.sh`.

- [ ] **Step 5: Commit**

```bash
git add files/scripts/install-cursor.sh files/scripts/install-ai-clis.sh recipes/06-extra-tooling.yml
git commit -m "Add recipe 06: Cursor AppImage + AI CLI install scripts

install-cursor.sh downloads the latest Cursor AppImage at build time,
extracts the .desktop and icons, installs to /opt/cursor with a
/usr/bin/cursor wrapper. install-ai-clis.sh npm-installs the three
scoped AI coding CLI packages (@anthropic-ai/claude-code, @openai/codex,
@mariozechner/pi-coding-agent) at pinned versions. Both invoked
by the script module in recipes/06-extra-tooling.yml."
```

---

## Phase 12: CI workflow + Justfile + README

### Task 12.1: Write the BlueBuild workflow

**Files:**
- Create: `.github/workflows/build.yml`

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/build.yml` with this content:

```yaml
---
name: build
on:
  push:
    branches:
      - main
      - bluebuild
  pull_request:
    branches:
      - main
  schedule:
    - cron: '0 1 * * 2'   # Tuesday 01:00 UTC
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
      COSIGN_PASSWORD: ${{ secrets.COSIGN_PASSWORD }}
```

(The `bluebuild` branch is included in the trigger so the migration build runs before fast-forwarding `main`.)

- [ ] **Step 2: Verify the workflow file parses as YAML**

```bash
python3 -c 'import yaml,sys; yaml.safe_load(open(".github/workflows/build.yml"))' && echo OK
```

Expected: `OK` printed.

### Task 12.2: Write the Justfile

**Files:**
- Modify: `Justfile` (full rewrite)

- [ ] **Step 1: Replace the Justfile with the new BlueBuild-oriented content**

Overwrite the existing `Justfile` with this content:

```makefile
default: build

# Build the image locally (requires bluebuild CLI: cargo install --locked bluebuild)
build:
    bluebuild build recipes/recipe.yml

# Render the Containerfile without building (useful for inspecting what BlueBuild generates)
generate:
    bluebuild generate recipes/recipe.yml

# Lint the rendered Containerfile + recipe
lint:
    bluebuild validate recipes/recipe.yml

# Rebase a running Fedora atomic system to the locally-built image
switch-local:
    sudo bootc switch --transport containers-storage localhost/zirconium:latest

# Rebase to the published GHCR image (normal install/update path)
switch-remote:
    sudo bootc switch ghcr.io/pbonh/zirconium:latest

# Initialize all submodules (zdots, optionally assets)
submodule-init:
    git submodule update --init --recursive

# Clean local build artifacts
clean:
    podman image rm -f localhost/zirconium:latest 2>/dev/null || true
    rm -rf .bluebuild/
```

### Task 12.3: Write the README

**Files:**
- Modify: `README.md` (full rewrite)

- [ ] **Step 1: Replace the README**

Overwrite the existing `README.md` with this content:

```markdown
# zirconium

Personal customization layer on top of [zirconium](https://github.com/zirconium-dev/zirconium), built with [BlueBuild](https://blue-build.org).

Upstream zirconium provides niri (tiling Wayland compositor), DankMaterialShell, the Fedora-bootc base, and the broader desktop session. This image adds:

- **Browsers:** Brave
- **Terminals:** Ghostty, WezTerm-nightly, Kitty
- **Editors:** Neovim, [Zed](https://zed.dev) (via Terra), [Cursor](https://cursor.com) (via AppImage)
- **AI coding CLIs:** `claude` ([Claude Code](https://www.npmjs.com/package/@anthropic-ai/claude-code)), `codex` ([OpenAI Codex CLI](https://www.npmjs.com/package/@openai/codex)), `pi` ([Pi coding agent](https://www.npmjs.com/package/@mariozechner/pi-coding-agent))
- **Container/dev tooling:** Docker CE, distrobox, Node.js, gcc/make, Ansible
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
```

### Task 12.4: Validate everything and commit

- [ ] **Step 1: Re-validate the recipe**

```bash
bluebuild validate recipes/recipe.yml
```

Expected: passes.

- [ ] **Step 2: Render the Containerfile and skim it**

```bash
bluebuild generate recipes/recipe.yml
```

Expected: a Containerfile is produced. Skim for:
- `FROM ghcr.io/zirconium-dev/zirconium:latest`
- `dnf install` lines for each package
- `COPY files/system/ /` (or equivalent)
- Invocations of the two install scripts

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml Justfile README.md
git commit -m "Add BlueBuild CI workflow, Justfile, README

Single workflow calls BlueBuild's reusable build-and-publish action;
multi-arch (amd64+arm64) is on by default. Justfile shrinks to ~15
lines wrapping bluebuild CLI commands. README documents install
(bootc switch), update (bootc upgrade/rollback), signature verification
(cosign), and local build."
```

---

## Phase 13: Local CI dry run

Confirm the recipe builds end-to-end on your local machine before pushing.

### Task 13.1: Local end-to-end build

**Files:**
- No file changes; build verification only.

- [ ] **Step 1: Run a full local build**

```bash
just clean
just build 2>&1 | tee /tmp/zirconium-local-build.log
```

Expected: `bluebuild build` produces `localhost/zirconium:latest`. Build is long (~10–30 minutes for first run). On failure, read `/tmp/zirconium-local-build.log` and diagnose:
- DNF errors (missing repo, missing package) → fix in recipes 01/02
- Cursor download failure → check `install-cursor.sh`'s URL still works
- npm errors → check pinned versions in `install-ai-clis.sh` are still on the registry
- `chezmoi-apply.timer` not found → check the unit file actually copied into `files/system/`

- [ ] **Step 2: Inspect the resulting image**

```bash
podman images | grep zirconium
podman run --rm localhost/zirconium:latest /usr/bin/cursor --version 2>&1 | head
podman run --rm localhost/zirconium:latest claude --version 2>&1 | head
podman run --rm localhost/zirconium:latest codex --version 2>&1 | head
podman run --rm localhost/zirconium:latest pi --version 2>&1 | head
podman run --rm localhost/zirconium:latest zed --version 2>&1 | head
podman run --rm localhost/zirconium:latest brave-browser --version 2>&1 | head
```

Expected: each binary responds with a version (or at least exits cleanly). `cursor --version` may not work in a container without a display; if it errors with a display-related message, that's OK — verify in Phase 15.

- [ ] **Step 3: No commit needed for this phase**

The build verification doesn't change tracked files.

---

## Phase 14: Push branch and let GHA build

### Task 14.1: Push and monitor the workflow

**Files:**
- No file changes.

- [ ] **Step 1: Push the bluebuild branch**

```bash
git push origin bluebuild
```

Expected: push succeeds; GHA `build` workflow triggers automatically.

- [ ] **Step 2: Watch the workflow run**

```bash
gh run list --branch bluebuild --limit 1
gh run watch
```

Expected: workflow runs through; on success, image published to `ghcr.io/pbonh/zirconium:latest` (and signed). On failure, fix and re-push.

- [ ] **Step 3: Verify the published image and its signature**

```bash
podman pull ghcr.io/pbonh/zirconium:latest
cosign verify --key cosign.pub ghcr.io/pbonh/zirconium:latest
```

Expected: image pulls; signature verification reports the expected entries.

---

## Phase 15: Boot test in a VM

### Task 15.1: Boot the new image

**Files:**
- No file changes.

- [ ] **Step 1: Set up a Fedora atomic test VM**

If you don't have one: download the latest Fedora Silverblue ISO, install in a libvirt/qemu VM with at least 30GB disk and 4GB RAM. Or use an existing test VM.

- [ ] **Step 2: Inside the VM, switch to the new image**

```bash
sudo bootc switch ghcr.io/pbonh/zirconium:latest
sudo systemctl reboot
```

Expected: reboot completes; the new image is the active deployment.

- [ ] **Step 3: Log into a niri session and verify**

After login, open a terminal and check:

```bash
which cursor claude codex pi zed
cursor --version
claude --version
codex --version
pi --version
zed --version
brave-browser --version
docker --version
```

Expected: all binaries on PATH and report versions.

- [ ] **Step 4: Verify Cursor in the launcher**

Open the application launcher (DMS): "Cursor" should appear with its icon.

- [ ] **Step 5: Verify dotfiles applied**

```bash
systemctl --user status chezmoi-apply.timer
ls ~/.config | head        # should show your zdots-managed configs
```

Expected: timer is active; configs from zdots are in `~/.config`.

- [ ] **Step 6: Verify flatpaks installed**

```bash
flatpak list --app | head
```

Expected: bitwarden, obsidian, etc. listed.

- [ ] **Step 7: Verify image signature on the running system**

```bash
sudo bootc status
```

Expected: shows the current image source as `ghcr.io/pbonh/zirconium:latest` with a verified signature reference.

- [ ] **Step 8: If anything is wrong, return to earlier phases and iterate**

Common failures and which phase to revisit:
- Missing package → Phase 7 (recipe 02)
- Missing repo → Phase 6 (recipe 01)
- Dotfiles not applied → Phase 8 (recipe 03; check unit file paths and contents)
- Cursor not in launcher → Phase 11 (`install-cursor.sh`; the .desktop extraction may have failed silently — check the build log)
- AI CLI not on PATH → Phase 11 (`install-ai-clis.sh`; check the npm install succeeded)

---

## Phase 16: Fast-forward main

The new image boots and verifies. Time to flip `main`.

### Task 16.1: Fast-forward main and clean up

**Files:**
- No file changes; git operations only.

- [ ] **Step 1: Make sure your local main is up to date**

```bash
git checkout main
git pull origin main
```

Expected: local main matches remote.

- [ ] **Step 2: Fast-forward main to bluebuild**

```bash
git merge --ff-only bluebuild
```

Expected: fast-forward succeeds. If git refuses (because main has diverged), STOP and investigate before forcing anything.

- [ ] **Step 3: Push the fast-forwarded main**

```bash
git push origin main
```

Expected: push succeeds; the GHA workflow runs again on main, publishing `ghcr.io/pbonh/zirconium:latest` from the main branch (which now points at the same commit as bluebuild).

- [ ] **Step 4: Optionally remove the audit script and report**

The `audit-report.txt` and `scripts/audit-vs-upstream.sh` were useful during the migration; you can remove them now that main is on bluebuild. Or keep them as historical reference — your call.

```bash
git rm audit-report.txt scripts/audit-vs-upstream.sh
git commit -m "Remove migration audit artifacts (kept as reference in legacy-mkosi-v1)"
git push origin main
```

- [ ] **Step 5: (Optional) Best-effort scrub of the old cosign key from history**

The old `cosign.key` and `cosign.key.b64` are still present in the history of the `legacy-mkosi-v1` tag and the `legacy-mkosi` branch. You already rotated, so this is best-effort cleanup. If you want to scrub:

```bash
# Use git-filter-repo (safer than the deprecated filter-branch):
pip install --user git-filter-repo

git clone --mirror https://github.com/pbonh/zirconium.git /tmp/zirconium-mirror
cd /tmp/zirconium-mirror
git filter-repo --path cosign.key --path cosign.key.b64 --invert-paths
# Force-push the cleaned mirror back. THIS REWRITES HISTORY for legacy-mkosi-v1
# and legacy-mkosi. Anyone else with clones will need to re-clone.
git push --force --all
git push --force --tags
```

This is destructive and rewrites pushed history. Only do it if you understand the consequences. The keys are already compromised; the public repo's commit history retention plus any forks/clones means scrubbing is best-effort, not a guarantee. Most people skip this step.

- [ ] **Step 6: Migration done**

```bash
git log --oneline -5
git branch -a
```

Expected: main now contains all the bluebuild work; `legacy-mkosi` and `legacy-mkosi-v1` still exist as references to the pre-migration state; the `bluebuild` branch can be deleted at your leisure (`git push origin --delete bluebuild`) or kept as a no-op.

---

## Self-Review

**Spec coverage check:**
- Goals (image at `ghcr.io/pbonh/zirconium`, signed, multi-arch via BlueBuild reusable, niri+DMS inherited, Brave/Ghostty/WezTerm/Docker/Zed/Cursor/AI CLIs added, dotfiles applied, install via bootc switch) → covered by Phases 6–15.
- Non-goals (no nvidia, no ISO, no S3, no backwards compat) → covered by NOT having tasks for these things; Phase 4 wipe explicitly removes nvidia/ISO/S3 artifacts.
- Architecture (base image, modular recipes, repo layout) → Phase 5 + Phases 6–11.
- Submodule disposition (drop ublue-brew + bluefin-common, keep zdots, audit assets) → Phase 4.
- Dotfiles application (chezmoi systemd unit, zdots baked at /usr/share/zirconium/zdots) → Phase 8.
- Module mapping (mkosi → BlueBuild) → Phases 6–11 follow the table.
- Audit step → Phase 2 (gating precondition).
- CI workflow → Phase 12.
- Justfile → Phase 12.
- README outline → Phase 12.
- Security (cosign key rotation) → Phase 3.
- Migration sequencing → Phase ordering follows spec's 15-step list.
- Risks (upstream cadence, audit accuracy, chezmoi unit collision, custom-scripts provenance, assets fate, Cursor URL stability, npm fragility, typosquat) → addressed in audit (Phase 2), validation steps in Phases 11/13/15, and explicit warnings in `install-ai-clis.sh`.

**Placeholder scan:** No "TBD"/"TODO"/"add appropriate X"/"similar to Task N" entries. Every script is provided in full. The two deferred decisions (`assets` keep/drop, custom-scripts subset) are resolved in Phase 2 by the audit before Phase 4 needs them.

**Type/name consistency:**
- Recipe filenames `01-extra-repos.yml` ... `06-extra-tooling.yml` referenced consistently in `recipes/recipe.yml`, in each phase, and in the README.
- Cosign secret names `SIGNING_SECRET` + `COSIGN_PASSWORD` referenced consistently in Phase 3 and the workflow.
- `chezmoi-apply.timer` is the unit name used in `recipes/03-dotfiles.yml`; Task 8.1 step 1 instructs the engineer to verify the actual filename and substitute if different.
- npm package names (`@anthropic-ai/claude-code`, `@openai/codex`, `@mariozechner/pi-coding-agent`) referenced consistently in `install-ai-clis.sh`, the spec, and the README.
- Image reference `ghcr.io/pbonh/zirconium:latest` consistent across workflow, Justfile, README, install steps.

Plan is internally consistent and covers the spec.
