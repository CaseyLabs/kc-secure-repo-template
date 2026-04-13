#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Resolve the project configuration file from the first argument or environment.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
# Load image names and other settings used to start the example app.
. "${project_cfg_file}"

# Build the example container name from the configured project name.
case "${PROJECT_NAME}" in
*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
*) src_name=${PROJECT_NAME}-example ;;
esac
src_image="${src_name}:local"
container_name="${src_name}-run"

# Auto-build the image so `make run` works even if the user skipped `make build`.
if ! docker image inspect "${src_image}" >/dev/null 2>&1; then
	sh ./scripts/build.sh "${PROJECT_CFG_FILE}"
fi

# Reuse the current host user's uid/gid for writable bind mounts.
docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}"

# Remove any old container with the same name before starting a fresh one.
if docker ps -aq --filter "name=^${container_name}$" | grep -q .; then
	docker rm -f "${container_name}" >/dev/null
fi

printf '\n==> Run src container\n'
# Start the Go example in detached mode so other commands can inspect it afterward.
container_id=$(
	docker run -d \
		--name "${container_name}" \
		--user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/workspace" \
		-w /workspace \
		"${src_image}" \
		sh -eu -c 'cd src && go run ./cmd/app'
)

printf '\n==> Run summary\n'
# Echo the container id because that is the handle Docker uses for logs and cleanup.
printf '%s\n' "Image: ${src_image}"
printf '%s\n' "Container: ${container_name}"
printf '%s\n' "Container ID: ${container_id}"
