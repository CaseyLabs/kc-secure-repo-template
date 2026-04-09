#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC2016
set -eu

# Resolve the project config file from argv or the environment.
PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}
project_env=${PROJECT_ENV}
case "${project_env}" in
/* | ./* | ../*) ;;
*) project_env="./${project_env}" ;;
esac
# Release generation needs the reviewed config and image locks.
[ -f "${project_env}" ] || {
	printf 'missing %s; copy project.env.example to %s first\n' "${project_env}" "${PROJECT_ENV}" >&2
	exit 1
}

# Load project build settings and scanner image references.
. "${project_env}"

# Allow derived repositories to swap the image name, Dockerfile, or build target.
project_image=${PROJECT_IMAGE:-kc-secure-template-dev:local}
project_dockerfile=${PROJECT_DOCKERFILE:-Dockerfile}
project_build_target=${PROJECT_BUILD_TARGET:-dev}

# Match host uid/gid for bind-mounted files and persistent cache directories.
docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}"

printf '\n==> Build project image\n'
# GitHub Actions can opt into Buildx cache export/import without changing local defaults.
if [ -n "${DOCKER_BUILD_EXTRA_ARGS:-}" ]; then
	# shellcheck disable=SC2086
	docker buildx build --load \
		${DOCKER_BUILD_EXTRA_ARGS} \
		--build-arg DEV_BASE_IMAGE="${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}}" \
		--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--build-arg DEBIAN_APT_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--target "${project_build_target}" \
		-f "${project_dockerfile}" \
		-t "${project_image}" .
else
	# Build the main project image that knows how to create the release artifact.
	docker build \
		--build-arg DEV_BASE_IMAGE="${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}}" \
		--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--build-arg DEBIAN_APT_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--target "${project_build_target}" \
		-f "${project_dockerfile}" \
		-t "${project_image}" .
fi

printf '\n==> Run release command\n'
# Delegate the archive creation logic to the template helper script inside the container.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${project_image}" \
	sh ./scripts/template.sh release

# Read release settings after the tarball exists so follow-up reports use the same defaults.
release_target=${RELEASE_INTEGRITY_TARGET:-dist/kc-secure-repo-template.tar.gz}
release_dir=${RELEASE_INTEGRITY_DIST_DIR:-dist}
release_name=${RELEASE_INTEGRITY_NAME:-$(basename "${release_target}")}
release_version=${RELEASE_INTEGRITY_VERSION:-local}
enable_sbom=${ENABLE_SBOM:-true}
enable_grype=${ENABLE_GRYPE:-true}
grype_fail_on=${GRYPE_FAIL_ON:-critical}

if [ "${enable_grype}" = 'true' ] && [ "${enable_sbom}" != 'true' ]; then
	printf '%s\n' 'ENABLE_GRYPE=true requires ENABLE_SBOM=true because Grype scans the generated SBOM' >&2
	exit 1
fi

# Store all integrity outputs next to the release artifact.
mkdir -p "${release_dir}"

# Generate an SBOM first because Grype can scan it later.
if [ "${enable_sbom}" = 'true' ]; then
	syft_image=${DEV_SCAN_SYFT_IMAGE_LOCK}
	case "${syft_image}" in
	*@sha256:*) ;;
	*)
		printf 'DEV_SCAN_SYFT_IMAGE_LOCK must be pinned by digest\n' >&2
		exit 1
		;;
	esac
	source_path="/workspace/${release_target}"
	[ -d "${release_target}" ] && source_path="dir:${source_path}"
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/workspace" \
		"${syft_image}" \
		"${source_path}" \
		--source-name "${release_name}" \
		--source-version "${release_version}" \
		-o spdx-json >"${release_dir}/template.spdx.json"
fi

# Run vulnerability scanning only when enabled and after the SBOM exists.
if [ "${enable_grype}" = 'true' ]; then
	grype_image=${DEV_SCAN_GRYPE_IMAGE_LOCK}
	case "${grype_image}" in
	*@sha256:*) ;;
	*)
		printf 'DEV_SCAN_GRYPE_IMAGE_LOCK must be pinned by digest\n' >&2
		exit 1
		;;
	esac
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/workspace" \
		"${grype_image}" \
		"sbom:/workspace/${release_dir}/template.spdx.json" \
		--fail-on "${grype_fail_on}" \
		-o table >"${release_dir}/grype-report.txt"
fi

# Hash every generated evidence file except the checksum file itself and the final report.
find "${release_dir}" -maxdepth 1 -type f ! -name SHA256SUMS ! -name SECURITY-ANALYSIS.md -print |
	LC_ALL=C sort |
	while IFS= read -r path; do
		sha256sum "${path}"
	done >"${release_dir}/SHA256SUMS"

# Write a human-readable summary that records what controls ran for this release build.
{
	printf '# Compliance Report\n\n'
	printf 'This document is generated by `scripts/dist.sh` for the built release artifacts in `%s`.\n\n' "${release_dir}"
	printf '## Scope\n\n'
	printf -- '- Name: `%s`\n' "${release_name}"
	printf -- '- Version: `%s`\n' "${release_version}"
	printf -- '- Target: `%s`\n' "${release_target}"
	printf -- '- Output directory: `%s`\n\n' "${release_dir}"
	printf '## Controls\n\n'
	printf -- '- Checksums: always generated.\n'
	if [ "${enable_sbom}" = 'true' ]; then
		printf -- '- SBOM: `%s/template.spdx.json`\n' "${release_dir}"
	else
		printf -- '- SBOM: skipped.\n'
	fi
	if [ "${enable_grype}" = 'true' ]; then
		printf -- '- Vulnerability scan: `%s/grype-report.txt`, fail on `%s`.\n' "${release_dir}" "${grype_fail_on}"
	else
		printf -- '- Vulnerability scan: skipped.\n'
	fi
	printf '\n## Checksums\n\n```\n'
	cat "${release_dir}/SHA256SUMS"
	printf '```\n'
	if [ -f "${release_dir}/grype-report.txt" ]; then
		printf '\n## Vulnerability Scan\n\n```\n'
		cat "${release_dir}/grype-report.txt"
		printf '```\n'
	fi
} >"${release_dir}/SECURITY-ANALYSIS.md"
