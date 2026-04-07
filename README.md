# kc-secure-repo-template

Security-hardened, container-first template for new GitHub repositories.

It is meant to stay:

- language-agnostic by default
- Docker-first for build, test, lint, scan, and release
- small in public interface
- reproducible and reviewable by default
- safe for GitHub-hosted CI

It is not meant to become an application framework or kitchen-sink dev environment.

## What You Get

- Nonroot dev and CI containers
- Small stable root `Makefile` interface
- Pinned images and pinned GitHub Action SHAs
- Secret scanning and workflow policy checks
- Reproducible release archive generation
- Optional SBOM, vulnerability scan, checksums, and GitHub artifact attestation
- Bundled examples:
  - `src/` Go hello-world demo used by `make example`
  - `config/infra/` Terraform GitHub repository hardening workspace

## Requirements

- Docker
- GNU `make`
- `bash` or `zsh`
- standard POSIX tools available on a typical Linux/macOS/WSL host

For `make update`, also install the host helpers it uses directly: `awk`, `curl`, `jq`, `perl`, `sed`, `tr`, and `head`.

## Quick Start

```sh
git clone --depth 1 https://github.com/CaseyLabs/kc-secure-repo-template
cd kc-secure-repo-template
PROJECT_ENV=project.env.example make example
```

`make example` exercises the bundled `src/` demo and runs the template security and workflow checks without forcing you to customize the template first.

## Public Interface

The root `Makefile` is the main entrypoint:

```sh
make build    # build the bundled dev image
make test     # run lint and tests for the bundled src workflow
make run      # start the bundled src container
make stop     # stop the bundled src container
make status   # show the local image and running containers
make logs     # show logs from running containers
make clean    # remove caches, artifacts, and local images
make shell    # open a shell in the container
make update   # refresh checked-in lock/checksum values
make example  # run the bundled Go demo plus scan checks
make infra    # build/test/plan the bundled infra workspace
make scan     # run template security and workflow checks
make dist     # build release artifacts and integrity outputs
```

Template-maintainer validation paths:

```sh
sh scripts/test.sh template
sh scripts/test.sh smoke
```

## First-Hour Setup

Use this sequence after creating a repository from the template.

1. Validate the baseline:

```sh
PROJECT_ENV=project.env.example make example
PROJECT_ENV=project.env.example make dist
```

2. Create your real config:

```sh
cp project.env.example project.env
```

3. Update `project.env` with your project values. At minimum review:

- `PROJECT_NAME`
- `PROJECT_IMAGE`
- `DEV_BASE_IMAGE`

4. Update [`Dockerfile`](Dockerfile) so the dev image includes your project toolchain.

5. Replace the bundled example implementation with your real project workflow in the existing top-level scripts and Docker image:

- [`Dockerfile`](Dockerfile)
- [`scripts/build.sh`](scripts/build.sh)
- [`scripts/test.sh`](scripts/test.sh)
- [`scripts/run.sh`](scripts/run.sh)
- [`scripts/stop.sh`](scripts/stop.sh)
- [`scripts/scan.sh`](scripts/scan.sh)
- [`scripts/dist.sh`](scripts/dist.sh)

6. Add or update `.github/CODEOWNERS` if you want code-owner review enforcement.

7. Verify your customized path:

```sh
make build
PROJECT_ENV=project.env make scan
PROJECT_ENV=project.env make dist
```

If your repository has a real runtime path, also verify:

```sh
make test
make run
make stop
```

8. After the repo exists on GitHub, apply the repository hardening settings below.

9. Remove or replace template-only content you do not want to keep, such as `src/`, `config/infra/`, and any bundled example logic in the root `scripts/`.

## Configuration Model

The main customization point is [`project.env.example`](project.env.example), copied to `project.env`.

The checked-in `project.env` file is for local validation in this template repository. Release archives and derived repositories should start from `project.env.example`.

The split is intentional:

- `project.env.example`: reviewed selectors, versions, and defaults
- [`config/lockfile.env`](config/lockfile.env): reviewed digest locks and checksum-like values maintained by `make update`

Important groups:

