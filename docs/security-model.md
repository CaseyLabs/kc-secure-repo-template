# Security Model

This template reduces common repository and supply-chain risks by making build,
test, scan, release, and dependency-update behavior explicit and reviewable. It
does not replace project-specific threat modeling, secure coding, or GitHub
organization controls.

## Default Protections

- Container-first workflows reduce dependence on mutable host toolchains.
- Development containers run as a nonroot user and drop capabilities where the
  scripts run containers directly.
- Docker image selectors are reviewed in `config/project.cfg` and locked by
  digest in `config/lockfile.cfg`.
- GitHub Actions are pinned by full commit SHA and keep a reviewed release tag
  comment beside each external action reference.
- `make scan` runs secret scanning, workflow linting, Dockerfile
  misconfiguration scanning, Kubernetes manifest scanning when configured, and
  workflow policy checks.
- Release builds repeat tests and scans on the tagged commit, reject tags outside
  default-branch history, and refuse to modify an existing GitHub Release.
- Release outputs can include checksums, an SBOM, a vulnerability report, and
  GitHub artifact attestations.

## Why These Controls Exist

- Pinned dependencies make code review meaningful because reviewers can inspect
  the exact action or image that will run.
- Digest locks protect runtime scripts from mutable image tags after a version
  selector is reviewed.
- `pull_request` workflows treat contributor code as untrusted; the template
  rejects checked-in use of `pull_request_target` for default CI paths.
- Repeating tests and scans during release protects against tags that are created
  after pull request checks have completed.
- Nonroot containers and dropped capabilities reduce the blast radius of build
  and test tooling.

## Git Versus GitHub Settings

Some protections are enforced by files in this repository:

- workflow trigger policy and action pinning in `make scan`
- pinned image locks in `config/lockfile.cfg`
- release tag ancestry checks in `.github/workflows/build.yml`
- release artifact generation in `scripts/dist.sh`
- optional Terraform hardening defaults under `config/infra/`

Other protections depend on GitHub repository or organization settings:

- secret scanning and push protection availability
- default branch protection or rulesets
- release immutability
- tag protection or tag rulesets
- workflow approval policies
- environment protection rules
- organization SSO, audit logging, and secret access policies

Document the GitHub-side controls for each derived repository so maintainers know
which protections are actually active.

## Credentials

Keep credentials out of tracked files, examples, docs, and logs. Prefer narrow,
short-lived credentials such as GitHub App tokens or OIDC-based credentials.
Avoid broad personal access tokens for automation.

Self-hosted Renovate is designed to use a GitHub App token with scoped
permissions. Terraform operations use `GITHUB_TOKEN` from the local environment
or a protected automation environment, not from tracked files.

## Related Docs

- [`docs/github-ci.md`](github-ci.md): GitHub workflow and repository-control
  guidance.
- [`docs/release-and-packaging.md`](release-and-packaging.md): release artifact
  and integrity output details.
- [`docs/terraform.md`](../docs/terraform.md): Terraform-backed GitHub
  hardening workspace.
