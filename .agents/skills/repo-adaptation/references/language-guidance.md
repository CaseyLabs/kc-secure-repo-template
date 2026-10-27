# Language profile guidance

Use this reference when adding or revising optional language-specific guidance for derived repositories.

## Use this reference when
- updating Go, Node.js, Python, SQL, or polyglot guidance
- revising language-specific documentation
- deciding whether a language-specific check belongs in the template, docs, or a derived repository
- extending default validation guidance for a specific ecosystem

## Do not read this reference when
- the task is about generic template policy
- the task is about GitHub-side settings
- the task is about release-integrity design
- the task is just routine validation of existing behavior
- the task would make one language stack mandatory for all derived repositories

## Goals
- Improve usability for common project types without turning the template into a framework.
- Keep language-specific logic optional.
- Preserve the generic template's stable interface and security posture.

## Method
- Keep language-specific behavior optional rather than mandatory in the generic template.
- Do not break generic usage for repositories that do not use that language stack.
- Prefer documentation and examples over hard-coding specialized behavior into the base template.
- Keep the public interface stable even when language-specific implementation details differ.
- When adding language-specific checks, explain where they belong: template, docs, CI helper scripts, or derived repositories.
- Follow the parent repo-adaptation workflow when language guidance changes the customization surface.

## Guidance areas
- Go: formatting, vetting, tests, vulnerability checks
- Node.js: lockfile-based installs, deterministic CI commands (see "Node.js and Python stacks")
- Python: hashed requirements, builder/runtime version match (see "Node.js and Python stacks")
- SQL: read-only validation in CI, dialect-appropriate linting or formatting
- Polyglot: keep one clear primary build path

## Node.js and Python stacks
- Scope: Node.js and Python are supported by guidance only. The template keeps the Go example; nothing below is merged into the template's `Dockerfile` or `config/project.cfg`.
- These changes belong in a **derived repository**, not the template. Make them in the derived repo's `config/project.cfg` and `Dockerfile`, then run `make update` to refresh `config/lockfile.cfg`.
- Variable names stay as the template defines them, even when the stack is not Go:
  - `DEV_GO_IMAGE` is the dev and builder image for every stack (the name is historical). Point it at the stack's image, for example `node:24-trixie` or `python:3.13-trixie`.
  - `DEV_DISTROLESS_STATIC_IMAGE` is the runtime base. Point it at the matching distroless image and keep the `:nonroot` tag.
  - `RUNTIME_BUILD_IMAGE` and `RUNTIME_BASE_IMAGE` receive those two digest-locked values from `scripts/build.sh`, `scripts/scan.sh`, and `scripts/dist.sh`.
  - A `PROJECT_BUILD_TARGET` other than `dev` needs both locks digest-pinned, or `make scan` and `make dist` refuse to build.
- The runtime stage must keep what `make scan` checks: `FROM ${RUNTIME_BASE_IMAGE...}`, a non-root `USER`, and an exec-form `ENTRYPOINT`.
- Commands run as `sh -eu -c` in the dev container from `/workspace`, so each example uses `cd src &&`.

