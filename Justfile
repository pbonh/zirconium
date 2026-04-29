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
