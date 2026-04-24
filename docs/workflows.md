# Workflow Guide

Use `make help` as the source of truth for available root commands. The root
targets are intentionally small; scripts under `scripts/` hold the implementation
details so local use and GitHub Actions can share the same behavior.

## Core Commands

- `make build`: builds the project development container image.
- `make test`: runs the selected test mode inside the container-first workflow.
- `make run`: starts the example app container, building first when needed.
- `make stop`: stops the running example app container.
- `make status`: shows local image and container state.
- `make logs`: prints logs from the running app container.
- `make clean`: removes generated artifacts, caches, and the local image.
- `make shell`: opens a shell in the running container.
- `make example`: runs the bundled build, test, run, logs, stop, and scan flow.

These commands are the normal adopter interface. Prefer changing the scripts they
call instead of adding many new root targets.

## Specialized Commands

- `make scan`: runs template security scans and workflow policy checks.
- `make update`: resolves reviewed image selectors into digest locks and syncs
  related generated references.
- `make renovate`: runs self-hosted Renovate when enabled.
- `make dist`: builds release artifacts and integrity outputs under `dist/`.
- `make k8s`: lints, renders, and packages the optional Helm chart.
- `make k8s-test-local`: validates rendered Kubernetes manifests with
  `kubectl apply --dry-run=server` against a real kubeconfig/context.
- `make infra`: builds, formats, validates, and plans the optional Terraform
  GitHub hardening workspace; applies only when `APPLY=true`.

## Common Inputs

- `PROJECT_CFG_FILE`: selects the project config file. Defaults to
  `config/project.cfg`.
- `TEST_MODE`: selects `src`, `template`, or `smoke` behavior for `make test`.
- `APPLY=true`: lets `make infra` apply the generated Terraform plan.
- `ENABLE_SBOM`, `ENABLE_GRYPE`, `GRYPE_FAIL_ON`: control release integrity
  outputs used by `make dist` and the release workflow.
- `DOCKER_BUILD_EXTRA_ARGS`: lets CI provide Buildx cache options without
  changing local defaults.
- `DOCKER_UID`, `DOCKER_GID`, `DOCKER_HOME`, `DOCKER_HOME_SOURCE`, and
  `DOCKER_TMPDIR`: control container user and cache paths for bind-mounted
  workflows.

Project-specific values belong in `config/project.cfg` when they should be
reviewed and committed. Local-only values belong in the environment.

## Why The Workflow Is Container-First

The default workflow avoids requiring a host-installed language toolchain. Builds,
tests, scans, and release steps run through Docker images selected by
`config/project.cfg` and locked by `config/lockfile.cfg`.

This keeps local development, CI, and release behavior close together. It also
makes dependency changes reviewable: normal version selectors live in
`config/project.cfg`, while immutable lock values are refreshed by `make update`.

## CI Alignment

GitHub Actions should stay thin wrappers around `make` targets. If a workflow
needs new behavior, add it to the relevant script or target first, then call that
same entrypoint from CI. This prevents a command from passing locally while the
workflow runs a different implementation.