- Build/runtime:
  - `PROJECT_NAME`, `PROJECT_IMAGE`, `PROJECT_DOCKERFILE`
  - `DEV_BASE_IMAGE`
  - `DEV_PACKAGE_SNAPSHOT_LOCK`
  - `DEV_TERRAFORM_IMAGE`
- Scanners:
  - `DEV_SCAN_GITLEAKS_IMAGE`
  - `DEV_SCAN_SYFT_IMAGE`
  - `DEV_SCAN_GRYPE_IMAGE`
- Release controls:
  - `ENABLE_SBOM`
  - `ENABLE_GRYPE`
  - `GRYPE_FAIL_ON`
  - `RELEASE_INTEGRITY_TARGET`
  - `RELEASE_INTEGRITY_DIST_DIR`
  - `RELEASE_INTEGRITY_NAME`
  - `RELEASE_INTEGRITY_VERSION`

Rules worth keeping:

- `ENABLE_GRYPE=true` requires `ENABLE_SBOM=true`.
- Run `make update` after changing checked-in selector/version values in `project.env.example`.
- `make update` also refreshes the README workflow allowlist section and the pinned Terraform image/provider references used by the bundled infra example.
- The `DEV_SCAN_*` selectors are reviewed tags in `project.env.example`; `make update` resolves them into digest-pinned `*_LOCK` values in [`config/lockfile.env`](config/lockfile.env), and scan/dist use those lock values directly.
- `DEV_PACKAGE_SNAPSHOT_LOCK` in [`config/lockfile.env`](config/lockfile.env) is intentionally reviewed state, not a value regenerated from wall clock time.

## Adapting The Dev Image

Keep normal workflows container-first. Derived repositories should extend the root [`Dockerfile`](Dockerfile), not switch back to host-installed toolchains.

Typical profiles:

### Go

Use a pinned Go image or install a pinned Go toolchain explicitly. The bundled `src/` demo shows the default pattern.

Example project task scripts:

```sh
cd src && go build -trimpath -buildvcs=false ./cmd/app
go test ./src/...
test -z "$(gofmt -l .)" && go vet ./src/...
go run ./src/cmd/app
mkdir -p dist && cd src && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -buildvcs=false -ldflags="-s -w" -o ../dist/app-linux-amd64 ./cmd/app
```

Put those commands into the existing root workflow scripts and `Dockerfile` for your derived repository.

### Node.js

Prefer a pinned `node:<version>-bookworm-slim` base image, run as nonroot, and default installs to `npm ci --ignore-scripts`.

Example project task scripts:

```sh
npm ci --ignore-scripts && npm run build
npm ci --ignore-scripts && npm test
npm ci --ignore-scripts && npm run lint
npm ci --ignore-scripts && npm run dev
mkdir -p dist && npm ci --ignore-scripts && npm pack --pack-destination dist
```

Put those commands into the matching root workflow scripts for your repository.

If the repo is heavily Node-focused and can adopt `pnpm`, prefer `pnpm install --frozen-lockfile --ignore-scripts` and use release-age gates such as `minimumReleaseAge` with narrow exclusions for internal scopes only.

### SQL-Focused Repositories

Add the exact database client, formatter, or linter you need. Keep CI validation deterministic and release packaging reproducible.

## Infra Example

`make infra` exercises the bundled [`config/infra`](config/infra) workspace.

Default behavior:

- Terraform-only
- nonroot container flow only
- uses `GITHUB_TOKEN` from the environment for authenticated GitHub operations

Typical usage:

```sh
make infra
APPLY=true GITHUB_TOKEN=... make infra
```

The baseline covers repository creation and a minimal GitHub hardening posture: PRs, approvals, rulesets, vulnerability alerts, Dependabot security updates, and force-push/deletion restrictions.

The checked-in example currently verifies and pins:

- Terraform image `hashicorp/terraform:1.14.8` pinned to `hashicorp/terraform:1.14.8@sha256:42ecfb253183ec823646dd7859c5652039669409b44daa72abf57112e622849a`
- GitHub provider `integrations/github` with `= 6.11.1`

## Release Integrity

`make dist` creates:

- a reproducible release archive
- release-integrity outputs under `dist/`

The archive path is normalized and reproducible:

