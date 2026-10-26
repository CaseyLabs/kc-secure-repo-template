# kc-secure-repo-template

**A security-hardened repository template for new GitHub projects.**

- [Features](#features)
- [Example Output](#example-output)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
  - [Setup](#setup)
  - [Usage](#usage)
- [Repository Layout](#repository-layout)
- [Documentation](#documentation)
- [Repo Options](#repo-options)
  - [Kubernetes Support](#kubernetes-k8s-support)
  - [AI Agents Commands](#ai-agents-commands)
  - [Dependency Updates](#dependency-updates)
  - [Security Scanners](#security-scanners)

---

## Overview

This repo template includes the following default options out of the box:

### Security

- Scanning for vulnerabilities, misconfigurations, and leaked secrets (including Git history)
- Reproducible builds with pinned SHA checksums to help prevent supply-chain attacks [[1]](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions)

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

---

### Setup

- Place your source code into the `src/` folder
- Then customize the following files to fit your project/code base:
  - `config/project.cfg`
  - `Dockerfile`
  - `scripts/*.sh`

---

### Usage

```shell
# Main Commands
make build    # builds the project as a container image
make test     # run code linters, tests, and source build in the container image
make run      # runs the container
make stop     # stops the container

# Misc Commands
make clean    # Removes project outputs, caches, images, and the example container
make shell    # Opens a shell in the running container
make status   # show the local image and running containers
make logs     # show logs from running containers
make scan     # run security and secret scanning
make update   # Updates the pinned SHA checksums in `./config/lockfile.cfg`
make renovate # Runs self-hosted Renovate for this repository
make dist     # build release artifacts to `./dist`
make k8s      # lint/render/package Helm chart in `./config/k8s/chart`
make k8s-test-local # server-side dry-run using a pinned kubectl image and your kubeconfig
make infra    # build/test/plan Terraform config from `./config/infra`
```

---

## Repository Layout

```text
.
├── AGENTS.md                 # Repo-specific AI agent guidance
├── Makefile                  # For all `make` commands
├── Dockerfile                # Default nonroot dev/CI container image
├── docs/                     # Project documentation
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

## Documentation

- [Template Overview](docs/README.md)
  - [Customize Template](docs/customize-template.md)
  - [Build Commands](docs/build-commands.md)
  - [Security Model](docs/security-model.md)
  - [Github Actions CI/CD](docs/github-ci.md)
  - [GitOps Naming Conventions](docs/gitops-conventions.md)
    - [Release and Packaging](docs/release-and-packaging.md)
    - [Dependency Updates](docs/dependency-updates.md)
  - [AI Agent Support](docs/ai-agent-support.md)
  - [Terraform Support](docs/terraform.md)
  - [Kubernetes Support](docs/k8s.md)

---

## Repo Options

### Kubernetes (`k8s`) Support

Usage:

```shell
make k8s    # lint/render/package Helm chart in `./config/k8s/chart`
```

- Keep Kubernetes-owned static assets in `config/k8s/`

---

### AI Agents Commands

This project includes Agentic commands and skills that can be used by AI CLI tools such as Codex CLI, Claude Code, etc.

Example commands:

```text
# Perform a code review, based on the checklist in `.agents/code_review.md`:
/review             

 # Perform a security audit of the repo, using `.agents/skills/repo-security-review`:
$repo-security-review   
```

---

### Dependency Updates

This template also uses third-party tools to automate the upgrade of project images/tools/dependencies via Pull Requests:

- [dependabot](https://docs.github.com/en/code-security/tutorials/secure-your-dependencies/dependabot-quickstart-guide): will update GitHub Actions pins in workflows
  - `.github/dependabot.yml`
- [renovate](https://github.com/renovatebot/renovate): will update any tools listed in `config/project.cfg`
  - `.github/renovate.json`
  - `.github/workflows/renovate.yml`
  *Note*: Renovate requires a GitHub App to be installed in order to operate. To create one, run:
  ```shell
  .github/renovate/setup-github-app.sh
  ```
  - If you do not wish to use Renovate in your repo:
    - set `DEV_SCAN_ENABLE_RENOVATE=false` in `config/project.cfg`.

---

### Security Scanners

This project uses the following open-source tools as part of its security scanning workflows. Each one covers a job the others do not:

- [actionlint](https://github.com/rhysd/actionlint): lints GitHub Actions workflow files, including `run:` scripts through its bundled shellcheck.
  - Why: catches broken expressions, invalid keys, and shell quoting bugs before a workflow runs.
- [betterleaks](https://github.com/betterleaks/betterleaks): scans the repository, including Git history when available, for leaked secrets (the maintained successor to gitleaks).
  - Why: catches secrets locally and in pull requests, before GitHub's server-side secret scanning and push protection would see them.
- [grype](https://github.com/anchore/grype): scans the generated SBOM for known vulnerabilities during release builds, and weekly for published releases.
  - Why: release evidence includes a vulnerability report, and newly disclosed CVEs in already-published releases still surface.
- [syft](https://github.com/anchore/syft): generates SBOM output for release artifacts.
  - Why: the SBOM lists the pinned GitHub Actions and Terraform provider shipped in the template archive, and is what grype scans.
- [trivy](https://github.com/aquasecurity/trivy): scans Dockerfiles, the Terraform under `config/infra`, and rendered Kubernetes manifests for misconfigurations.
  - Why: none of the other tools check infrastructure posture. It runs offline from its bundled checks; reviewed suppressions live in `config/.trivyignore`.
- [zizmor](https://github.com/zizmorcore/zizmor): scans GitHub Actions workflows for security footguns.
  - Why: rejects unpinned actions, privileged triggers, template injection, and broad token permissions. `scripts/workflow-policy.sh` adds only the template rules zizmor does not cover.

See [docs/security-model.md](docs/security-model.md) for when a derived repository should add more scanners.
