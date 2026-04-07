#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Load the project config so we can derive the matching example image name.
PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}
project_env=${PROJECT_ENV}
case "${project_env}" in
/* | ./* | ../*) ;;
*) project_env="./${project_env}" ;;
esac
. "${project_env}"

# Keep naming logic in sync with build/run/status.
case "${PROJECT_NAME}" in
*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
*) src_name=${PROJECT_NAME}-example ;;
esac
src_image="${src_name}:local"

printf '\n==> Project container logs\n'
printf '%s\n' "Image: ${src_image}"

# If the image does not exist yet, there cannot be any related running containers.
if ! docker image inspect "${src_image}" >/dev/null 2>&1; then
	printf '%s\n' 'Running containers: none'
	exit 0
fi

# Find all running containers created from this image.
image_id=$(docker image inspect --format '{{.Id}}' "${src_image}")
container_ids=$(docker ps --filter "ancestor=${image_id}" --format '{{.ID}}')
[ -n "${container_ids}" ] || {
	printf '%s\n' 'Running containers: none'
	exit 0
}

# Print each container's logs separately so users can tell them apart.
for container_id in ${container_ids}; do
	printf '\n%s\n' "--- ${container_id} ---"
	docker logs "${container_id}"
done
