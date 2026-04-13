#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Load project configuration, defaulting to the standard config file.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
. "${project_cfg_file}"

# Use the same derived image name as the build and run scripts.
case "${PROJECT_NAME}" in
*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
*) src_name=${PROJECT_NAME}-example ;;
esac
src_image="${src_name}:local"

# Build the image on demand so the shell target works from a clean checkout.
if ! docker image inspect "${src_image}" >/dev/null 2>&1; then
	sh ./scripts/build.sh "${PROJECT_CFG_FILE}"
fi

# Match host uid/gid for writable bind mounts and caches.
docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}"

# Only allocate a terminal when stdin and stdout are both real terminals.
tty_flags='-i'
if [ -t 0 ] && [ -t 1 ]; then
	tty_flags='-i -t'
fi

printf '\n==> Start interactive shell in the src container\n'
# shellcheck disable=SC2086
# Expand tty flags as separate words so Docker receives `-i` and `-t` correctly.
docker run --rm ${tty_flags} \
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
	sh
