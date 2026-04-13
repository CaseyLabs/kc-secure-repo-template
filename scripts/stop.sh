#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Read the same project config used by the other scripts so naming stays consistent.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
. "${project_cfg_file}"

# The run script always uses this derived container name.
case "${PROJECT_NAME}" in
*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
*) src_name=${PROJECT_NAME}-example ;;
esac
container_name="${src_name}-run"

printf '\n==> Stop src container\n'
# Treat "already stopped" as a normal outcome instead of an error.
if ! docker ps -aq --filter "name=^${container_name}$" | grep -q .; then
	printf '%s\n' "Container not running: ${container_name}"
	exit 0
fi

# Stop the container first, then remove it so the next run starts cleanly.
docker stop "${container_name}" >/dev/null
docker rm "${container_name}" >/dev/null
printf '%s\n' "Stopped: ${container_name}"
