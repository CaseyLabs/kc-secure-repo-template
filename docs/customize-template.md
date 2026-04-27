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
4. Identify how the project builds, tests, runs, and releases before changing
   root workflow files.
5. Adjust `Dockerfile` for the project's build and test toolchain.
6. Update `scripts/build.sh`, `scripts/test.sh`, and `scripts/run.sh` only as
   needed for the project.
7. Run `make build`, `make test`, and `make scan`.
8. Review `.github/workflows/` and keep workflows calling `make` targets.
9. Keep or remove optional `config/k8s/` and `config/infra/` support based on
   whether the derived project will use them.

## Map The Source Project

Before wiring commands into the template, inspect the project under `src/` and
write down the answers maintainers will need during review:

- primary language, framework, and runtime
- package manager, dependency manifests, and lockfiles
- build, test, lint, format, and smoke-test commands
- executable entrypoint and default run command
- runtime ports, volumes, and required environment variables
- local data, generated files, caches, and credentials that must stay ignored
- release artifacts, container image names, and published package names

Use that inventory to decide what belongs in `config/project.cfg`, `Dockerfile`,
and `scripts/`. Avoid copying one-off terminal commands directly into GitHub
Actions; put durable behavior behind root `make` targets instead.

## Where Changes Belong

- `src/`
  - project application code and its own tests
  - language lockfiles that the project needs for reproducible installs
- `config/project.cfg`
  - reviewed project name, image name, tool image selectors, and optional
    Kubernetes or Terraform defaults
  - values that local scripts and CI should share
- `Dockerfile`
  - the container runtime and development tools needed for build, test, and run
  - deterministic package installation and nonroot runtime expectations
- `scripts/`
  - implementation details for root `make` targets
  - project-specific build, test, run, release, scan, or update commands
- `Makefile`
  - a small stable command surface for humans and CI
  - thin target wiring only; avoid burying project logic here
- `.github/workflows/`
  - thin wrappers around `make` targets
  - pinned external actions and minimal permissions
- `docs/`
  - user-facing setup, workflow, deployment, and security notes that changed
    because of the adaptation

When removing optional areas such as `config/k8s/` or `config/infra/`, also
remove stale docs, workflow references, release packaging expectations, and
agent guidance that described the removed area.

## Validation Checklist

- After replacing `src/`
  - run `make build`
  - run `make test`
- After changing `Dockerfile`, `scripts/`, or root targets
  - run `make build`
  - run `make test`
  - run `make scan`
- After changing GitHub Actions or pinned tool/image selectors
  - run `make scan`
  - run `make update` when lock values need to refresh
- After changing Kubernetes support
  - run `make k8s`
  - run `make k8s-test-local` only with a real kubeconfig/context
- After changing Terraform support
  - run `make infra`
  - run `APPLY=true make infra` only when intentionally applying with a real
    `GITHUB_TOKEN`
- Before changing release packaging or shipped template files
  - run `make dist`
  - inspect `dist/template-manifest.txt`

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

## Optional Agent Help

If you use an agent that supports repo-local skills, invoke `$repo-adaptation`
when adapting this repository around new source code in `src/`.

Example prompt:

```text
$repo-adaptation Inspect `src/` and update the repository workflow so
`make build`, `make test`, and `make run` match this project. Preserve the root
Makefile interface, keep project-specific logic in `scripts/`, update docs for
workflow changes, and call out any Docker, runtime, dependency, or validation
changes before editing.
```

The skill is optional. The repository should remain understandable through
`README.md`, `docs/`, `Makefile`, and the scripts even when no agent is used.
