# Cosign Signature Verification Fix

## Problem

After rotating the cosign key pair, `bootc upgrade` and `podman pull` fail with:

```
error: Upgrading: Preparing import: Fetching manifest: failed to invoke method OpenImage:
A signature was required, but no signature exists
```

## Root Cause

Two issues combined to break signature verification:

1. **Missing registries.d entry** -- The tmpfiles.d config (`99-zirconium-factory.conf`) created a symlink for `zirconium-dev.yaml` but the actual factory file is named `pbonh.yaml`. Without this file, `containers/image` does not know to look for sigstore attachments in the registry and instead checks the local sigstore directory (where nothing exists).

2. **Key rotation chicken-and-egg** -- The running system's `policy.json` requires `sigstoreSigned` verification for `ghcr.io/pbonh`, but after a key rotation the running system may not have the new public key yet. The new image contains the correct key, but you need the key to trust the new image.

## Workaround (applied 2026-04-15)

### Step 1: Create the missing registries.d config

```bash
sudo tee /etc/containers/registries.d/pbonh.yaml <<'EOF'
docker:
  ghcr.io/pbonh:
    use-sigstore-attachments: true
EOF
```

### Step 2: Temporarily relax the signature policy

```bash
sudo python3 -c "
import json
with open('/etc/containers/policy.json') as f:
    p = json.load(f)
p['transports']['docker']['ghcr.io/pbonh'] = [{'type': 'insecureAcceptAnything'}]
with open('/etc/containers/policy.json', 'w') as f:
    json.dump(p, f, indent=4)
"
```

### Step 3: Upgrade

```bash
sudo bootc upgrade
```

After reboot, the new image will have:
- The correct `pbonh.yaml` in registries.d (via the fixed tmpfiles.d entry)
- The new cosign public key at `/usr/share/pki/containers/zirconium.pub`
- The original `sigstoreSigned` policy restored

### Step 4: Restore signature policy (after reboot into new image)

The reboot restores the factory `policy.json` via tmpfiles.d, so no manual action is needed. Verify with:

```bash
cat /etc/containers/policy.json | jq '.transports.docker["ghcr.io/pbonh"]'
```

Expected output:
```json
[
  {
    "type": "sigstoreSigned",
    "keyPaths": [
      "/usr/share/pki/containers/zirconium.pub",
      "/usr/share/pki/containers/jackrabbit.pub",
      "/usr/share/pki/containers/hawaii.pub"
    ],
    "signedIdentity": {
      "type": "matchRepository"
    }
  }
]
```

## Permanent Fix

The tmpfiles.d entry was corrected in this commit:

**File:** `mkosi.extra/usr/lib/tmpfiles.d/99-zirconium-factory.conf`

```diff
-L+ /etc/containers/registries.d/zirconium-dev.yaml
+L+ /etc/containers/registries.d/pbonh.yaml
```

This ensures future image builds materialize the correct registries.d config on first boot.
