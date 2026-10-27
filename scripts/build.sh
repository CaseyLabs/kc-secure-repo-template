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
# Read the workflow commands only from the config, never from the caller's
# environment, so an exported variable cannot replace the reviewed command.
unset PROJECT_BUILD_COMMAND PROJECT_LINT_COMMAND PROJECT_TEST_COMMAND PROJECT_RUN_COMMAND
. "${project_cfg_file}"

# Workflow commands run through `sh -eu -c` in the existing non-root dev
# container. Fall back to the Go example commands so older layered configs that
# predate these settings keep working unchanged. Only an unset variable falls
# back; an explicitly empty command is a deliberate no-op.
project_build_command=${PROJECT_BUILD_COMMAND-'cd src && go build -trimpath -buildvcs=false ./cmd/app'}
# Opt-in distroless runtime image; blank (or unset in older configs) skips it.
project_runtime_image=${PROJECT_RUNTIME_IMAGE-}

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

# Opt-in distroless runtime image. It does not depend on the dev image, so it is
# built first: the lock checks then fail fast, before the slower dev build.
# Both locks must be digest-pinned, so the build never falls back to a mutable tag.
. ./scripts/workflow-policy.sh
if [ -n "${project_runtime_image}" ]; then
	require_pinned_lock DEV_GO_IMAGE_LOCK "${DEV_GO_IMAGE_LOCK:-}" "build PROJECT_RUNTIME_IMAGE"
	require_pinned_lock DEV_DISTROLESS_STATIC_IMAGE_LOCK "${DEV_DISTROLESS_STATIC_IMAGE_LOCK:-}" "build PROJECT_RUNTIME_IMAGE"
	printf '\n==> Build runtime image\n'
	# Plain `docker build` (no Buildx cache) keeps this path simple; the stage is small.
	docker build \
		--build-arg RUNTIME_BUILD_IMAGE="${DEV_GO_IMAGE_LOCK}" \
		--build-arg RUNTIME_BASE_IMAGE="${DEV_DISTROLESS_STATIC_IMAGE_LOCK}" \
		--target runtime \
		-f Dockerfile \
		-t "${project_runtime_image}" .
fi

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
	# Build the dev image first; later steps run inside this container.
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
	sh -eu -c "${project_build_command}"

printf '\n==> Build summary\n'
# Print a short recap so users can see which image and config were used.
printf '%s\n' "Image: ${src_image}"
printf '%s\n' "Project config: ${PROJECT_CFG_FILE}"
printf '%s\n' "Build command: ${project_build_command}"
if [ -n "${project_runtime_image}" ]; then
	printf '%s\n' "Runtime image: ${project_runtime_image}"
fi
printf '%s\n' 'Result: build passed'
