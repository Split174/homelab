# AGENTS.md

Guidelines and context for AI agents working in this homelab repository.

## Project Overview

This is a **Kubernetes homelab** managed by **Flux CD** (GitOps). The cluster is provisioned with **k0s** (see `00-k0s-init/k0sctl.yml`) and runs on a single node named `gilfoyle`.

- **Git repo**: `ssh://git@github.com/Split174/homelab.git` (branch `master`)
- **Flux sync interval**: GitRepository every 1m, Kustomizations every 10m
- **Kubeconfig**: stored at `./.private-files/gilfoyle.yaml` (gitignored)
- **CLI tools used**: `flux`, `kubectl`, `kustomize`, `sops`, `helm`, `make`

## Repository Layout

```
homelab/
├── .private-files/          # gitignored — kubeconfig, age key, etc.
├── .sops.yaml               # sops config (age encryption rules)
├── .gitignore               # hides *secret*.yaml, keeps *secret*.enc.yaml
├── Makefile                  # diagnostic targets (debug, status, reconcile…)
├── README.md
├── AGENTS.md
├── 00-k0s-init/             # k0s cluster bootstrap (k0sctl.yml)
└── 01-flux/
    └── gilfoyle/
        ├── flux-system/      # Flux bootstrap (gotk-components, sync, apps Kustomization)
        └── apps/             # all applications live here
            ├── kustomization.yaml   # enables/disables apps
            ├── grafana/
            ├── victoria-logs/
            ├── cert-manager/
            ├── cloudnative-pg/
            ├── haproxy-ingress/     # ingress controller (class: haproxy)
            ├── local-path-storage/  # local-path provisioner
            ├── metallb/
            ├── envoy-gateway/
            ├── zot/
            ├── …etc
```

## How Flux Works Here

1. **`flux-system` Kustomization** — bootstraps Flux itself and creates a `GitRepository` pointing at this repo.
2. **`apps` Kustomization** (`apps.yaml`) — watches `./01-flux/gilfoyle/apps/` path and applies everything recursively. This Kustomization has **SOPS decryption** configured, so encrypted secrets are decrypted on-the-fly by Flux using the `sops-age` key stored in `flux-system` namespace.
3. Each app directory is a self-contained Flux-managed unit referenced from `apps/kustomization.yaml`.

## Adding a New Application

Each app directory under `01-flux/gilfoyle/apps/` typically contains:

| File | Purpose |
|---|---|
| `namespace.yaml` | `Namespace` resource |
| `helm-repo.yaml` | `HelmRepository` (for Helm-based apps) |
| `helm-release.yaml` | `HelmRelease` with all values |
| `kustomization.yaml` | assembles the resources |
| `secret.enc.yaml` | encrypted secrets (optional) |
| `ingress.yaml` | standalone Ingress (optional, if not inlined in helm-release) |

To enable an app, add it to `apps/kustomization.yaml`. To disable, comment it out.

### Conventions

- **Ingress class**: `haproxy` (not nginx)
- **TLS**: `cert-manager.io/cluster-issuer: "letsencrypt"` annotation on ingresses
- **Storage**: `local-path` storage class for persistent volumes (single-node, use `strategy: Recreate`)
- **HelmRelease API**: `helm.toolkit.fluxcd.io/v2`

## Secrets Management

Secrets are **encrypted at rest in Git** using [SOPS](https://github.com/getsops/sops) with **age** encryption. Flux decrypts them in-cluster via its built-in SOPS provider.

### Architecture

```
┌──────────────────┐     ┌────────────────────────┐
│  Developer laptop│     │  Kubernetes cluster     │
│                  │     │                         │
│  sops encrypt ───┼────►│  GitRepository sync     │
│  .enc.yaml files │     │        │                │
│                  │     │        ▼                │
│                  │     │  Kustomization (apps)   │
│                  │     │  decryption: sops       │
│                  │     │  secretRef: sops-age ───┼──► age key secret
│                  │     │        │                │    (flux-system ns)
│                  │     │        ▼                │
│                  │     │  Secrets decrypted and  │
│                  │     │  applied to cluster     │
└──────────────────┘     └────────────────────────┘
```

### Configuration Files

- **`.sops.yaml`** — defines encryption rules: all files matching `.*\.enc\.yaml$` are encrypted with the age public key. Only `data` and `stringData` fields are encrypted (`encrypted_regex`).
- **`.gitignore`** — pattern `*secret*.yaml` blocks plain secrets, while `!*secret*.enc.yaml` allows encrypted versions through.

### Secret Naming Convention

| Pattern | Meaning |
|---|---|
| `secret.enc.yaml` | Encrypted secret (committed to Git) |
| `secret.yaml` | Plain-text secret (gitignored, **never commit**) |

### Workflow: Creating a New Secret

1. **Write the plain-text secret** in `secret.enc.yaml` under the app directory:

```yaml
apiVersion: v1
kind: Secret
metadata:
    name: myapp-secret
    namespace: myapp
type: Opaque
stringData:
    api-key: my-super-secret-value
```

2. **Encrypt in-place**:

```bash
export SOPS_AGE_KEY_FILE=<path/to/age>/age.key
sops --encrypt --in-place 01-flux/gilfoyle/apps/myapp/secret.enc.yaml
```

3. **Edit an existing encrypted secret**:

```bash
sops 01-flux/gilfoyle/apps/myapp/secret.enc.yaml
# opens $EDITOR with decrypted content; saves re-encrypted
```

4. **Add to kustomization** if not already there:

```yaml
resources:
  - secret.enc.yaml
```

5. **Commit and push** — Flux will decrypt and apply automatically.

### Important Rules

- **Never commit plain-text secrets.** The `.gitignore` provides a safety net, but always double-check with `git diff --staged`.
- The age private key lives **only** in `flux-system` namespace (as `sops-age` secret) and on the developer's machine at the path referenced by `SOPS_AGE_KEY_FILE`.
- All encrypted secrets use the **same age public key** defined in `.sops.yaml`.

## Useful Commands

```bash
# Full Flux diagnostic
make debug

# Force Flux reconciliation
make reconcile

# Check a specific HelmRelease
make check-helm

# Local kustomize lint (catches YAML/patch errors before pushing)
make lint

# Edit an encrypted secret
export SOPS_AGE_KEY_FILE=<path/to/age>/age.key
sops 01-flux/gilfoyle/apps/<app>/secret.enc.yaml
```

## Notes

- Some apps are commented out in `apps/kustomization.yaml` (e.g., `metallb`, `envoy-gateway`, `ntfy`) — they are disabled but kept in the repo for future use.
- The `Makefile` sets `KUBECONFIG` to `./.private-files/gilfoyle.yaml` automatically for all targets.
- When working with Helm charts, always check the chart's actual `values.yaml` (e.g., on GitHub) for supported fields — the chart README may lag behind.
