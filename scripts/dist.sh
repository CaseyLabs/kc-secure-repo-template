#!/bin/sh
# shellcheck shell=sh disable=SC1090,SC2016
set -eu

# Resolve the project config file from argv or the environment.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
# Release generation needs the reviewed config and image locks.
[ -f "${project_cfg_file}" ] || {
	printf 'missing %s; set PROJECT_CFG_FILE to an existing config file\n' "${project_cfg_file}" >&2
	exit 1
}

# Load project build settings and scanner image references.
publication_requested=${RELEASE_PUBLICATION:-false}
env_enable_sbom=${ENABLE_SBOM-}
env_enable_grype=${ENABLE_GRYPE-}
env_grype_fail_on=${GRYPE_FAIL_ON-}
. "${project_cfg_file}"
RELEASE_PUBLICATION=${publication_requested}
export RELEASE_PUBLICATION
# Workflow variables are the effective release settings even if a derived
# config supplies local defaults for the same fields.
ENABLE_SBOM=${env_enable_sbom:-${ENABLE_SBOM:-true}}
ENABLE_GRYPE=${env_enable_grype:-${ENABLE_GRYPE:-true}}
GRYPE_FAIL_ON=${env_grype_fail_on:-${GRYPE_FAIL_ON:-critical}}
export ENABLE_SBOM ENABLE_GRYPE GRYPE_FAIL_ON

# A release cannot bypass the publication gate by changing local packaging
# flags. Disposable local archives may still disable scanners for fast tests.
sh ./scripts/release-policy.sh
if [ "${RELEASE_PUBLICATION:-false}" = true ] &&
	{ [ "${ENABLE_SBOM:-true}" = false ] || [ "${ENABLE_GRYPE:-true}" = false ]; }; then
	exception_file=${RELEASE_EXCEPTION_FILE:-config/release-exception.cfg}
	case "${exception_file}" in
	/*|./*|../*) . "${exception_file}" ;;
	*) . "./${exception_file}" ;;
	esac
fi

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

# Store all integrity outputs next to the release artifact.
mkdir -p "${release_dir}"
# The template helper always writes its manifest under dist/. Keep a copy in
# the evidence directory, avoiding a same-file copy for equivalent paths.
if [ "$(cd "${release_dir}" && pwd -P)" != "$(cd dist && pwd -P)" ]; then
	cp dist/template-manifest.txt "${release_dir}/template-manifest.txt"
fi
rm -f "${release_dir}/SECURITY-ANALYSIS.md" "${release_dir}/SHA256SUMS" "${release_dir}/ARCHIVE-SHA256SUMS" "${release_dir}/grype-report.txt" "${release_dir}/template.spdx.json"

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

# Record the final archive bytes before writing evidence that names them.
sha256sum "${release_target}" >"${release_dir}/ARCHIVE-SHA256SUMS"
archive_digest=$(cut -d ' ' -f 1 "${release_dir}/ARCHIVE-SHA256SUMS")
source_commit=${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || printf unknown)}
run_identity=${GITHUB_RUN_ID:-local}

# Write a human-readable summary that records what controls ran for this release build.
{
	printf '# Release Integrity Report\n\n'
	printf 'This document is generated by `scripts/dist.sh` for the built release artifacts in `%s`.\n\n' "${release_dir}"
	printf '## Scope\n\n'
	printf -- '- Name: `%s`\n' "${release_name}"
	printf -- '- Version: `%s`\n' "${release_version}"
	printf -- '- Target: `%s`\n' "${release_target}"
	printf -- '- Output directory: `%s`\n\n' "${release_dir}"
	printf -- '- Archive SHA-256: `%s`\n' "${archive_digest}"
	printf -- '- Source commit: `%s`\n' "${source_commit}"
	printf -- '- Build run: `%s`\n' "${run_identity}"
	if [ -n "${GITHUB_SERVER_URL:-}" ] && [ -n "${GITHUB_REPOSITORY:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
		printf -- '- Workflow evidence: %s/%s/actions/runs/%s\n' "${GITHUB_SERVER_URL}" "${GITHUB_REPOSITORY}" "${GITHUB_RUN_ID}"
	fi
	printf '\n'
	printf '## Published Release Assets\n\n'
	printf -- '- `%s/%s`\n' "${release_dir}" "$(basename "${release_target}")"
	printf -- '- `%s/ARCHIVE-SHA256SUMS`\n' "${release_dir}"
	printf -- '- `%s/SECURITY-ANALYSIS.md`\n' "${release_dir}"
	printf -- '- `%s/SHA256SUMS`\n' "${release_dir}"
	printf -- '- `%s/template-manifest.txt`\n' "${release_dir}"
	if [ "${enable_sbom}" = 'true' ]; then
		printf -- '- `%s/template.spdx.json`\n' "${release_dir}"
	fi
	if [ "${enable_grype}" = 'true' ]; then
		printf -- '- `%s/grype-report.txt`\n' "${release_dir}"
	fi
	printf '\n## Workflow Artifact Bundle\n\n'
	printf 'The complete `%s` directory is retained as the release workflow artifact bundle for CI evidence.\n\n' "${release_dir}"
	printf -- '- `%s/ARCHIVE-SHA256SUMS` verifies the generated template archive.\n\n' "${release_dir}"
	printf '## Controls\n\n'
	printf -- '- Checksums: `%s/SHA256SUMS` covers the published release assets generated before the checksum file.\n' "${release_dir}"
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
	printf -- '- Publication exception: `%s`.\n' "${RELEASE_EXCEPTION_ID:-none}"
	if [ -f "${release_dir}/grype-report.txt" ]; then
		printf '\n## Vulnerability Scan\n\n```\n'
		cat "${release_dir}/grype-report.txt"
		printf '```\n'
	fi
} >"${release_dir}/SECURITY-ANALYSIS.md"

# Hash published release assets that exist before the checksum file is written.
{
	sha256sum "${release_target}"
	sha256sum "${release_dir}/ARCHIVE-SHA256SUMS"
	sha256sum "${release_dir}/SECURITY-ANALYSIS.md"
	sha256sum "${release_dir}/template-manifest.txt"
	for asset in template.spdx.json grype-report.txt; do
		if [ -f "${release_dir}/${asset}" ]; then
			sha256sum "${release_dir}/${asset}"
		fi
	done
} >"${release_dir}/SHA256SUMS"
