# This example builds a Terraform-based dev image while keeping the reviewed
# base image and nonroot runtime setup in one place.
ARG DEBIAN_APT_SNAPSHOT

FROM hashicorp/terraform:1.16.5@sha256:c7926feace05d0f7e73542842bf3945924e955a1f782cf000ccbb8d18fa42d77 AS terraform-cli
FROM debian:trixie-slim@sha256:a29215f6a35e51e22adffa17f89e9d2ef06214e64a2bad10d765c46aea49f11f AS dev-base

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
# make infra supplies explicit validation and plan commands.
CMD ["terraform", "version"]
