#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Resolve and load the selected project config.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
. "${project_cfg_file}"

# Recreate the example image name exactly the same way as the build script.
case "${PROJECT_NAME}" in
*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
*) src_name=${PROJECT_NAME}-example ;;
esac
src_image="${src_name}:local"

printf '\n==> Project Docker status\n'
printf '%s\n' "Image: ${src_image}"
printf '%s\n' 'Built images:'

# Show the built image if it exists; otherwise explain that nothing has been built yet.
if docker image inspect "${src_image}" >/dev/null 2>&1; then
	image_id=$(docker image inspect --format '{{.Id}}' "${src_image}")
	docker image ls --filter "reference=${src_image}" --format '  {{.Repository}}:{{.Tag}} | {{.ID}} | {{.Size}} | {{.CreatedSince}}'
else
	image_id=''
	printf '%s\n' '  none'
fi

printf '%s\n' 'Running containers:'
# Docker can filter running containers by the built image id.
if [ -n "${image_id}" ]; then
	docker ps --filter "ancestor=${image_id}" --format '  {{.ID}} | {{.Image}} | {{.Status}} | {{.Names}}'
else
	printf '%s\n' '  none'
fi