- canonical file manifest
- stable ordering
- normalized ownership and timestamps
- `SOURCE_DATE_EPOCH` support
- `gzip -n` to suppress variable gzip metadata

Optional integrity controls:

- Syft SBOM generation
- Grype vulnerability scanning
- `SHA256SUMS`
- `SECURITY-ANALYSIS.md` compliance report
- GitHub artifact attestation in the release workflow

The default scan target is the built tarball in `dist/`, not the mutable working tree. Evidence files such as SBOMs, vulnerability reports, and `SECURITY-ANALYSIS.md` are execution-specific audit artifacts, not reproducible build outputs.

## GitHub Hardening Checklist

Apply these settings after creating the GitHub repository:

1. Mark it as a template if you want direct reuse.
2. Protect `main` or the default branch with pull requests required.
3. Require at least one approval.
4. Require code owner review.
5. Require status checks for `build`, `test`, and `scan`.
6. Disable force pushes and branch deletion.
7. Enable secret scanning and push protection.
8. Enable dependency graph, Dependabot alerts, and Dependabot security updates.
9. Restrict Actions to approved actions and reusable workflows if your org supports it.
10. Keep default `GITHUB_TOKEN` permissions minimal.
11. Protect release tags like `v*`.
12. Treat workflow changes, release-path changes, dependency manifests, and lockfiles as high-scrutiny reviews.
13. For Node repositories, keep install scripts opt-in and avoid unpinned `npx` in automation.

If your org uses an Actions allowlist, permit the exact SHAs currently used by the template workflows:

### Current Actions

- `actions/attest-build-provenance@a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32`
- `actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd`
- `actions/upload-artifact@bbbca2ddaa5d8feaa63e36b76fdaad77386f024f`

### Allowlist Guidance

Keep the allowlist minimal, re-pin exact SHAs when you intentionally update Actions, and verify each SHA against the reviewed upstream release tag.

## Security Posture

The template aims for reviewable defaults, not magical security.

Current enforced baseline:

- GitHub Actions pinned to full commit SHAs
- reviewed upstream-tag comments for pinned actions
- `actions/checkout` with `persist-credentials: false`
- minimal top-level workflow permissions
- workflow lint plus action pin policy checks
- digest-pinned container/image inputs for the checked-in path
- nonroot container execution for normal workflows

Still your responsibility in derived repositories:

- pin and review language-level dependencies
- review lockfile diffs carefully
- keep GitHub repository settings aligned with the checklist above
- avoid weakening runtime privileges or allowing unreviewed fetch-and-exec automation

## Repository Layout

```text
.
├── AGENTS.md                 # Repo-specific agent guidance and workflow rules
├── README.md                 # Main template documentation and setup flow
├── LICENSE.md                # Template license
├── code_review.md            # Review checklist used for /review-style audits
├── Makefile                  # Stable public entrypoint for local and CI workflows
├── Dockerfile                # Default nonroot dev/CI container image
├── .dockerignore             # Keeps caches and generated artifacts out of build context
├── .gitignore                # Ignores local artifacts, caches, and generated outputs
├── project.env.example       # Reviewed example configuration for derived repositories
├── project.env               # Checked-in local validation config for this template repo
├── config/
│   ├── lockfile.env          # Digest locks and reviewed checksum-like values
│   ├── tests/                # Test fixtures/helpers for template validation paths
│   └── infra/                # Bundled Terraform example for GitHub repo hardening
│       ├── README.md         # Infra-specific usage notes
│       ├── Dockerfile        # Infra container image definition
│       ├── versions.tf       # Terraform and provider version constraints
│       ├── providers.tf      # Provider configuration
│       ├── main.tf           # Repository hardening resources
│       └── terraform.tfvars.example  # Example input values for the infra workspace
├── .agents/
│   └── skills/               # Repo-local agent skills for template-specific tasks
├── scripts/                  # Implementation behind the root Makefile targets
├── src/                      # Small Go example used by `make example`
│   ├── README.md             # Example-specific usage notes
│   ├── go.mod                # Go module definition for the bundled demo
│   └── cmd/app/              # Minimal example application entrypoint
└── .github/
    ├── dependabot.yml        # Dependency update policy for GitHub-managed updates
    └── workflows/            # CI, scan, test, build, and release workflows
```
