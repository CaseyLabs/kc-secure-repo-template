#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac

[ -f "${project_cfg_file}" ] || {
	printf 'missing %s; set PROJECT_CFG_FILE to an existing config file\n' "${project_cfg_file}" >&2
	exit 1
}

. "${project_cfg_file}"

if [ "${DEV_SCAN_ENABLE_RENOVATE:-false}" != "true" ]; then
	printf '%s\n' 'self-hosted Renovate is disabled by DEV_SCAN_ENABLE_RENOVATE'
	exit 0
fi

command -v docker >/dev/null 2>&1 || {
	printf '%s\n' 'missing required command: docker' >&2
	exit 1
}

[ -n "${RENOVATE_TOKEN:-}" ] || {
	printf '%s\n' 'missing RENOVATE_TOKEN for self-hosted Renovate' >&2
	exit 1
}

renovate_repository=${RENOVATE_REPOSITORY:-${RENOVATE_REPOSITORIES:-${GITHUB_REPOSITORY:-}}}
[ -n "${renovate_repository}" ] || {
	printf '%s\n' 'missing RENOVATE_REPOSITORY, RENOVATE_REPOSITORIES, or GITHUB_REPOSITORY' >&2
	exit 1
}

renovate_image=${DEV_RENOVATE_IMAGE_LOCK:-${DEV_RENOVATE_IMAGE:-renovate/renovate:43.113.0}}
renovate_allowed_commands='["^sh scripts/update.sh config/project.cfg$"]'

printf '\n==> Run self-hosted Renovate\n'
printf '%s\n' "Image: ${renovate_image}"
printf '%s\n' "Repository: ${renovate_repository}"

docker run --rm \
	-e LOG_LEVEL="${LOG_LEVEL:-info}" \
	-e RENOVATE_PLATFORM=github \
	-e RENOVATE_TOKEN="${RENOVATE_TOKEN}" \
	-e RENOVATE_ALLOWED_COMMANDS="${renovate_allowed_commands}" \
	-e RENOVATE_REQUIRE_CONFIG=required \
	"${renovate_image}" \
	"${renovate_repository}"
