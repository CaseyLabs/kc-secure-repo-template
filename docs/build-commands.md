# Project Build Commands

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

## Configurable Workflow Commands

- `config/project.cfg` sets the commands `make build`, `make test`, and
  `make run` run inside the existing non-root dev container:
  - `PROJECT_BUILD_COMMAND`
  - `PROJECT_LINT_COMMAND` (runs before the tests in `make test`)
  - `PROJECT_TEST_COMMAND`
  - `PROJECT_RUN_COMMAND`
- Each runs as `sh -eu -c "<command>"` from the repository root (`/workspace`).
  The defaults are the bundled Go example commands.
- A layered config that sources `config/project.cfg` can override any of them.
  Configs that predate these settings fall back to the Go defaults.
- Only the config sets these; exported environment variables are ignored.
- An empty value turns that step into a no-op.
- A failing build, lint, or test command fails the make target; there is no
  silent fallback. `make run` starts its command detached, so run failures show
  in `make status` and `make logs`.
- The dev image must contain the toolchain the commands need; see
  `docs/customize-template.md`.
- The dev image sets `GOTOOLCHAIN=local`, so Go uses only the toolchain in
  `DEV_GO_IMAGE_LOCK` and never downloads another one.
  - If the `go` line in `src/go.mod` is ahead of that image, `make build` and
    `make test` fail with
    `go.mod requires go >= X (running go Y; GOTOOLCHAIN=local)`.
  - A newer `toolchain` line is ignored; the image's Go version is used.
  - `make scan` fails if the `dev` stage stops setting `GOTOOLCHAIN=local`.
  - Fix it by raising `DEV_GO_IMAGE` in `config/project.cfg` and running
    `make update` to refresh the digest lock, not by unsetting the variable.

## Specialized Commands

- `make scan`: runs template security scans, workflow policy checks, AI agent
  setup checks, and the commit attribution check.
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
- `TEST_MODE`: defaults to `src`. `template` runs isolated shell regressions and
  copied-repository build, test, Terraform, Helm, and packaging checks. `smoke`
  remains a compatibility alias for that same suite.
- `TEMPLATE_SKIP_SRC_TESTS`: set to exactly `true` to skip the nested `src`
  tests inside `TEST_MODE=template`. CI uses it because `test-code` already runs
  them; leave it unset locally and for releases.
- `INFRA_UPDATE_LOCK=true`: explicitly refreshes provider checksums during
  `make infra`; review the resulting lockfile before applying.
- `APPLY=true`: lets `make infra` apply the generated Terraform plan.
- `ENABLE_SBOM`, `ENABLE_GRYPE`, `GRYPE_FAIL_ON`: control release integrity
  outputs used by `make dist` and the release workflow.
- `DOCKER_BUILD_EXTRA_ARGS`: optional extra `docker buildx build` flags, such
  as a layer cache, without changing local defaults.
  - When set, `scripts/build.sh`, `scripts/scan.sh`, and `scripts/dist.sh` build
    with `docker buildx build --load` instead of plain `docker build`.
  - The template's workflows leave it unset. On GitHub-hosted runners, plain
    `docker build` was faster than a warm Buildx `type=gha` cache: Buildx setup
    and the `--load` import into Docker cost more than the cache saved.
  - A `type=gha` cache also needs the Actions cache token exported to `run:`
    steps, which GitHub only gives to actions; without it Buildx silently
    skips the cache.
  - Keep the release workflow uncached so release artifacts never reuse layers
    written by other runs.
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

## Optional Go Runtime Image

- Off by default. Set `PROJECT_RUNTIME_IMAGE` in `config/project.cfg` (for
  example `my-app-runtime:local`) and `make build` also builds the Dockerfile
  `runtime` stage into that tag.
- The image holds only the static example binary on
  `gcr.io/distroless/static-debian13:nonroot`.
  - It runs as `nonroot:nonroot` with an exec-form `ENTRYPOINT` and has no shell.
  - Source and tests stay in the build stage; `docker build` does not run tests.
- The base is pinned by digest through `DEV_DISTROLESS_STATIC_IMAGE_LOCK`, and
  the Go compiler through `DEV_GO_IMAGE_LOCK`. With the image enabled,
  `make build` fails before building anything if either lock is missing or not
  digest-pinned.
  - The build stage sets `GOTOOLCHAIN=local`, so raising the `go` line in
    `src/go.mod` cannot download a newer toolchain; bump the lock instead.
- The runtime stages sit above `dev` in the `Dockerfile`, so a plain
  `docker build .` still produces the dev image.
  - `make build`, `make scan`, and `make dist` refuse `DOCKER_BUILDKIT=0` and
    otherwise run Docker with `DOCKER_BUILDKIT=1`: the legacy builder builds
    every stage above the target, including the runtime stages from their
    mutable fallback tags.
- `make scan` checks that the `runtime` stage builds `FROM` the
  `RUNTIME_BASE_IMAGE` arg, keeps a digest-pinned lock (or an empty one from a
  blank selector), a non-root `USER` and group, and an exec-form `ENTRYPOINT`.
  - It also requires a `runtime-build` stage built `FROM` the
    `RUNTIME_BUILD_IMAGE` arg, and the `runtime` stage may only
    `COPY --from=runtime-build`.
  - Deleting the `runtime` stage skips the check.
- Try it: `docker run --rm my-app-runtime:local`.

## Optional Image Vulnerability Scan

- Off by default (`PROJECT_SCAN_IMAGE_VULNS=false`); with it off, `make scan` is unchanged.
- Set `PROJECT_SCAN_IMAGE_VULNS=true` and `make scan` also:
  - builds `PROJECT_SCAN_IMAGE_TARGET` (default `runtime`) through the same build-arg path as the dev image
  - saves it to a temporary tarball and runs the pinned Trivy image on it
  - fails on HIGH or CRITICAL findings (`--exit-code 1 --severity HIGH,CRITICAL`)
  - deletes the tarball and the scan image whether the scan passes or fails
- The runtime target needs digest-pinned `DEV_GO_IMAGE_LOCK` and `DEV_DISTROLESS_STATIC_IMAGE_LOCK`.
- Unlike the other scanners, this one needs network access for Trivy's vulnerability database, so Trivy gets only the read-only tarball.
- Values other than `true` or `false` fail the scan.
- Keep the target on a shipped-image stage; the dev image carries toolchains on purpose.
- `make dist` does not record this scan in its release evidence yet.
