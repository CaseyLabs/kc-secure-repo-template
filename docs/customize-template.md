# Repo Template Customization Guide

This repository is a starting point for a new project, not an application
framework. The intended path is to keep the secure workflow shape, then replace
the bundled example with your real project code.

## First Decisions

- Choose a project name and image name in `config/project.cfg`.
- Replace or extend the example under `src/`.
- Update `Dockerfile` so the dev image contains the tools your project needs.
- Keep root commands in `Makefile` stable and put implementation details in
  `scripts/`.
- Keep generated files, local credentials, build caches, and environment-specific
  state out of git.

`config/project.cfg` is the main customization point because the same settings
are loaded by local scripts, CI workflows, release packaging, and optional
Kubernetes or Terraform support. Using one reviewed config file reduces drift
between local and GitHub Actions behavior.

## Recommended Adoption Flow

1. Start from the template and run `make example`.
2. Set `PROJECT_NAME` and `PROJECT_IMAGE` in `config/project.cfg`.
3. Replace the contents of `src/` with your project source.
4. Adjust `Dockerfile` for the project's build and test toolchain.
5. Update `scripts/build.sh`, `scripts/test.sh`, and `scripts/run.sh` only as
   needed for the project.
6. Run `make build`, `make test`, and `make scan`.
7. Review `.github/workflows/` and keep workflows calling `make` targets.
8. Keep or remove optional `config/k8s/` and `config/infra/` support based on
   whether the derived project will use them.

## What To Preserve

- Root `make` targets should stay small and predictable for maintainers.
- CI should call the same `make` targets that developers run locally.
- External GitHub Actions should stay pinned by full commit SHA with a reviewed
  release tag comment.
- Tool container images should stay locked in `config/lockfile.cfg` through
  `make update`.
- Sensitive values should stay in GitHub secrets, local environment variables,
  or ignored local files, not in tracked config or docs.

## Optional Areas

- Kubernetes support lives under `config/k8s/`; see
  [`docs/k8s.md`](../docs/k8s.md).
- Terraform-backed GitHub repository hardening lives under `config/infra/`; see
  [`docs/terraform.md`](../docs/terraform.md).
- GitHub workflow and repository-control guidance lives in
  [`docs/github-ci.md`](github-ci.md).

These areas are optional so a derived repository can stay small. Remove unused
scaffolding deliberately, then run the relevant checks so packaging, scans, and
documentation remain aligned.
