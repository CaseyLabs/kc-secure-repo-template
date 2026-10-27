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
# Opt-in vulnerability scan of a built image (off unless set to true). The target
# defaults to the distroless runtime stage; the dev image carries toolchains on
# purpose, so it is not a sensible target.
scan_image_vulns=${PROJECT_SCAN_IMAGE_VULNS-false}
# Reject anything but true/false so a typo such as TRUE or 1 cannot silently
# leave this security check off.
case "${scan_image_vulns}" in
true | false) ;;
*)
	printf 'PROJECT_SCAN_IMAGE_VULNS must be true or false, not %s\n' "${scan_image_vulns}" >&2
	exit 1
	;;
esac
scan_image_target=${PROJECT_SCAN_IMAGE_TARGET:-runtime}
# A per-project tag keeps two checkouts on one Docker host from scanning each
# other's image; cleanup removes it again.
scan_image_tag="${PROJECT_NAME:-kc-secure-template}-vuln-scan:local"
scan_image_built=false

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
scan_image_tar=''

cleanup() {
	# The saved image tarball can be large; remove it whether the scan passed or failed.
	[ -z "${scan_image_tar}" ] || rm -f "${scan_image_tar}"
	[ "${scan_image_built}" = false ] || docker image rm "${scan_image_tag}" >/dev/null
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
. ./scripts/commit-policy.sh
. ./scripts/agent-policy.sh
require_buildkit "make scan"

# Host-only checks run first: they need only sh, git, grep, sed, and awk, so a
# PR that breaks them fails in seconds instead of after the image build and
# container scans.
printf '\n==> Check AI agent setup\n'
# Keep skill entrypoints paired with canonical skills and the root guidance
# within budget.
check_agent_skill_policy
check_agent_guidance_size

printf '\n==> Check commit attribution policy\n'
# Recheck commit messages in the pushed or PR range (COMMIT_POLICY_BASE/HEAD in
# CI), because the local commit-msg hook is opt-in and can be skipped.
check_commit_attribution_policy

# Build one Dockerfile target with the pinned build args. The project image and
# the opt-in vulnerability-scan image share this path so the args never drift.
# $1 is the target, $2 the image tag, and $3 optional extra build args (word-split
# on purpose, so keep them free of spaces).
build_scan_target() {
	# GitHub Actions can opt into Buildx cache export/import without changing local defaults.
	build_command=build
	[ -z "${DOCKER_BUILD_EXTRA_ARGS:-}" ] || build_command="buildx build --load ${DOCKER_BUILD_EXTRA_ARGS}"
	# shellcheck disable=SC2086
	docker ${build_command} \
		--build-arg DEV_BASE_IMAGE="${DEV_BASE_IMAGE_LOCK:-${DEV_BASE_IMAGE}}" \
		--build-arg DEV_PACKAGE_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		--build-arg DEBIAN_APT_SNAPSHOT="${DEV_PACKAGE_SNAPSHOT_LOCK}" \
		${3:-} \
		--target "$1" \
		-f "${project_dockerfile}" \
		-t "$2" .
}

printf '\n==> Build project image\n'
# Build the main dev image before running syntax and template checks inside it.
build_scan_target "${project_build_target}" "${project_image}"

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
# Derived repositories that have not renamed their lock yet keep scanning with
# DEV_SCAN_GITLEAKS_IMAGE_LOCK; gitleaks v8.19+ accepts the same git/dir commands.
# The lock name is kept with the image so a pin error names the variable the
# user actually set.
if [ -n "${DEV_SCAN_BETTERLEAKS_IMAGE_LOCK:-}" ] || [ -z "${DEV_SCAN_GITLEAKS_IMAGE_LOCK:-}" ]; then
	secret_scan_lock_name=DEV_SCAN_BETTERLEAKS_IMAGE_LOCK
	secret_scan_image=${DEV_SCAN_BETTERLEAKS_IMAGE_LOCK:-}
else
	secret_scan_lock_name=DEV_SCAN_GITLEAKS_IMAGE_LOCK
	secret_scan_image=${DEV_SCAN_GITLEAKS_IMAGE_LOCK}
fi
case "${secret_scan_image}" in
*@sha256:*) ;;
*)
	printf '%s must be pinned by digest\n' "${secret_scan_lock_name}" >&2
	exit 1
	;;
