# kc-secure-repo-template

**A security-hardened repository template for new GitHub projects.**

<!-- TOC -->

- [Features](#features)
- [Example Output](#example-output)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
  - [Setup](#setup)
  - [Usage](#usage)
- [Repository Layout](#repository-layout)
- [Repo Options](#repo-options)
  - [Kubernetes Support](#kubernetes-k8s-support)
  - [AI Agents Commands](#ai-agents-commands)
  - [Dependency Updates](#dependency-updates)
  - [Security Scanners](#security-scanners)

<!-- /TOC -->

---

## Features

This repo template includes the following default options out of the box:

### Security

- Scanning for vulnerabilities, misconfigurations, and leaked secrets (including Git history)
- Reproducible builds with pinned SHA checksums to help prevent supply-chain attacks <sup>[[1]](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions)</sup>

### Developer Workflow

- Nonroot containers for local development and CI
- GitHub Actions CI workflow templates
- Automated dependency update checks
- AI agentic coding templates

### Infrastructure

- Optional Terraform and Kubernetes Helm scaffolding

---

## Example Output

```text
> make example

==> Build summary
Image: kc-secure-template-example:local
Project config: ./config/project.cfg
Source Code: ./src
Results:
  Container build: passed
  App build: passed
  Lint: passed
  Tests: passed
  Run: passed
  Security scan: passed
```

---

## Requirements

- Terminal shell (Linux, MacOS, or WSL)
- Docker

---

## Quick Start

In a Terminal, run the following:

```shell
git clone --depth 1 https://github.com/CaseyLabs/kc-secure-repo-template
cd kc-secure-repo-template

make example    # Builds/tests/runs an example container
```

### Setup

- Place your source code into the `src/` folder

- Then customize the following files to fit your project/code base:

  - `config/project.cfg`
  - `config/k8s/` if your project also needs the optional Kubernetes scaffold
  - `Dockerfile`
  - `scripts/*.sh`

### Usage

```shell
# Main Commands
make build    # builds the project as a container image
make test     # run code linters, tests, and source build in the container image
make run      # runs the container
make stop     # stops the contaner

# Misc Commands
make clean    # Removes all previously running containers
make shell    # Opens a shell in the running container
make status   # show the local image and running containers
make logs     # show logs from running containers
make scan     # run security and secret scanning
make update   # Updates the pinned SHA checksums in `./config/lockfile.cfg`
make renovate # Runs self-hosted Renovate for this repository
make dist     # build release artifacts to `./dist`
make k8s      # lint/render/package Helm chart in `./config/k8s/chart`
make k8s-test-local # build config/k8s/Dockerfile.k8s and run kubectl server-side dry-run with your kubeconfig
make infra    # build/test/plan Terraform config from `./config/infra`
```

---

## Repository Layout

```text
.
├── AGENTS.md                 # Repo-specific AI agent guidance
├── Makefile                  # For all `make` commands
├── Dockerfile                # Default nonroot dev/CI container image
├── src/                      # Project source code (built into a container)
├── scripts/                  # Scripts used by the Makefile
├── config/
│   ├── project.cfg           # Project configuration
│   ├── lockfile.cfg          # Pinned SHA checksums for project tooling
│   ├── k8s/                  # Optional Kubernetes Helm scaffold
│   └── infra/                # Terraform example for GitHub repo hardening
├── .github/
│   └── workflows/            # GitHub Actions workflows
└── .agents/
    ├── code_review.md        # Repo-specific AI agent `/review` checklist
    └── skills/               # Repo-specific AI agent skills templates
```

---

## Repo Options

### Kubernetes (`k8s`) Support

This template includes an optional Helm chart under `config/k8s/chart` for
derived repositories that deploy to Kubernetes.

Use:

```shell
make k8s
make k8s-test-local
```

That flow runs locally in a container and:

- lints the chart
- renders manifests
- packages the chart
- `make k8s-test-local` also builds `config/k8s/Dockerfile.k8s` and runs `kubectl apply --dry-run=server` against your current cluster context
- It does not contact a cluster or perform `helm install`
- Keep Kubernetes-owned static assets in `config/k8s/`

`make k8s` reads its main defaults from `config/project.cfg`, but explicit
`K8S_*` environment overrides still win. `K8S_VALUES_FILE`, `K8S_RENDER_DIR`,
and `K8S_PACKAGE_DIR` may point either inside the repository or at absolute
host paths outside it.

By default, the generated Helm release name and chart name are sanitized from
`PROJECT_NAME` into a DNS-safe Kubernetes name.

`make k8s-test-local` requires a real kubeconfig. By default it uses `~/.kube/config`.
You can point it at another file with `K8S_TEST_LOCAL_KUBECONFIG=/path/to/config`
and select a context with `K8S_TEST_LOCAL_CONTEXT=name`.

---

### AI Agents Commands

This project includes Agentic commands and skills that can be used by AI CLI tools such as Codex CLI, Claude Code, etc.

Example commands:

```text
/review             # Performs a code review, based on the checklist in `.agents/code_review.md`
$security-review    # Performs a security audit of the repo, using `.agents/skills/security-review`
```

---

### Dependency Updates

This template also uses third-party tools to automate the upgrade of project images/tools/dependencies via Pull Requests:

- [dependabot](https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/dependabot-quickstart-guide):
  - `.github/dependabot.yml`

- [renovate](https://github.com/renovatebot/renovate): will update any tools listed in `config/project.cfg`
  - `.github/renovate.json`
  - `.github/workflows/renovate.yml`

  _Note_: Renovate requires a GitHub App to be installed in order to operate. To create one, run:

  ```shell
  .github/renovate/setup-github-app.sh
  ```

  - If you do not wish to use Renovate in your repo:

    - set `DEV_SCAN_ENABLE_RENOVATE=false` in `config/project.cfg`.

---

### Security Scanners

This project uses the following open-source tools as part of its security scanning workflows:

- [actionlint](https://github.com/rhysd/actionlint): lints GitHub Actions workflow files.
- [gitleaks](https://github.com/gitleaks/gitleaks): scans the repository, including Git history when available, for leaked secrets.
- [grype](https://github.com/anchore/grype): scans the generated SBOM for known vulnerabilities during release builds.
- [syft](https://github.com/anchore/syft): generates SBOM output for release artifacts.
- [trivy](https://github.com/aquasecurity/trivy): scans for Dockerfile misconfigurations in the repository.
