# This example builds a Terraform-based dev image while keeping the reviewed
# base image and nonroot runtime setup in one place.
ARG DEBIAN_APT_SNAPSHOT

FROM hashicorp/terraform:1.14.9@sha256:1d10ec4073f4ddbdf34a28540a3b9250852ab500cb1c53f68c8bd17d82f474d8 AS terraform-cli
FROM debian:trixie-slim@sha256:cedb1ef40439206b673ee8b33a46a03a0c9fa90bf3732f54704f99cb061d2c5a AS dev-base

ARG DEBIAN_APT_SNAPSHOT

RUN rm -f /etc/apt/sources.list.d/debian.sources && \
    printf '%s\n' \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_APT_SNAPSHOT} trixie main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_APT_SNAPSHOT} trixie-updates main" \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian-security/${DEBIAN_APT_SNAPSHOT} trixie-security main" \
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
CMD ["sh", "-eu", "-c", "project_cfg_file=${PROJECT_CFG_FILE:-config/project.cfg}; case ${project_cfg_file} in /*|./*|../*) ;; *) project_cfg_file=./${project_cfg_file} ;; esac; . ${project_cfg_file}; ( eval \"${LINT_COMMAND}\" ); ( eval \"${TEST_COMMAND}\" ); ( eval \"${BUILD_COMMAND}\" )"]
