# Dependency Update Guide

This template uses both Dependabot and self-hosted Renovate. They cover different
parts of the repository and use cooldowns so maintainers have time to review new
upstream releases before routine update pull requests appear.

## Dependabot

Dependabot is configured in `.github/dependabot.yml`.

It updates:

- GitHub Actions used by workflows
- Dockerfile dependency references when present

Routine update PRs wait for the configured cooldown period. This timing defense
helps avoid immediately adopting a newly published action or image before yanks,
malicious releases, or incident reports have time to surface.

## Renovate

Self-hosted Renovate is configured in `.github/renovate.json` and runs through
`make renovate`.

It updates reviewed selectors in `config/project.cfg`, including tool images and
Terraform provider versions. After updating those selectors, Renovate is allowed
to run:

```sh
sh scripts/update.sh config/project.cfg
```

That command refreshes immutable locks in `config/lockfile.cfg` and syncs related
generated references. Keeping selectors and locks together makes dependency
changes easier to review.

## GitHub App Token

The Renovate workflow mints a GitHub App token instead of using a broad personal
access token. The app token can be scoped to the repository and permissions that
Renovate needs to open pull requests and report status.

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
