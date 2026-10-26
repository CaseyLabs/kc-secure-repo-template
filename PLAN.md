# Language-Neutral Workflow and Runtime Image Plan

Status: milestones 1–2 done (unmerged branches). Replaces `feat/dockerfile-templates` (02459d7), which is
31 commits behind `main`, conflicts in 5 files, and has design bugs (see the
review notes at the end).

## Objective

Let derived repositories use the root `make` interface with stacks other than
the bundled Go example, and give them an optional hardened runtime image, without
weakening the template's defaults.

- The default Go `src/` example keeps working with no config changes.
- Every new behavior is opt-in through `config/project.cfg`.
- Every new image is pinned by digest in `config/lockfile.cfg` and kept updated
  by Renovate (Dependabot only does alerts now; see #78).
- No new shipped per-language Dockerfiles. Python and Node.js become
  documentation, not code.

## Ground rules for every milestone

- One milestone per branch and PR, branched from the latest `main`
  (`feat/<scope>-<summary>`, per `docs/gitops-conventions.md`).
- Test first: add the failing template-mode check before the change. Use the
  existing fake-`docker` pattern in `scripts/test.sh` (see the `scan.sh` and
  `update.sh` cases near lines 528–690).
- Verification for every milestone: `TEST_MODE=template make test`,
  `make test`, `make scan`. Only one agent runs these at a time in a checkout.
- Load the `workflow-validation` skill for script and CI changes, and
  `repo-adaptation` for customization-surface and language-guidance changes.

## Decisions (confirmed 2026-10-26)

- D1. The Go runtime stage is a `runtime` stage in the root `Dockerfile`. It
  builds from the pinned Go image and is used only when the build targets it.
  Not a separate `src/Dockerfile`.
- D2. Distroless images keep the `:nonroot` tag in `project.cfg`.
  `make update` and Renovate digest updates refresh the lock digest. Document
  this in `docs/dependency-updates.md`.

## 1. Configurable workflow commands

Priority: high. Self-contained; needed by everything else.

Current state:

- The Go commands are hard-coded in `scripts/build.sh:73`, `scripts/run.sh:57`,
  and `scripts/test.sh:1395` and `:1409`.

Work:

- Add `PROJECT_BUILD_COMMAND`, `PROJECT_LINT_COMMAND`, `PROJECT_TEST_COMMAND`,
  and `PROJECT_RUN_COMMAND` to `config/project.cfg`, with comments. Their
  defaults are the current Go commands.
- The scripts read these with a fallback to the current Go command, so older
  layered configs that don't set them keep working.
- The commands run with `sh -eu -c` inside the existing non-root dev container.
  Don't add any other way to run them.
- Don't add `PROJECT_BUILD_TARGET` to `build.sh` yet. `dist.sh` and `scan.sh`
  already support it; add it only if milestone 2 needs it.

Acceptance:

- With no config changes, `make build`, `make test`, and `make run` run exactly
  what they ran before.
- A layered config that overrides a command makes the matching script run the
  override (checked against a fake `docker` in template mode).
- An override that fails makes the make target fail, with no silent fallback.

Likely files: `config/project.cfg`, `scripts/build.sh`, `scripts/run.sh`,
`scripts/test.sh`, `docs/customize-template.md`, `docs/build-commands.md`.

## 2. Optional Go runtime image

Priority: medium. Depends on 1 and D1.

Work:

- Add a multi-stage runtime build. It compiles `src/cmd/app` in the pinned Go
  image (`CGO_ENABLED=0`, `-trimpath`, `-buildvcs=false`), then copies only the
  binary into `gcr.io/distroless/static-debian13:nonroot`.
- Use exec-form `ENTRYPOINT` and `USER nonroot:nonroot`. Tests and source code
  stay out of the final image, and tests don't run during `docker build`.
- Add `DEV_DISTROLESS_STATIC_IMAGE` to `project.cfg` with a `# renovate:`
  comment matching the existing `customManagers` regex, and add
  `DEV_DISTROLESS_STATIC_IMAGE_LOCK` to the lockfile.
- `scripts/update.sh`: add a `gcr.io` digest lookup (salvage `gcr_digest` from
  02459d7). Skip it when the selector is blank, like the optional k8s images.
- Expose this through existing targets or config only, not a new root target,
  unless `make help` clearly needs one.

Acceptance:

- With the feature off, image builds and outputs are unchanged.
- The runtime image runs as nonroot, contains only the binary, and starts the
  example.
- Template mode fails if the distroless lock is not digest-pinned, or if the
  runtime stage has no non-root `USER` or uses a shell-form entrypoint.
- `update.sh` resolves `gcr.io` selectors (tested with a fake `curl`).

Likely files: `Dockerfile`, `config/project.cfg`,
`config/lockfile.cfg`, `scripts/update.sh`, `scripts/test.sh`,
`.github/renovate.json` (only if the regex doesn't already match),
`docs/dependency-updates.md`.

## 3. Opt-in runtime image vulnerability scan

Priority: medium. Depends on 2.

Work:

- `PROJECT_SCAN_IMAGE_VULNS=false` by default, plus `PROJECT_SCAN_IMAGE_TARGET`.
  When on, `make scan` builds that target and runs the pinned Trivy image
  against a saved image tarball, failing on HIGH and CRITICAL findings.
- Build it with the same build-arg path as the existing `scan.sh` build. Don't
  copy the build-arg block a third time; factor it into a function in the
  script if that helps.
- Keep it off for the dev image, which carries toolchains on purpose.
- Decide with the `release-integrity` skill whether `make dist` should record
  this scan in its release evidence. Leave that out of this milestone unless
  it's trivial.

Acceptance:

- When off, `make scan` output and behavior are unchanged.
- When on, a fake `docker` shows the runtime target built and Trivy called with
  `--exit-code 1 --severity HIGH,CRITICAL`, and Trivy failing makes the scan
  fail.
- The temporary image tarball is deleted whether the scan passes or fails.

Likely files: `scripts/scan.sh`, `config/project.cfg`, `scripts/test.sh`,
`docs/security-model.md` or `docs/build-commands.md`.

## 4. Python and Node.js adaptation guidance

Priority: low. Docs only; depends on 1.

Work:

- In `.agents/skills/repo-adaptation/references/language-guidance.md`, add
  example `PROJECT_*_COMMAND` values and a sketch runtime stage for each stack.
- Node.js: require `npm ci` with a committed lockfile. Use the same major
  version in the builder image and in `distroless/nodejs<N>-debian13`.
- Python: the builder's Python version must match the distroless runtime's
  (Debian 13 ships 3.13). Pin pip tooling or use hashed requirements, and set
  `PYTHONPATH` for both `make run` and the runtime image.
- Add Python to the skill's scope list, or leave it out on purpose and say so.
- Say clearly that these live in derived repositories, not the template.

Acceptance:

- The examples match the variable names and scripts as merged in 1–3.
- No unpinned installs or lockfile-optional paths appear in the examples.

Likely files: `.agents/skills/repo-adaptation/references/language-guidance.md`,
`.agents/skills/repo-adaptation/SKILL.md`, `docs/customize-template.md`.

## 5. Retire the old branch

- After milestone 2 merges, delete `feat/dockerfile-templates` locally and on
  `origin`. Confirm with the maintainer first.
- Delete this `PLAN.md` when all milestones are done, as in f8eb0a1.

## Review notes on 02459d7 (why not rebase)

- It modifies `.github/dependabot.yml`, which #78 deleted.
- Its Python template builds with 3.14 and runs on distroless Python 3.13, so
  packages with compiled code break.
- Its template `dev` stages have no `jq`, `make`, or non-root user, so
  `make scan` breaks when `PROJECT_DOCKERFILE` points at them.
- Python `make run` can't import `src/app` because `PYTHONPATH` isn't set in
  the dev stage.
- Unpinned `pip install --upgrade` and a lockfile-optional `npm install`.
- The same build-arg block is copied into 7 places across three scripts.

## Progress

- [x] D1 / D2 confirmed
- [x] 1. Configurable workflow commands (2026-10-26; `test_workflow_command_overrides`; template test, `make test`, `make scan` passed)
- [x] 2. Optional Go runtime image (2026-10-26; `test_update_gcr_digest`, `test_runtime_image_build`, `test_runtime_image_policy`, real runtime build in template mode; template test, `make test`, `make scan` passed)
- [ ] Follow-up: lock formats differ by registry (ghcr.io drops the tag, gcr.io and Docker Hub keep it); unify in `resolve_image` as a separate change
- [ ] Follow-up: `make scan` could check every non-empty `*_LOCK` is digest-pinned and share one pin helper with `scan.sh`/`dist.sh`/`build.sh`
- [ ] 3. Opt-in runtime image vulnerability scan
- [ ] 4. Python and Node.js adaptation guidance
- [ ] 5. Retire the old branch

## Surprises & Discoveries

- 2026-10-26 (M1): `make run` starts its command detached, so a failing
  `PROJECT_RUN_COMMAND` cannot fail the make target (same as before). The test
  covers `run.sh` failing when `docker run` fails; docs point to `make status`
  and `make logs`.

- 2026-10-26 (M2): BuildKit rejects a blank `FROM` in any stage, even one it
  does not build ("base name should not be blank"), so the runtime stages keep
  fallback tags. `make build` always passes the digest locks and refuses to
  build the runtime image without them.
- 2026-10-26 (M2): A plain `docker build .` builds the last stage, so the
  runtime stages sit above `dev` to keep the default image unchanged.

## Decision Log

- 2026-10-26 (M1): The scripts fall back to the Go command only when a variable
  is unset (`${VAR-default}`). An explicitly empty command is a deliberate no-op
  (for example, a stack with no lint step).
- 2026-10-26 (M1): The scripts `unset` the four command variables before
  sourcing the config, so an exported environment variable cannot replace the
  reviewed command.
- 2026-10-26 (M1): Kept the Go defaults duplicated in `project.cfg` and the
  script fallbacks, as the plan requires. Declined a shared-defaults helper.
- 2026-10-26 (M1): The dev image still builds from `DEV_GO_IMAGE_LOCK`. Choosing
  a toolchain stays with milestones 2 and 4.

- 2026-10-26 (handoff, user decision): Branch milestone 2 from
  `feat/workflow-configurable-commands` (M1, unmerged, commit d968a2b) rather than
  `main`. Rebase it onto `main` once M1's PR merges.

- 2026-10-26 (M2 design): Opt-in is `PROJECT_RUNTIME_IMAGE` in `project.cfg`
  (blank = off, image tag to build when set). `build.sh` then also builds
  `--target runtime`. The `dev` build and its args are untouched. The Go builder
  stage reuses `DEV_GO_IMAGE_LOCK` via a `RUNTIME_BUILD_IMAGE` arg. The policy
  check lives in `scripts/workflow-policy.sh` (already in the manifests) so no
  new script has to be added to the template manifests.

- 2026-10-26 (M2 review): The scan policy accepts an empty distroless lock (a
  blank selector, which `update.sh` supports); a non-empty lock must be
  digest-pinned and the stage must build `FROM ${RUNTIME_BASE_IMAGE...}`.
  `build.sh` checks both the Go and distroless locks before any docker build.
- 2026-10-26 (M2 review): Declined renaming `DEV_DISTROLESS_STATIC_IMAGE` to a
  role name (the plan fixes the name), Go build-cache mounts, and parallel
  dev/runtime builds (simplicity over seconds).

## Outcomes & Retrospective

- M1: `PROJECT_{BUILD,LINT,TEST,RUN}_COMMAND` shipped with a fake-docker
  regression covering defaults, legacy configs, overrides, env isolation, empty
  commands, and failure propagation. Fixed eight `/code-review` findings
  (fallback semantics, env leak, GNU-only grep, a weak assertion, untested run
  failure, stale summaries and comments, a wrong fail message); declined two.
- M2: Opt-in `PROJECT_RUNTIME_IMAGE` builds a distroless, nonroot, exec-form
  runtime stage from digest locks; `update.sh` resolves gcr.io and now shares
  one registry token and manifest helper across Docker Hub, GHCR, and gcr.io.
  Fixed eight `/code-review` findings (policy bypass via `FROM`, blank-selector
  scan failure, default-target change, unchecked Go lock, no real runtime build
  in CI, case and whitespace gaps, late lock check, misplaced comment); declined
  the mutable fallback tags (BuildKit needs them).
