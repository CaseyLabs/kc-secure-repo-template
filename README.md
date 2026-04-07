# kc-secure-repo-template

**A security-hardened repository template for new GitHub projects.**

## Features

- Nonroot containers for local development and CI workflows
- Secret and vulnerability scanning
- GitHub Actions CI workflow templates
- Terraform configs for creating new repos
- AI Agentic Coding template files
- Reproducible builds with pinned SHA checksums to help prevent supply-chain attacks <sup>[[1]](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions)</sup>

## Example Output

```shell
> make example

==> Build summary
Image: kc-secure-template-example:local
Env File: ./project.env
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

cp project.env.example project.env
make example    # Builds/tests/runs an example container
```

## Setup

- Place your source code into the `src/` folder

- Then customize the following files to fit your project/code base:

  - `project.env`
  - `Dockerfile`
  - `scripts/*.sh`

## Usage

```shell
# Main Commands:
make build    # builds the project as a container image
make test     # run code linters and tests built container image
make run      # runs the container
make stop     # stops the contaner

# Misc Commands:
make clean    # Removes all previously running containers
make shell    # Opens a shell in the running container
make status   # show the local image and running containers
make logs     # show logs from running containers
make update   # Updates the pinned SHA checksums
make scan     # run security scans and workflow checks
make dist     # build release artifacts
make infra    # build/test/plan the Terraform config
```

## Repository Layout

```text
.
├── AGENTS.md                 # Repo-specific AI agent guidance
├── code_review.md            # Repo-specific AI agent `/review` checklist
├── project.env               # Project environment variables
├── Makefile                  # For all `make` commands
├── Dockerfile                # Default nonroot dev/CI container image
├── src/                      # Project source code (built into a container)
├── scripts/                  # Scripts used by the Makefile
├── config/
│   ├── lockfile.env          # Pinned SHA checksums for project tooling
│   └── infra/                # Terraform example for GitHub repo hardening
├── .github/
│   └── workflows/            # GitHub Actions workflows
└── .agents/
    └── skills/               # Repo-specific AI agent skills templates
```
