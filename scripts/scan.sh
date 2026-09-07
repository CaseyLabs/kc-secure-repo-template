#!/bin/sh
# shellcheck shell=sh disable=SC1090
set -eu

# Resolve the project config file from argv or the environment.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
project_cfg_file=${PROJECT_CFG_FILE}
case "${project_cfg_file}" in
/* | ./* | ../*) ;;
*) project_cfg_file="./${project_cfg_file}" ;;
esac
# Refuse to continue without the reviewed project configuration.
[ -f "${project_cfg_file}" ] || {
	printf 'missing %s; set PROJECT_CFG_FILE to an existing config file\n' "${project_cfg_file}" >&2
	exit 1
}

# Load build settings and pinned scanner image references.
. "${project_cfg_file}"

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
k8s_stage_dir=''
k8s_metadata_file=''
k8s_log=''

cleanup() {
	[ -z "${k8s_log}" ] || rm -f "${k8s_log}"
	if [ -n "${k8s_stage_dir}" ]; then
		rm -rf "${k8s_stage_dir}"
	fi
	if [ -n "${k8s_metadata_file}" ]; then
		rm -f "${k8s_metadata_file}"
	fi
}
trap cleanup EXIT INT TERM HUP

. ./scripts/workflow-policy.sh

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

printf '\n==> Check shell syntax\n'
# Syntax-check scripts inside the container; scanning does not generate release files.
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
	sh -eu -c 'find scripts -type f -name '"'"'*.sh'"'"' -print | LC_ALL=C sort | while IFS= read -r path; do sh -n "${path}"; done '

k8s_chart_path=${K8S_CHART_PATH:-config/k8s/chart}
case "${k8s_chart_path}" in
/* | ./* | ../*) ;;
*) k8s_chart_path="./${k8s_chart_path}" ;;
esac
k8s_render_file_scan_path=''
k8s_helm_image=${DEV_K8S_HELM_IMAGE_LOCK:-${DEV_K8S_HELM_IMAGE:-}}

if [ -n "${k8s_helm_image}" ] && [ -d "${k8s_chart_path}" ]; then
	k8s_metadata_file=$(mktemp "${docker_tmpdir}/k8s-scan-meta.XXXXXX")
	printf '\n==> Render Kubernetes manifests\n'
	k8s_log=$(mktemp "${docker_tmpdir}/k8s-scan-log.XXXXXX")
	K8S_METADATA_FILE="${k8s_metadata_file}" sh ./scripts/k8s.sh "${PROJECT_CFG_FILE}" >"${k8s_log}"
	# shellcheck disable=SC1090
	. "${k8s_metadata_file}"
	[ -n "${K8S_RENDER_FILE:-}" ] || {
		printf '%s\n' 'k8s render did not report a manifest path' >&2
		exit 1
	}
	[ -f "${K8S_RENDER_FILE}" ] || {
		printf 'missing rendered manifest: %s\n' "${K8S_RENDER_FILE}" >&2
		exit 1
	}
	k8s_stage_dir=$(mktemp -d "${docker_tmpdir}/k8s-scan-manifest.XXXXXX")
	k8s_stage_file="${k8s_stage_dir}/$(basename "${K8S_RENDER_FILE}")"
	cp "${K8S_RENDER_FILE}" "${k8s_stage_file}"
	k8s_render_file_scan_path="/tmp/$(basename "${k8s_stage_dir}")/$(basename "${K8S_RENDER_FILE}")"
else
	printf '\n==> Skip Kubernetes manifest scan\n'
	printf '%s\n' 'Optional Kubernetes scaffold not configured; skipping Helm render and manifest scan'
fi

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

zizmor_scan_image=${DEV_SCAN_ZIZMOR_IMAGE_LOCK}
case "${zizmor_scan_image}" in
*@sha256:*) ;;
*)
	printf 'DEV_SCAN_ZIZMOR_IMAGE_LOCK must be pinned by digest\n' >&2
	exit 1
	;;
esac

printf '\n==> Run GitHub Actions security scan\n'
# zizmor complements actionlint by checking workflow security footguns without
# executing workflow code. Offline mode keeps local and CI scans deterministic.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace" \
	-w /workspace \
	"${zizmor_scan_image}" \
	--offline \
	--strict-collection \
	--collect=workflows,actions \
	--persona=regular \
	.

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

printf '\n==> Run Kubernetes manifest scan\n'
if [ -n "${k8s_render_file_scan_path}" ]; then
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
		config \
		--severity HIGH,CRITICAL \
		--exit-code 1 \
		--skip-version-check \
		"${k8s_render_file_scan_path}"
else
	printf '%s\n' 'No rendered Kubernetes manifests available; skipping Trivy config scan'
fi

printf '\n==> Check workflow pins\n'
# Finally, verify that workflow action references and triggers stay within the
# template's reviewed CI/CD policy.
check_workflow_action_pins
check_workflow_permissions_policy
check_workflow_trigger_policy
check_workflow_metadata_policy
