# This example builds a Terraform-based dev image while keeping the reviewed
# base image and nonroot runtime setup in one place.
ARG DEBIAN_APT_SNAPSHOT

FROM hashicorp/terraform:1.15.2@sha256:ffbb410cccfdb89f8d2d4d3b40abc171db747c6d2c6ee9a3ce0e10d1e838a41e AS terraform-cli
FROM debian:trixie-slim@sha256:109e2c65005bf160609e4ba6acf7783752f8502ad218e298253428690b9eaa4b AS dev-base

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
