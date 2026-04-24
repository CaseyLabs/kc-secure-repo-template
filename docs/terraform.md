# Infra Workspace

This workspace shows how to adapt the template into a repository that uses
Terraform to create and harden a GitHub repository through the
`integrations/github` provider.

Purpose:

- create or manage a GitHub repository through Terraform
- apply a solo-maintainer-friendly hardening baseline
- keep plan and apply behavior behind the root `make infra` workflow
- keep tokens and local state out of tracked files

Runtime shape:

- the infra image keeps a Debian-based nonroot runtime layer
- the image copies in `terraform` from the selected Terraform Docker Hub image
- the root workflow is implemented by
  [`scripts/infra.sh`](../../scripts/infra.sh)

Usage:

```sh
PROJECT_CFG_FILE=config/project.cfg make infra
APPLY=true GITHUB_TOKEN=... make infra
```

Workflow notes:

- `make example` still points at the smaller Go demo under `src`
- use `make infra` for the Terraform workspace under `config/infra`
- `make infra` builds the infra dev container image
- `make infra` runs Terraform formatting and validation
- `make infra` generates `.tmp/infra/github-repository.tfplan`
- `make infra` prints the reviewed apply command
- `APPLY=true make infra` reuses the same flow, then applies the generated plan

Release-scan defaults:

- SBOM generation is disabled by default for this workspace
- Grype scanning is disabled by default for this workspace
- the infra flow is centered on the generated Terraform plan
- the infra workspace is not treated as a published release artifact set

Repository hardening defaults:

- Dependabot security features stay enabled
- default-branch rulesets stay enabled
- linear history stays enabled
- non-fast-forward protection stays enabled
- merge review requirements default to off so a single owner can keep working
  without needing a second approver
- public repositories get secret scanning and push protection through the
  `security_and_analysis` block
- private or internal repositories depend on GitHub Secret Protection plan and
  organization settings for secret scanning and push protection
- the default branch ruleset requires the `test-code`, `test-repo`, and
  `scan-repo` GitHub Actions checks before merge
- the release tag ruleset protects `refs/tags/v*` tags from deletion or
  retagging
- the release workflow also verifies that a tag points at default-branch history
  before publishing artifacts
- `archive_on_destroy` defaults to `true`, so a Terraform destroy archives the
  repository instead of deleting it

Before `make infra`:

- update `terraform.tfvars.example` with your repository details
- keep `default_branch = null` when an existing repository's current default
  branch should stay unchanged
- set `default_branch` only when Terraform should manage that setting

Before `APPLY=true make infra`:

- export a token in the environment
- do not commit the token to Terraform files, examples, plans, logs, or docs

```sh
export GITHUB_TOKEN=replace-with-a-real-token
```

For organization or GitHub Enterprise repositories:

- adjust provider settings before applying
- adjust input defaults before applying
- verify GitHub-side controls before relying on them