esac

printf '\n==> Run secret scan\n'
# Prefer Git-aware scanning so removed-but-still-reachable secrets in history are
# caught; fall back to a plain directory scan when Git metadata is unavailable.
secret_scan_mode=dir
[ -d .git ] && secret_scan_mode=git
# The scanner only reads the checkout and never validates findings against live
# APIs (no --validation), so it runs with no network and a read-only mount: a
# compromised scanner image can neither exfiltrate nor rewrite repository files.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	--network=none \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/repo:ro" \
	-w /repo \
	"${secret_scan_image}" \
	"${secret_scan_mode}" /repo --no-banner --redact --exit-code 1

printf '\n==> Run workflow lint\n'
# Use actionlint in a container so CI and local runs use the same tool version.
# The image bundles shellcheck, which actionlint runs on every run: block, so
# shell quoting and word-splitting bugs in workflows fail the scan. pyflakes is
# disabled because the workflows contain no Python steps. actionlint only reads
# the checkout, so it gets no network and a read-only mount.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	--network=none \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace:ro" \
	-w /workspace \
	"${DEV_SCAN_ACTIONLINT_IMAGE_LOCK}" \
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
# executing workflow code. The shared helper in scripts/workflow-policy.sh keeps
# the flags identical between this scan and the regression fixtures.
run_workflow_security_scan "${zizmor_scan_image}" "$(pwd)"

trivy_scan_image=${DEV_SCAN_TRIVY_IMAGE_LOCK}
case "${trivy_scan_image}" in
*@sha256:*) ;;
*)
	printf 'DEV_SCAN_TRIVY_IMAGE_LOCK must be pinned by digest\n' >&2
	exit 1
	;;
esac

printf '\n==> Run misconfiguration scan\n'
# Trivy complements the other scanners by checking Dockerfile and Terraform
# posture issues. It runs offline from the checks bundled in the pinned image
# (--skip-check-update), so a compromised or changed check feed cannot alter
# results, and it mounts the checkout read-only because it only reads it.
# On a cold cache (such as a fresh CI runner) Trivy logs "Falling back to
# embedded checks" at ERROR level; that is expected and the scan still runs.
# config/.trivyignore holds reviewed suppressions, each with its reason.
# --skip-dirs drops providers and modules that terraform init downloads, which
# are third-party code rather than this repository's configuration, plus the
# gitignored .cache and .tmp trees so local runs match a fresh CI checkout.
# --tf-exclude-downloaded-modules also covers modules the evaluator loads
# through .terraform/modules/modules.json, including other Terraform roots.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	--network=none \
	-e HOME="${docker_home}" \
	-e XDG_CACHE_HOME="${docker_cache_home}" \
	-e TRIVY_CACHE_DIR="${docker_cache_home}/trivy" \
	-v "${docker_home_source}:${docker_home}" \
	-v "${docker_tmpdir}:/tmp" \
	-v "$(pwd):/workspace:ro" \
	-w /workspace \
	"${trivy_scan_image}" \
	fs \
	--scanners misconfig \
	--misconfig-scanners dockerfile,terraform \
	--skip-dirs /workspace/config/infra/.terraform \
	--skip-dirs /workspace/.cache \
	--skip-dirs /workspace/.tmp \
	--tf-exclude-downloaded-modules \
	--ignorefile /workspace/config/.trivyignore \
	--severity HIGH,CRITICAL \
	--exit-code 1 \
	--skip-version-check \
	--skip-check-update \
	/workspace

