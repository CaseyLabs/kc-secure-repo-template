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
- [Dependency Updates](#dependency-updates)
- [Agentic AI Commands](#agentic-ai-commands)
- [Third-Party Tools](#third-party-tools)

<!-- /TOC -->

## Features

- Nonroot containers for local development and CI workflows
- Secret, workflow, and Dockerfile misconfiguration scanning (including Git history)
- GitHub Actions CI workflow templates
- Terraform configs for creating new repos
- AI Agentic Coding template files
- Reproducible builds with pinned SHA checksums to help prevent supply-chain attacks <sup>[[1]](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions)</sup>

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

## Requirements

- Terminal shell (Linux, MacOS, or WSL)
- Docker

## Quick Start

In a Terminal, run the following:

```shell
git clone --depth 1 https://github.com/CaseyLabs/kc-secure-repo-template
cd kc-secure-repo-template

make example    # Builds/tests/runs an example container
```

## Setup

- Place your source code into the `src/` folder

- Then customize the following files to fit your project/code base:

  - `config/project.cfg`
  - `Dockerfile`
  - `scripts/*.sh`

## Usage

```shell
# Main Commands
make build    # builds the project as a container image
make test     # run code linters and tests built container image
make run      # runs the container
make stop     # stops the contaner

# Misc Commands
make clean    # Removes all previously running containers
make shell    # Opens a shell in the running container
make status   # show the local image and running containers
make logs     # show logs from running containers
make scan     # run security and secret scanning
make update   # Updates the pinned SHA checksums in `./config/lockfile.cfg`
make dist     # build release artifacts to `./dist`
make infra    # build/test/plan the Terraform config from `./config/infra`
```

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
│   └── infra/                # Terraform example for GitHub repo hardening
├── .github/
│   └── workflows/            # GitHub Actions workflows
└── .agents/
    ├── code_review.md        # Repo-specific AI agent `/review` checklist
    └── skills/               # Repo-specific AI agent skills templates
```

## Agentic AI Commands

This project includes Agentic commands and skills that can be used by AI CLI tools such as Codex CLI, Claude Code, etc.

Example commands:

```text
/review             # Performs a code review, based on the checklist in `.agents/code_review.md`

$security-review    # Performs a security audit of the repo, using `.agents/skills/security-review`
```

## Third-Party Tools

This project uses the following open-source tools as part of its security scanning workflows:

- [actionlint](https://github.com/rhysd/actionlint): lints GitHub Actions workflow files.
- [gitleaks](https://github.com/gitleaks/gitleaks): scans the repository, including Git history when available, for leaked secrets.
- [grype](https://github.com/anchore/grype): scans the generated SBOM for known vulnerabilities during release builds.
- [syft](https://github.com/anchore/syft): generates SBOM output for release artifacts.
- [trivy](https://github.com/aquasecurity/trivy): scans for Dockerfile misconfigurations in the repository.

### Optional: Renovate Tooling Upgrader

Renovate is a third-party tool that can be installed as a GitHub App in your repo:

- https://github.com/apps/renovate

When installed, Renovate will scan the tooling versions in `config/project.cfg`, and create automatically create pull requests for new tool/image releases.

- `.github/renovate.json` is configured to update tooling pins only in `config/project.cfg`
- Renovate runs `make update` to ensure pinned tools in `config/lockfile.cfg` stay updated

If you do not wish to use Renovate in your repo, set the following setting in `config/project.cfg`

`DEV_SCAN_ENABLE_RENOVATE=false`
