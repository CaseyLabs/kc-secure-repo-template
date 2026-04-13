#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Load the project config if it exists; `clean` still works with fallback defaults.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
[ -f "${project_cfg_file}" ] && . "${project_cfg_file}"

# Fall back to the template defaults so cleanup still works if the config file is missing.
case "${PROJECT_NAME:-kc-secure-template-dev}" in
*-dev) src_name=${PROJECT_NAME%-dev}-example ;;
*) src_name=${PROJECT_NAME:-kc-secure-template-dev}-example ;;
esac
src_image="${src_name}:local"
root_image="${PROJECT_IMAGE:-kc-secure-template-dev:local}"
container_name="${src_name}-run"

printf '\n==> Remove generated artifacts, caches, and local project images\n'
# Remove the example runtime container if it still exists.
if docker ps -aq --filter "name=^${container_name}$" | grep -q .; then
	docker rm -f "${container_name}" >/dev/null
fi

# Delete both the example image and the main project image when present.
for image in "${src_image}" "${root_image}"; do
	if docker image inspect "${image}" >/dev/null 2>&1; then
		docker image rm -f "${image}" >/dev/null
	fi
done

# Clear local build outputs and temporary caches created by the scripts.
rm -rf dist .cache .tmp