# Off by default and silent when off, so the default scan output is unchanged.
if [ "${scan_image_vulns}" = true ]; then
	printf '\n==> Run image vulnerability scan\n'
	scan_image_build_args=''
	if [ "${scan_image_target}" = runtime ]; then
		# The runtime stage has no mutable fallback in a scan: both locks must be
		# digest-pinned, with the same shared check build.sh applies.
		require_pinned_lock DEV_GO_IMAGE_LOCK "${DEV_GO_IMAGE_LOCK:-}" "scan the runtime image"
		require_pinned_lock DEV_DISTROLESS_STATIC_IMAGE_LOCK "${DEV_DISTROLESS_STATIC_IMAGE_LOCK:-}" "scan the runtime image"
		scan_image_build_args="--build-arg RUNTIME_BUILD_IMAGE=${DEV_GO_IMAGE_LOCK} --build-arg RUNTIME_BASE_IMAGE=${DEV_DISTROLESS_STATIC_IMAGE_LOCK}"
	fi
	scan_image_built=true
	build_scan_target "${scan_image_target}" "${scan_image_tag}" "${scan_image_build_args}"
	scan_image_tar=$(mktemp "${docker_tmpdir}/scan-image.XXXXXX")
	docker save -o "${scan_image_tar}" "${scan_image_tag}"
	# Unlike the other scanners, Trivy needs network access here to fetch its
	# vulnerability database. So it gets only the tarball and the reviewed ignore
	# file, read-only, plus its own cache in the Docker home, not the shared temp
	# directory.
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-e TRIVY_CACHE_DIR="${docker_cache_home}/trivy" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${scan_image_tar}:/scan/image.tar:ro" \
		-v "$(pwd)/config/.trivyignore:/scan/.trivyignore:ro" \
		"${trivy_scan_image}" \
		image \
		--input /scan/image.tar \
		--ignorefile /scan/.trivyignore \
		--scanners vuln \
		--severity HIGH,CRITICAL \
		--exit-code 1 \
		--skip-version-check
fi

printf '\n==> Run Kubernetes manifest scan\n'
if [ -n "${k8s_render_file_scan_path}" ]; then
	docker run --rm --user "${docker_uid}:${docker_gid}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		--network=none \
		-e HOME="${docker_home}" \
		-e XDG_CACHE_HOME="${docker_cache_home}" \
		-e TRIVY_CACHE_DIR="${docker_cache_home}/trivy" \
		-v "${docker_home_source}:${docker_home}" \
		-v "${docker_tmpdir}:/tmp" \
		-v "$(pwd):/workspace:ro" \
		-w /workspace \
		"${trivy_scan_image}" \
		config \
		--ignorefile /workspace/config/.trivyignore \
		--severity HIGH,CRITICAL \
		--exit-code 1 \
		--skip-version-check \
		--skip-check-update \
		"${k8s_render_file_scan_path}"
else
	printf '%s\n' 'No rendered Kubernetes manifests available; skipping Trivy config scan'
fi

printf '\n==> Check workflow pins\n'
# Finally, apply the template-only workflow rules that zizmor does not cover:
# release tag comments on pinned actions, a top-level permissions block in
# every workflow, the issue_comment trigger ban, and no inline zizmor ignores.
check_workflow_action_pins
check_workflow_permissions_policy
check_workflow_trigger_policy
check_workflow_scanner_suppressions

printf '\n==> Check runtime image policy\n'
# The optional distroless runtime stage must stay digest-pinned, non-root, and
# exec-form so it cannot silently weaken the image when the Dockerfile changes.
check_runtime_image_policy

printf '\n==> Check Claude settings\n'
# Keep the shared Claude deny rules in place. The settings check parses JSON with jq, which the dev image provides; running
# it in the container keeps jq off the list of required host tools.
docker run --rm --user "${docker_uid}:${docker_gid}" \
	--cap-drop=ALL \
	--security-opt=no-new-privileges:true \
	--network=none \
	-e HOME="${docker_home}" \
	-v "$(pwd):/workspace:ro" \
	-w /workspace \
	"${project_image}" \
	sh -eu -c '. ./scripts/agent-policy.sh; check_agent_settings_policy'
