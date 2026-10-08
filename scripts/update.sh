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

# Stop with a clear message when a host helper command is unavailable.
require_command() {
	command -v "$1" >/dev/null 2>&1 || {
		printf 'missing required command: %s\n' "$1" >&2
		exit 1
	}
}

# This script resolves image digests and rewrites tracked files, so verify prerequisites first.
for cmd in awk curl grep jq perl sed tr head; do
	require_command "${cmd}"
done

# Load the reviewed image tags and version selectors that this script will lock down.
. "${project_cfg_file}"

# Docker Hub requires a short-lived token before manifest metadata can be fetched.
docker_hub_token() {
	token_response=$(curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull") || return 1
	token=$(printf '%s\n' "${token_response}" | jq -er '.token | select(type == "string" and length > 0)') || return 1
	[ -n "${token}" ] || {
		printf 'registry returned an empty Docker Hub token for %s\n' "$1" >&2
		return 1
	}
	printf '%s\n' "${token}"
}

# Resolve a Docker Hub tag into its immutable digest.
docker_hub_digest() {
	token=$(docker_hub_token "$1") || return 1
	headers=$(curl -fsSI \
		-H "Authorization: Bearer ${token}" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
		"https://registry-1.docker.io/v2/$1/manifests/$2") || return 1
	digest=$(printf '%s\n' "${headers}" | tr -d '\r' | sed -n 's/^docker-content-digest: //Ip' | head -n 1)
	validate_digest "${digest}" "$1:$2"
}

validate_digest() {
	case "$1" in
		sha256:*) digest_hex=${1#sha256:} ;;
		*) digest_hex='' ;;
	esac
	if [ "${#digest_hex}" -ne 64 ] || ! printf '%s\n' "${digest_hex}" | grep -Eq '^[[:xdigit:]]{64}$'; then
		printf 'registry returned an invalid digest for %s\n' "$2" >&2
		return 1
	fi
	printf 'sha256:%s\n' "${digest_hex}"
}

# GHCR uses a similar API, but with a different token endpoint.
ghcr_digest() {
	token_response=$(curl -fsSL "https://ghcr.io/token?scope=repository:$1:pull") || return 1
	token=$(printf '%s\n' "${token_response}" | jq -er '.token | select(type == "string" and length > 0)') || return 1
	headers=$(curl -fsSI \
		-H "Authorization: Bearer ${token}" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
		"https://ghcr.io/v2/$1/manifests/$2") || return 1
	digest=$(printf '%s\n' "${headers}" | tr -d '\r' | sed -n 's/^docker-content-digest: //Ip' | head -n 1)
	validate_digest "${digest}" "$1:$2"
}

# Accept common image formats and return a digest-pinned reference for each one.
resolve_image() {
	case "$1" in
	*@sha256:*)
		digest=$(validate_digest "${1##*@}" "$1") || return 1
		resolved_image="${1%@*}@${digest}"
		;;
	ghcr.io/*:*)
		repo=${1#ghcr.io/}
		tag=${repo##*:}
		repo=${repo%:*}
		digest=$(ghcr_digest "${repo}" "${tag}") || return 1
		resolved_image="ghcr.io/${repo}@${digest}"
		;;
	ghcr.io/*)
		repo=${1#ghcr.io/}
		digest=$(ghcr_digest "${repo}" latest) || return 1
		resolved_image="ghcr.io/${repo}@${digest}"
		;;
	*/*:*)
		tag=${1##*:}
		repo=${1%:*}
		digest=$(docker_hub_digest "${repo}" "${tag}") || return 1
		resolved_image="${1}@${digest}"
		;;
	*:*)
		tag=${1##*:}
		repo=${1%:*}
		digest=$(docker_hub_digest "library/${repo}" "${tag}") || return 1
		resolved_image="${1}@${digest}"
		;;
	*)
		digest=$(docker_hub_digest "library/${1}" latest) || return 1
		resolved_image="${1}@${digest}"
		;;
	esac
	case "${resolved_image}" in
		*@sha256:*) ;;
		*) printf 'resolved image has no valid digest: %s\n' "${1}" >&2; return 1 ;;
	esac
	printf '%s\n' "${resolved_image}"
}

