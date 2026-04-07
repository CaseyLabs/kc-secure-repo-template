#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Read the same project config used by the other scripts so naming stays consistent.
PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}
project_env=${PROJECT_ENV}
case "${project_env}" in
/* | ./* | ../*) ;;
*) project_env="./${project_env}" ;;
esac
. "${project_env}"

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
