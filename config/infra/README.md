# Infra Workspace

This workspace shows how to adapt the template into a repository that uses Terraform to create and harden a GitHub repository through the `integrations/github` provider.

The infra image keeps a Debian-based nonroot runtime layer and then copies in `terraform` from the selected Terraform Docker Hub image.

The root template now exposes this workspace through `make infra` and the declarative settings in [`scripts/infra.sh`](../../scripts/infra.sh):

```sh
PROJECT_CFG_FILE=config/project.cfg make infra
APPLY=true GITHUB_TOKEN=... make infra
```

The root `make example` target still points at the smaller Go demo under `src`. Use `make infra` when you want to build, test, plan, or apply the Terraform workspace under `./config/infra`.

What the mapped targets do:

- `make infra`: builds the infra dev container image, runs `fmt`, runs validation, generates `.tmp/infra/github-repository.tfplan`, and prints the reviewed apply command
- `APPLY=true make infra`: reuses the same flow, then applies the generated plan instead of stopping after plan output

The declarative infra defaults also disable SBOM and Grype by default. That keeps the infra flow centered on the generated Terraform plan workspace rather than scanning it as if it were a published release artifact set.

The repository defaults in this workspace aim for a solo-maintainer-friendly baseline: secret scanning, Dependabot security features, default-branch rulesets, linear history, and non-fast-forward protection stay enabled, while merge review requirements default to off so a single owner can keep working without needing a second approver. The default ruleset also requires the repository's `build`, `test`, and `scan` GitHub Actions checks before merge, and `archive_on_destroy` defaults to `true` so a Terraform destroy archives the repository instead of deleting it.

Before `make infra`, update `terraform.tfvars.example` with your repository details. `default_branch = null` leaves an existing repository's current default branch unchanged; set a branch name only when you intentionally want Terraform to manage that setting. Before `APPLY=true make infra`, also export a token:

```sh
export GITHUB_TOKEN=replace-with-a-real-token
```

If you manage repositories for an organization or GitHub Enterprise instance, adjust the provider settings and inputs in this workspace before applying it to a real repository.
