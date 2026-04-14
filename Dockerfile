# syntax=docker/dockerfile:1

# `ARG` values are build-time inputs. The Makefile/scripts pass these in so the
# same Dockerfile can be reused across derived repositories.
ARG DEV_BASE_IMAGE
ARG DEV_PACKAGE_SNAPSHOT

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