# Resolve every reviewed image selector to the exact digest committed in the repo.
dev_base_image_lock=$(resolve_image "${DEV_BASE_IMAGE}")
dev_go_image_lock=$(resolve_image "${DEV_GO_IMAGE}")
dev_terraform_image_lock=$(resolve_image "${DEV_TERRAFORM_IMAGE}")
dev_k8s_helm_image_lock=''
if [ -n "${DEV_K8S_HELM_IMAGE:-}" ]; then
	dev_k8s_helm_image_lock=$(resolve_image "${DEV_K8S_HELM_IMAGE}")
fi
dev_k8s_kubectl_image_lock=''
if [ -n "${DEV_K8S_KUBECTL_IMAGE:-}" ]; then
	dev_k8s_kubectl_image_lock=$(resolve_image "${DEV_K8S_KUBECTL_IMAGE}")
fi
dev_scan_gitleaks_image_lock=$(resolve_image "${DEV_SCAN_GITLEAKS_IMAGE}")
dev_scan_actionlint_image_lock=$(resolve_image "${DEV_SCAN_ACTIONLINT_IMAGE}")
dev_scan_zizmor_image_lock=$(resolve_image "${DEV_SCAN_ZIZMOR_IMAGE}")
dev_scan_trivy_image_lock=$(resolve_image "${DEV_SCAN_TRIVY_IMAGE}")
dev_scan_syft_image_lock=$(resolve_image "${DEV_SCAN_SYFT_IMAGE}")
dev_scan_grype_image_lock=$(resolve_image "${DEV_SCAN_GRYPE_IMAGE}")
dev_renovate_image_lock=$(resolve_image "${DEV_RENOVATE_IMAGE}")

# Rewrite the lock file that runtime scripts source during builds and scans.
cat >config/lockfile.cfg <<EOF
# --- Makefile-managed variables
# - These lock values/checksums are generated from the reviewed selectors in
#   ${PROJECT_CFG_FILE} and synced by make update.
DEV_PACKAGE_SNAPSHOT_LOCK='${DEV_PACKAGE_SNAPSHOT_LOCK}'
DEV_BASE_IMAGE_LOCK='${dev_base_image_lock}'
DEV_GO_IMAGE_LOCK='${dev_go_image_lock}'
DEV_TERRAFORM_IMAGE_LOCK='${dev_terraform_image_lock}'
DEV_K8S_HELM_IMAGE_LOCK='${dev_k8s_helm_image_lock}'
DEV_K8S_KUBECTL_IMAGE_LOCK='${dev_k8s_kubectl_image_lock}'
DEV_SCAN_GITLEAKS_IMAGE_LOCK='${dev_scan_gitleaks_image_lock}'
DEV_SCAN_ACTIONLINT_IMAGE_LOCK='${dev_scan_actionlint_image_lock}'
DEV_SCAN_ZIZMOR_IMAGE_LOCK='${dev_scan_zizmor_image_lock}'
DEV_SCAN_TRIVY_IMAGE_LOCK='${dev_scan_trivy_image_lock}'
DEV_SCAN_SYFT_IMAGE_LOCK='${dev_scan_syft_image_lock}'
DEV_SCAN_GRYPE_IMAGE_LOCK='${dev_scan_grype_image_lock}'
DEV_RENOVATE_IMAGE_LOCK='${dev_renovate_image_lock}'
EOF

# Keep the optional infra image and provider selectors synchronized.
DEV_TERRAFORM_IMAGE_LOCK_VALUE=${dev_terraform_image_lock} \
	DEV_BASE_IMAGE_LOCK_VALUE=${dev_base_image_lock} \
	perl -0pi -e 's#^FROM .* AS terraform-cli$#FROM $ENV{DEV_TERRAFORM_IMAGE_LOCK_VALUE} AS terraform-cli#m; s#^FROM .* AS dev-base$#FROM $ENV{DEV_BASE_IMAGE_LOCK_VALUE} AS dev-base#m' config/infra/Dockerfile
DEV_TERRAFORM_GITHUB_PROVIDER_VERSION_VALUE=${DEV_TERRAFORM_GITHUB_PROVIDER_VERSION} \
	perl -0pi -e 's#^      version = ".*"$#      version = "= $ENV{DEV_TERRAFORM_GITHUB_PROVIDER_VERSION_VALUE}"#m' config/infra/versions.tf
# End with a short machine-readable summary for maintainers.
printf '%s\n' 'updated config/lockfile.cfg and aligned infra image and provider versions'
