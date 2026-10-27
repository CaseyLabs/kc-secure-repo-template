# syntax=docker/dockerfile:1

# `ARG` values are build-time inputs. The Makefile/scripts pass these in so the
# same Dockerfile can be reused across derived repositories.
ARG DEV_BASE_IMAGE
ARG DEV_PACKAGE_SNAPSHOT
# Used only by the optional `runtime` stages at the bottom. `FROM` can only read
# ARGs declared before the first `FROM`, so they live here.
ARG RUNTIME_BUILD_IMAGE
ARG RUNTIME_BASE_IMAGE

# --- Optional runtime image (opt-in) ---------------------------------------
# These two stages are only built when a build targets `runtime`, which
# `make build` does when `PROJECT_RUNTIME_IMAGE` is set in `config/project.cfg`.
# The `dev` target below never uses them, so a default build is unchanged.
# The fallback tags only exist because BuildKit rejects a blank `FROM` in any
# stage, even one it does not build. `make build` always passes the digest locks
# and refuses to build the runtime image without them. `make scan` and
# `make dist` also pass the locks, and refuse any `PROJECT_BUILD_TARGET` (or scan
# target) other than `dev` unless both are digest-pinned.
# The legacy builder (`DOCKER_BUILDKIT=0`) builds every stage above the target,
# so it would pull these fallback tags even for `--target dev`; the build, scan,
# and dist scripts refuse it.
# They sit above `dev` on purpose: a plain `docker build .` with no `--target`
# builds the last stage, which must stay the dev image.

# Stage 1: compile the example in the pinned Go image. Nothing from this stage
# reaches the final image except the compiled binary.
FROM ${RUNTIME_BUILD_IMAGE:-golang:trixie} AS runtime-build
WORKDIR /build
# Use only the Go toolchain in the pinned image. Without this, raising the `go`
# or `toolchain` line in `src/go.mod` makes `go build` download a newer
# toolchain during the build, bypassing the digest lock.
ENV GOTOOLCHAIN=local
COPY src/ ./
# CGO_ENABLED=0 produces a static binary that runs on the shell-less `static`
# distroless base. `-trimpath` and `-buildvcs=false` keep the output
# reproducible. Tests are not run here; `make test` covers them.
RUN CGO_ENABLED=0 go build -trimpath -buildvcs=false -o /out/app ./cmd/app

# Stage 2: copy only the binary into the minimal distroless base. The `:nonroot`
# tag already defaults to an unprivileged user; `USER` below states it
# explicitly so the policy check and reviewers can see it.
FROM ${RUNTIME_BASE_IMAGE:-gcr.io/distroless/static-debian13:nonroot} AS runtime
COPY --from=runtime-build /out/app /app
USER nonroot:nonroot
# Exec form (JSON array): distroless has no shell, and exec form keeps the app
# as PID 1 so it receives stop signals directly.
ENTRYPOINT ["/app"]

# --- Development and CI image -----------------------------------------------
# Start from the configured base image. The default keeps this template usable
# even if a build does not explicitly override the value.
FROM ${DEV_BASE_IMAGE:-debian:trixie-slim} AS dev

# Re-declare the argument after `FROM` so it is available in this stage.
ARG DEV_PACKAGE_SNAPSHOT

# Replace Debian's normal package mirrors with a snapshot mirror pinned to a
# specific date. That makes package installs reproducible: users can rebuild
# later and get the same package set instead of "whatever is newest today".
# The cleanup at the end removes apt cache files so the image stays smaller.
RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    printf '%s\n' \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEV_PACKAGE_SNAPSHOT} trixie main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEV_PACKAGE_SNAPSHOT} trixie-updates main" \
        "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${DEV_PACKAGE_SNAPSHOT} trixie-security main" \
        >/etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false update && \
    apt-get install -y --no-install-recommends bash ca-certificates curl git jq make tar gzip && \
    rm -rf /var/lib/apt/lists/*

# Create a dedicated unprivileged user instead of running as root. This is a
# safer default for local development and for CI jobs that use this image.
RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid 10001 --create-home --home-dir /home/app --shell /usr/sbin/nologin app

# `/workspace` is where repository files will live inside the container.
WORKDIR /workspace
# Some tools look at `$HOME` for configuration and temporary files, so point it
# at the home directory we created for the non-root user.
ENV HOME=/home/app
# Use only the Go toolchain in the pinned base image, matching `runtime-build`.
# With Go's default (`auto`), raising the `go` or `toolchain` line in
# `src/go.mod` past the image makes `make build`/`make test` download a newer
# toolchain, bypassing the DEV_GO_IMAGE_LOCK digest. With `local`, Go ignores
# the `toolchain` line, and a newer `go` line fails with
# "go.mod requires go >= X (running go Y; GOTOOLCHAIN=local)". Raise
# DEV_GO_IMAGE in config/project.cfg and run `make update` instead.
# The official golang images already set this; stating it here keeps the policy
# from depending on the upstream image, and `make scan` checks it is present. A
# derived repo with a non-Go base image can keep it: nothing else reads it.
ENV GOTOOLCHAIN=local
# All following instructions and the default command run as the `app` user.
USER app:app

# Copy the repository into the image after the environment is prepared.
COPY . .

# The default command is intentionally a short help message instead of an app
# entrypoint. This repository is a template, so derived projects are expected to
# replace this with their own real runtime command later.
CMD ["sh", "-eu", "-c", \
    "printf '%s\n' \
    'Template development image ready.' \
    'Use the Makefile entrypoints for the bundled workflow:' \
    '  make build' \
    '  make test' \
    '  make run' \
    'Replace this Dockerfile CMD in derived repositories with your project command.'"]