### Node.js
- Commit `package-lock.json` and install only with `npm ci`, which fails when the lockfile and `package.json` disagree. Never use `npm install` in the workflow.
- Use the same major version in the builder and the runtime: `node:24-trixie` pairs with `gcr.io/distroless/nodejs24-debian13:nonroot`. Change both together.
- `--ignore-scripts` stops dependency install scripts from running; drop it only for a dependency that needs a native build, and review that dependency.
- `make build` runs `npm ci` in the bind-mounted checkout, so `src/node_modules` exists on the host. Add `**/node_modules` to `.dockerignore` (the template's `node_modules` entry only matches the repository root), or `COPY src/ ./` replaces the image's clean install with the host's tree, devDependencies included.

```shell
# config/project.cfg
DEV_GO_IMAGE='node:24-trixie'
DEV_DISTROLESS_STATIC_IMAGE='gcr.io/distroless/nodejs24-debian13:nonroot'
PROJECT_BUILD_COMMAND='cd src && npm ci --ignore-scripts && npm run build'
PROJECT_LINT_COMMAND='cd src && npm run lint'
PROJECT_TEST_COMMAND='cd src && npm test'
PROJECT_RUN_COMMAND='cd src && node index.js'
```

```dockerfile
# Dockerfile: replace the Go runtime stages
FROM ${RUNTIME_BUILD_IMAGE:-node:24-trixie} AS runtime-build
WORKDIR /build
# Copy the manifests first so the install layer is cached until they change.
COPY src/package.json src/package-lock.json ./
RUN npm ci --ignore-scripts
COPY src/ ./
# Build, then drop devDependencies so only runtime packages are shipped.
RUN npm run build && npm prune --omit=dev

FROM ${RUNTIME_BASE_IMAGE:-gcr.io/distroless/nodejs24-debian13:nonroot} AS runtime
WORKDIR /app
COPY --from=runtime-build /build /app
USER nonroot:nonroot
# Exec form with the distroless node path; there is no shell in this image.
ENTRYPOINT ["/nodejs/bin/node", "index.js"]
```

### Python
- The builder's Python must match the distroless runtime's. `gcr.io/distroless/python3-debian13` ships Debian 13's Python 3.13, so use `python:3.13-trixie` as the builder and check the versions again when either image moves.
- Install only from a hashed requirements file with `--require-hashes`, which also forces every dependency to be pinned. Generate it with `pip-compile --generate-hashes` (pip-tools) or `uv pip compile --generate-hashes`, and commit it.
- Add `--no-deps` (the hashed file already lists every dependency) and `--only-binary=:all:` so no source distribution runs build code at install time.
- Pin pip itself too: the builder image fixes its version, so do not run `pip install --upgrade pip`.
- Install into a directory under `src/` and set `PYTHONPATH` to it in both places: in `PROJECT_RUN_COMMAND` for `make run`, and with `ENV` in the runtime image.
- Add `src/.deps/` to `.gitignore` and `src/.deps` to `.dockerignore`. Otherwise the host install gets committed by accident, and `COPY src/ ./app/` ships a second, dev-image copy of the dependencies next to the hash-verified `/app/deps`.

```shell
# config/project.cfg
DEV_GO_IMAGE='python:3.13-trixie'
DEV_DISTROLESS_STATIC_IMAGE='gcr.io/distroless/python3-debian13:nonroot'
PROJECT_BUILD_COMMAND='cd src && python -m pip install --require-hashes --no-deps --only-binary=:all: --target .deps -r requirements.txt'
PROJECT_LINT_COMMAND='cd src && PYTHONPATH=.deps python -m ruff check .'
PROJECT_TEST_COMMAND='cd src && PYTHONPATH=.deps python -m unittest discover'
PROJECT_RUN_COMMAND='cd src && PYTHONPATH=.deps python main.py'
```

- The lint example assumes `ruff` is listed, with hashes, in `requirements.txt`. Swap in the project's own linter.

```dockerfile
# Dockerfile: replace the Go runtime stages
FROM ${RUNTIME_BUILD_IMAGE:-python:3.13-trixie} AS runtime-build
WORKDIR /build
COPY src/requirements.txt ./
RUN python -m pip install --require-hashes --no-deps --only-binary=:all: --target /build/deps -r requirements.txt
COPY src/ ./app/

FROM ${RUNTIME_BASE_IMAGE:-gcr.io/distroless/python3-debian13:nonroot} AS runtime
WORKDIR /app
COPY --from=runtime-build /build/deps /app/deps
COPY --from=runtime-build /build/app /app
# Same PYTHONPATH idea as `make run`, pointing at the copied packages.
ENV PYTHONPATH=/app/deps
USER nonroot:nonroot
ENTRYPOINT ["/usr/bin/python3", "/app/main.py"]
```

## Output expectations
- State what language-specific guidance changed.
- Explain why it remains optional.
- Note whether the change belongs in docs, scripts, examples, or derived repositories.
