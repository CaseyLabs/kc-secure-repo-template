#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Resolve the project config file from argv or the environment.
PROJECT_ENV=${1:-${PROJECT_ENV:-project.env}}
project_env=${PROJECT_ENV}
case "${project_env}" in
/* | ./* | ../*) ;;
*) project_env="./${project_env}" ;;
esac
# Refuse to continue without the reviewed project configuration.
[ -f "${project_env}" ] || {
	printf 'missing %s; copy project.env.example to %s first\n' "${project_env}" "${PROJECT_ENV}" >&2
	exit 1
}

# Load build settings and pinned scanner image references.
. "${project_env}"

# Allow derived repositories to change the image name, Dockerfile, or build target.
project_image=${PROJECT_IMAGE:-kc-secure-template-dev:local}
project_dockerfile=${PROJECT_DOCKERFILE:-Dockerfile}
project_build_target=${PROJECT_BUILD_TARGET:-dev}

# Match the container runtime user to the host user for bind-mounted files.
docker_uid=${DOCKER_UID:-$(id -u)}
docker_gid=${DOCKER_GID:-$(id -g)}
docker_home=${DOCKER_HOME:-/tmp/kc-template-home}
docker_cache_home=${DOCKER_CACHE_HOME:-${docker_home}/.cache}
docker_home_source=${DOCKER_HOME_SOURCE:-$(pwd)/.cache/docker-home}
docker_tmpdir=${DOCKER_TMPDIR:-$(pwd)/.cache/docker-tmp}
mkdir -p "${docker_home_source}" "${docker_tmpdir}"

# Read every external GitHub Action reference from workflow files.
list_workflow_entries() {
	for workflow in .github/workflows/*.yml; do
		awk -v workflow="${workflow}" '
			/^[[:space:]]*-[[:space:]]+uses:[[:space:]]+/ || /^[[:space:]]+uses:[[:space:]]+/ {
				ref = $0
				sub(/^[[:space:]]*-[[:space:]]+uses:[[:space:]]+/, "", ref)
				sub(/^[[:space:]]*uses:[[:space:]]+/, "", ref)
				comment = ""
				if (match(ref, /[[:space:]]+#.*$/)) {
					comment = substr(ref, RSTART + 1)
					sub(/^[[:space:]]+/, "", comment)
					sub(/^#[[:space:]]*/, "", comment)
					sub(/[[:space:]]+$/, "", comment)
					sub(/[[:space:]]+#.*$/, "", ref)
				}
				sub(/[[:space:]]+$/, "", ref)
				if (ref ~ /^(\.\/|\.\.\/)/) {
					next
				}
				printf "%s\t%s\t%s\n", workflow, ref, comment
			}
		' "${workflow}"
	done
}

# Enforce "pin by full SHA" plus a nearby reviewed tag comment for every action.
check_workflow_action_pins() {
	list_workflow_entries | while IFS="$(printf '\t')" read -r workflow ref comment; do
		case "${ref}" in
		*/*@[0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
			sha=${ref##*@}
			printf '%s\n' "${sha}" | grep -Eq '^[0-9a-f]{40}$' || {
				printf '%s must pin actions by full SHA: %s\n' "${workflow}" "${ref}" >&2
				exit 1
			}
			;;
		*)
			printf '%s uses an invalid action ref: %s\n' "${workflow}" "${ref}" >&2
			exit 1
			;;
		esac

		case "${comment}" in
		v*) ;;
		*)
			printf '%s must keep a reviewed release tag comment for %s\n' "${workflow}" "${ref}" >&2
			exit 1
			;;
		esac
	done
}

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
	# Build the main dev image before running syntax and template checks inside it.
	docker build \
		--build-arg DEV_BASE_IMAGE="${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}}" \
		--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--build-arg DEBIAN_APT_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--target "${project_build_target}" \
		-f "${project_dockerfile}" \
		-t "${project_image}" .
fi

printf '\n==> Run lint, test, and build commands\n'
# Syntax-check every shell script and regenerate the template manifest inside the container.
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
	sh -eu -c 'find scripts -type f -name '"'"'*.sh'"'"' -print | LC_ALL=C sort | while IFS= read -r path; do sh -n "${path}"; done && sh ./scripts/template.sh manifest'

# Secret scanning is security-sensitive, so require a digest-pinned scanner image.
secret_scan_image=${DEV_SCAN_GITLEAKS_IMAGE_LOCK}
case "${secret_scan_image}" in
*@sha256:*) ;;
*)
	printf 'DEV_SCAN_GITLEAKS_IMAGE_LOCK must be pinned by digest\n' >&2
	exit 1
	;;
esac

printf '\n==> Run secret scan\n'
# Prefer Git-aware scanning so removed-but-still-reachable secrets in history are caught.
if [ -d .git ]; then
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/repo" \
		-w /repo \
		"${secret_scan_image}" \
		detect --source /repo --no-banner --redact --exit-code 1
else
	# Fall back to plain filesystem scanning when Git metadata is unavailable.
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/repo" \
		"${secret_scan_image}" \
		detect --source /repo --no-git --no-banner --redact --exit-code 1
fi

printf '\n==> Run workflow lint\n'
# Use actionlint in a container so CI and local runs use the same tool version.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${DEV_SCAN_ACTIONLINT_IMAGE_LOCK}" \
	-shellcheck= \
	-pyflakes= \
	.github/workflows/*.yml

trivy_scan_image=${DEV_SCAN_TRIVY_IMAGE_LOCK}
case "${trivy_scan_image}" in
*@sha256:*) ;;
*)
	printf 'DEV_SCAN_TRIVY_IMAGE_LOCK must be pinned by digest\n' >&2
	exit 1
	;;
esac

printf '\n==> Run misconfiguration scan\n'
# Trivy complements the other scanners by checking Dockerfile posture issues.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-e TRIVY_CACHE_DIR="${docker_cache_home}/trivy" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${trivy_scan_image}" \
	fs \
	--scanners misconfig \
	--misconfig-scanners dockerfile \
	--severity HIGH,CRITICAL \
	--exit-code 1 \
	--skip-version-check \
	/workspace

printf '\n==> Check workflow pins\n'
# Finally, verify that workflow action references stay fully pinned and documented.
check_workflow_action_pins
