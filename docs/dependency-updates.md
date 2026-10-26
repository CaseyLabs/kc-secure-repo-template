# Dependency Update Guide

This template uses self-hosted Renovate for every dependency update pull
request. GitHub's Dependabot alerts stay enabled for detection only; Renovate
reads them to open vulnerability-fix PRs.

## What Renovate updates

Renovate is configured in `.github/renovate.json` and runs through
`make renovate` from `.github/workflows/renovate.yml`.

- `config/project.cfg` selectors
  - tool images, the Go image, and the Terraform provider version
  - grouped into one "project tooling and images" PR
- `config/lockfile.cfg` image digests
  - digest-only refreshes when an upstream image is rebuilt under the same tag
  - covers `DEV_BASE_IMAGE` (`debian:trixie-slim`), which has no version tag to
    bump, so Debian security rebuilds still reach the image
  - tag changes stay in `config/project.cfg`; a packageRule disables tag updates
    on lockfile lines
- `config/infra/.terraform.lock.hcl`
  - Renovate's `terraform` manager rewrites provider hashes in the same PR as
    the provider bump, so `-lockfile=readonly` validation keeps passing
- GitHub Actions in `.github/workflows/`
  - full-SHA pins with version comments, grouped into one PR
- Go modules in `src/go.mod`
  - `go mod tidy` runs after updates
  - Renovate does not bump the `go` directive by default

For the grouped "project tooling and images" PR, Renovate then runs:

```sh
sh scripts/update.sh config/project.cfg --refresh-package-snapshot
```

That command refreshes immutable locks in `config/lockfile.cfg`, syncs related
generated references, and moves `DEV_PACKAGE_SNAPSHOT_LOCK` to the current UTC
day so Debian packages pick up security fixes. Plain `make update` keeps the
reviewed snapshot unchanged.

PR titles and commit subjects follow `docs/gitops-conventions.md`:

- `[deps] tooling: update project tooling and images`
- `[deps] actions: update github-actions`
- `[deps] go: update <module> ...` for Go modules
- `[deps] renovate: ...` as the fallback for anything not matched above

## Schedule and cooldowns

- The workflow runs daily.
- Routine update PRs are created on Mondays, UTC
  (`"schedule": ["* * * * 1"]`). Weekly batches keep each PR small while the
  7-day cooldown below still filters out brand-new releases.
- Routine updates wait 7 days after an upstream release
  (`minimumReleaseAge`). This timing defense helps avoid immediately adopting a
  newly published action, image, or module before yanks, malicious releases, or
  incident reports have time to surface.
- Vulnerability-fix PRs from Dependabot alerts skip both the schedule and the
  cooldown, so they open on the next daily run.

## Why not Dependabot version updates

- Dependabot cannot parse the `# renovate:` selectors in `config/project.cfg`.
- It cannot run `scripts/update.sh`, so selectors, digests, and generated files
  would drift into separate PRs.
- Running both tools for GitHub Actions would open duplicate PRs.
- Dependabot security updates default to off in `config/infra` for the same
  reason; Renovate opens those fixes instead.

## GitHub App Token

The Renovate workflow mints a GitHub App token instead of using a broad personal
access token. The app token can be scoped to the repository and permissions that
Renovate needs to open pull requests and report status.

The app needs these permissions:

- contents, pull requests, checks, statuses: write
  - open and update PR branches and report status
- workflows: write
  - GitHub requires it for any app that edits `.github/workflows/*`
  - this lets Renovate change CI files, so review workflow PRs carefully
- Dependabot alerts (`vulnerability_alerts`): read
  - lets Renovate open vulnerability-fix PRs
- administration, metadata: read

`.github/renovate/setup-github-app.sh` requests these for new apps. For an
existing app, add the missing permissions in the app settings and accept the
change on its installation.

To disable self-hosted Renovate in a derived repository, set this in
`config/project.cfg`:

```sh
DEV_SCAN_ENABLE_RENOVATE=false
```

## Review Expectations

For dependency update PRs:

- confirm the version selector changed for the intended dependency
- confirm `config/lockfile.cfg` changed when a locked image was updated
- keep full-SHA action pins and reviewed tag comments intact
- run the relevant `make` target locally or rely on the matching required check
- pay extra attention to updates for build, release, scan, and credentialed
  workflow tools

Provider version changes need a review of `config/infra/.terraform.lock.hcl`.
Renovate updates it in the same PR; for manual provider changes, run
`INFRA_UPDATE_LOCK=true make infra`. Ordinary infra validation verifies that lock
without modifying it.

`make update` refreshes image digests but keeps the Debian package snapshot date.
Renovate passes `--refresh-package-snapshot` to advance it; for a manual refresh,
run `sh scripts/update.sh config/project.cfg --refresh-package-snapshot`.
