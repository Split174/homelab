# AGENTS.md

Guidelines and mandatory instructions for AI agents working in this homelab repository.

## 🚨 CRITICAL: Use MCP Tools for Cluster Navigation 🚨

This repository is equipped with a custom **MCP Server for Flux/GitOps** (`flux-mcp-server`), running locally. 
**You MUST use these MCP tools to explore, navigate, and analyze the cluster structure.** 
DO NOT use generic tools like `rg`, `grep`, or `read_file` to search for resources across multiple directories. 

Use these tools first:
1. `list_resources` — Get an instant list of all resources (e.g., `kind: "HelmRelease"`) with file paths.
2. `get_flux_dependencies` — See what upstream Kustomizations/HelmReleases a resource depends on.
3. `get_resource_yaml` — Extract specific Kubernetes manifests.
4. `get_helm_values` — **Highly recommended.** Extracts ONLY the `spec.values` from a `HelmRelease`. Use this instead of reading massive helm-release YAML files to save context tokens and avoid parsing boilerplate.

**Example workflow:** To modify Grafana plugins, call `list_resources(kind="HelmRelease")` -> call `get_helm_values(name="grafana")` -> open the file using its path -> edit only the plugins section -> save.

### When to use MCP vs Built-in Zed File Editor:
- **EXPLORATION (Use MCP):** If you are asked to analyze dependencies, find which app uses a specific config, or summarize the cluster architecture, ALWAYS use `list_resources`, `get_flux_dependencies`, or `get_helm_values`.
- **DIRECT EDITING (Use Built-in Zed tools):** If the user asks for a simple, direct edit (e.g., "Change the domain in Zot", "Update chart version"), and you already know the file path (e.g., `apps/zot/helm-release.yaml`), **DO NOT** use MCP. Just use standard file reading/editing tools to quickly patch the file. MCP is read-only and using it before a known direct edit wastes context tokens.


---

## Project Overview

This is a **Kubernetes homelab** managed by **Flux CD** (GitOps). The cluster is provisioned with **k0s** (see `00-k0s-init/k0sctl.yml`) and runs on a single node named `gilfoyle`.

- **Git repo**: `ssh://git@github.com/Split174/homelab.git` (branch `master`)
- **Flux sync interval**: GitRepository every 1m, Kustomizations every 10m
- **Kubeconfig**: stored at `./.private-files/gilfoyle.yaml` (gitignored)
- **CLI tools used**: `flux`, `kubectl`, `kustomize`, `sops`, `helm`, `make`

## Repository Layout

```text
homelab/
├── .private-files/          # gitignored — kubeconfig, age key, etc.
├── .sops.yaml               # sops config (age encryption rules)
├── .gitignore               # hides *secret*.yaml, keeps *secret*.enc.yaml
├── Makefile                 # diagnostic targets (debug, status, reconcile…)
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
            ├── ...
```

## How Flux Works Here

1. **`flux-system` Kustomization** — bootstraps Flux itself and creates a `GitRepository` pointing at this repo.
2. **`apps` Kustomization** (`apps.yaml`) — watches `./01-flux/gilfoyle/apps/` path and applies everything recursively. This Kustomization has **SOPS decryption** configured. Encrypted secrets are decrypted on-the-fly using the `sops-age` key stored in the `flux-system` namespace.
3. **No Explicit DependsOn**: We generally don't use explicit `dependsOn` arrays. Flux applies resources in the order of their source dependencies. 

## Adding a New Application

Each app directory under `01-flux/gilfoyle/apps/` typically contains:

| File | Purpose |
|---|---|
| `namespace.yaml` | `Namespace` resource |
| `helm-repo.yaml` | `HelmRepository` (for Helm-based apps) |
| `helm-release.yaml` | `HelmRelease` with all values |
| `kustomization.yaml` | assembles the resources |
| `secret.enc.yaml` | encrypted secrets (optional) |
| `ingress.yaml` | standalone Ingress (if not inlined in helm-release) |

To enable an app, add it to `apps/kustomization.yaml`. To disable, comment it out.

### Conventions

- **Ingress class**: `haproxy` (not nginx)
- **TLS**: `cert-manager.io/cluster-issuer: "letsencrypt"` annotation on ingresses
- **Storage**: `local-path` storage class for persistent volumes (single-node, use `strategy: Recreate`)
- **HelmRelease API**: `helm.toolkit.fluxcd.io/v2`

## Secrets Management

Secrets are **encrypted at rest in Git** using [SOPS](https://github.com/getsops/sops) with **age** encryption. 

### Configuration Files

- **`.sops.yaml`** — defines encryption rules: all files matching `.*\.enc\.yaml$` are encrypted with the age public key. Only `data` and `stringData` fields are encrypted (`encrypted_regex`).
- **`.gitignore`** — pattern `*secret*.yaml` blocks plain secrets, while `!*secret*.enc.yaml` allows encrypted versions through.

### Secret Naming Convention

| Pattern | Meaning |
|---|---|
| `secret.enc.yaml` | Encrypted secret (committed to Git) |
| `secret.yaml` | Plain-text secret (gitignored, **never commit**) |

### Workflow: Editing or Creating Secrets

As an AI agent, you **cannot** execute `sops` directly in the terminal if it requires interactive `$EDITOR` access. 

To create or update a secret:
1. Write the **plain-text** YAML manifest.
2. Ask the human user to run `sops --encrypt --in-place <path-to-file.enc.yaml>` locally. 
3. **Never attempt to write plain-text directly into a `.enc.yaml` file** without asking the user to encrypt it via CLI before committing.
4. Always verify `git diff` to ensure no plain-text secrets leak into commits.

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
```

## Notes

- Some apps might be commented out in `apps/kustomization.yaml` (e.g., `metallb`, `envoy-gateway`). They are disabled but kept in the repo for future use.
- The `Makefile` sets `KUBECONFIG` to `./.private-files/gilfoyle.yaml` automatically for all targets.
- When configuring Helm charts, use `get_helm_values` MCP tool to analyze existing values, but always cross-reference fields with the upstream chart values structure if introducing new keys.
