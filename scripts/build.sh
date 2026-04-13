#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC2016
set -eu

# Let callers override the config file, but default to the checked-in project config.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
# Turn bare filenames into a path relative to the repository root.
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
# Stop early with a helpful message if the config file is missing.
[ -f "${project_cfg_file}" ] || {
	printf 'missing %s; set PROJECT_CFG_FILE to an existing config file\n' "${project_cfg_file}" >&2
	exit 1
}

# Load project settings such as image names and pinned tool images.
. "${project_cfg_file}"

# Reuse the project name to derive the example image name used by the bundled Go app.
case "${PROJECT_NAME}" in
*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
*) src_name=${PROJECT_NAME}-example ;;
esac
src_image="${src_name}:local"

# Match container file ownership to the current host user so generated files stay editable.
docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}"

printf '\n==> Build src image\n'
# GitHub Actions can opt into Buildx cache export/import without changing local defaults.
if [ -n "${DOCKER_BUILD_EXTRA_ARGS:-}" ]; then
	# shellcheck disable=SC2086
	docker buildx build --load \
		${DOCKER_BUILD_EXTRA_ARGS} \
		--build-arg DEV_BASE_IMAGE="${DEV_GO_IMAGE_LOCK}" \
		--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--build-arg DEBIAN_APT_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--target dev \
		-f Dockerfile \
		-t "${src_image}" .
else
	# Build the Go example image first; later steps run inside this container.
	docker build \
		--build-arg DEV_BASE_IMAGE="${DEV_GO_IMAGE_LOCK}" \
		--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--build-arg DEBIAN_APT_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--target dev \
		-f Dockerfile \
		-t "${src_image}" .
fi

printf '\n==> Build src workspace\n'
# Run the actual application build inside the container so host toolchains are not required.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${src_image}" \
	sh -eu -c 'cd src && go build -trimpath -buildvcs=false ./cmd/app'

printf '\n==> Build summary\n'
# Print a short recap so users can see which image and config were used.
printf '%s\n' "Image: ${src_image}"
printf '%s\n' "Project config: ${PROJECT_CFG_FILE}"
printf '%s\n' 'Workspace: src'
printf '%s\n' 'Result: build passed'
