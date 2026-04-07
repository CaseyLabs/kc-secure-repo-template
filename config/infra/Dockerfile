# This example builds a Terraform-based dev image while keeping the reviewed
# base image and nonroot runtime setup in one place.
ARG DEBIAN_APT_SNAPSHOT

FROM hashicorp/terraform:1.14.8@sha256:42ecfb253183ec823646dd7859c5652039669409b44daa72abf57112e622849a AS terraform-cli
FROM debian:bookworm-slim@sha256:4724b8cc51e33e398f0e2e15e18d5ec2851ff0c2280647e1310bc1642182655d AS dev-base

ARG DEBIAN_APT_SNAPSHOT

RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    printf '%s\n' \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_APT_SNAPSHOT} bookworm main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_APT_SNAPSHOT} bookworm-updates main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${DEBIAN_APT_SNAPSHOT} bookworm-security main" \
      >/etc/apt/sources.list && \
    apt-get -o Acquire::Check-Valid-Until=false update && \
    apt-get install -y --no-install-recommends ca-certificates curl unzip && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid 10001 --create-home --home-dir /home/app --shell /usr/sbin/nologin app

WORKDIR /workspace
ENTRYPOINT []
COPY . .

FROM dev-base AS dev
COPY --from=terraform-cli /bin/terraform /usr/local/bin/terraform
USER app:app
CMD ["sh", "-eu", "-c", "project_env=${PROJECT_ENV:-project.env}; case ${project_env} in /*|./*|../*) ;; *) project_env=./${project_env} ;; esac; . ${project_env}; ( eval \"${LINT_COMMAND}\" ); ( eval \"${TEST_COMMAND}\" ); ( eval \"${BUILD_COMMAND}\" )"]
