#!/bin/sh
# shellcheck shell=sh disable=SC1091
set -eu

# Stop with a clear message when a host helper command is unavailable.
require_command() {
	command -v "$1" >/dev/null 2>&1 || {
		printf 'missing required command: %s\n' "$1" >&2
		exit 1
	}
}

# This script resolves image digests and rewrites tracked files, so verify prerequisites first.
for cmd in awk curl jq perl sed tr head; do
	require_command "${cmd}"
done

# Collect all external action references from workflow files.
list_workflow_entries() {
	for workflow in .github/workflows/*.yml; do
		awk -v workflow="${workflow}" '
			/^[[:space:]]*-[[:space:]]+uses:[[:space:]]+/ || /^[[:space:]]+uses:[[:space:]]+/ {
				ref = $0
				sub(/^[[:space:]]*-[[:space:]]+uses:[[:space:]]+/, "", ref)
				sub(/^[[:space:]]*uses:[[:space:]]+/, "", ref)
				if (ref ~ /[[:space:]]+#.*$/) {
					sub(/[[:space:]]+#.*$/, "", ref)
				}
				sub(/[[:space:]]+$/, "", ref)
				if (ref ~ /^(\.\/|\.\.\/)/) {
					next
				}
				print ref
			}
		' "${workflow}"
	done | LC_ALL=C sort -u
}

# Keep the README allowlist section aligned with the actual workflow files.
sync_workflow_allowlist() {
	tmp=$(mktemp)
	trap 'rm -f "${tmp}" "${tmp}.new"' EXIT INT TERM

	list_workflow_entries | awk '{ printf "- `%s`\n", $0 }' >"${tmp}"

	awk -v action_file="${tmp}" '
		BEGIN {
			while ((getline line < action_file) > 0) {
				actions = actions line ORS
			}
			close(action_file)
		}
		/^### Current Actions$/ && !done {
			print
			print ""
			printf "%s", actions
			print ""
			skip = 1
			done = 1
			next
		}
		skip {
			if ($0 == "### Allowlist Guidance") {
				skip = 0
				print
			}
			next
		}
		{ print }
	' README.md >"${tmp}.new"

	mv "${tmp}.new" README.md
	rm -f "${tmp}"
	trap - EXIT INT TERM
}

# Load the reviewed image tags and version selectors that this script will lock down.
. ./project.env.example

# Docker Hub requires a short-lived token before manifest metadata can be fetched.
docker_hub_token() {
	curl -fsSL "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$1:pull" | jq -r '.token'
}

# Resolve a Docker Hub tag into its immutable digest.
docker_hub_digest() {
	token=$(docker_hub_token "$1")
	curl -fsSI \
		-H "Authorization: Bearer ${token}" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
		"https://registry-1.docker.io/v2/$1/manifests/$2" |
		tr -d '\r' | sed -n 's/^docker-content-digest: //Ip' | head -n 1
}

# GHCR uses a similar API, but with a different token endpoint.
ghcr_digest() {
	token=$(curl -fsSL "https://ghcr.io/token?scope=repository:$1:pull" | jq -r '.token')
	curl -fsSI \
		-H "Authorization: Bearer ${token}" \
		-H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' \
		"https://ghcr.io/v2/$1/manifests/$2" |
		tr -d '\r' | sed -n 's/^docker-content-digest: //Ip' | head -n 1
}

# Accept common image formats and return a digest-pinned reference for each one.
resolve_image() {
	case "$1" in
	*@sha256:*)
		printf '%s\n' "$1"
		;;
	ghcr.io/*:*)
		repo=${1#ghcr.io/}
		tag=${repo##*:}
		repo=${repo%:*}
		printf 'ghcr.io/%s@%s\n' "${repo}" "$(ghcr_digest "${repo}" "${tag}")"
		;;
	ghcr.io/*)
		repo=${1#ghcr.io/}
		printf 'ghcr.io/%s@%s\n' "${repo}" "$(ghcr_digest "${repo}" latest)"
		;;
	*/*:*)
		tag=${1##*:}
		repo=${1%:*}
		printf '%s@%s\n' "$1" "$(docker_hub_digest "${repo}" "${tag}")"
		;;
	*:*)
		tag=${1##*:}
		repo=${1%:*}
		printf '%s@%s\n' "$1" "$(docker_hub_digest "library/${repo}" "${tag}")"
		;;
	*)
		printf '%s@%s\n' "$1" "$(docker_hub_digest "library/${1}" latest)"
		;;
	esac
}

# Resolve every reviewed image selector to the exact digest committed in the repo.
dev_base_image_lock=$(resolve_image "${DEV_BASE_IMAGE}")
dev_go_image_lock=$(resolve_image "${DEV_GO_IMAGE}")
dev_terraform_image_lock=$(resolve_image "${DEV_TERRAFORM_IMAGE}")
dev_scan_gitleaks_image_lock=$(resolve_image "${DEV_SCAN_GITLEAKS_IMAGE}")
dev_scan_actionlint_image_lock=$(resolve_image "${DEV_SCAN_ACTIONLINT_IMAGE}")
dev_scan_trivy_image_lock=$(resolve_image "${DEV_SCAN_TRIVY_IMAGE}")
dev_scan_syft_image_lock=$(resolve_image "${DEV_SCAN_SYFT_IMAGE}")
dev_scan_grype_image_lock=$(resolve_image "${DEV_SCAN_GRYPE_IMAGE}")

# Rewrite the lock file that runtime scripts source during builds and scans.
cat >config/lockfile.env <<EOF
# --- Makefile-managed variables
# - These lock values/checksums are generated from the reviewed selectors in
#   project.env.example and synced by make update.
DEV_PACKAGE_SNAPSHOT_LOCK='${DEV_PACKAGE_SNAPSHOT_LOCK}'
DEV_BASE_IMAGE_LOCK='${dev_base_image_lock}'
DEV_GO_IMAGE_LOCK='${dev_go_image_lock}'
DEV_TERRAFORM_IMAGE_LOCK='${dev_terraform_image_lock}'
DEV_SCAN_GITLEAKS_IMAGE_LOCK='${dev_scan_gitleaks_image_lock}'
DEV_SCAN_ACTIONLINT_IMAGE_LOCK='${dev_scan_actionlint_image_lock}'
DEV_SCAN_TRIVY_IMAGE_LOCK='${dev_scan_trivy_image_lock}'
DEV_SCAN_SYFT_IMAGE_LOCK='${dev_scan_syft_image_lock}'
DEV_SCAN_GRYPE_IMAGE_LOCK='${dev_scan_grype_image_lock}'
EOF

# Keep infra and README references synchronized with the newly resolved locks.
perl -0pi -e 's#^FROM .* AS terraform-cli$#FROM '"${dev_terraform_image_lock}"' AS terraform-cli#m; s#^FROM .* AS dev-base$#FROM '"${dev_base_image_lock}"' AS dev-base#m' config/infra/Dockerfile
perl -0pi -e 's#^      version = ".*"$#      version = "= '"${DEV_TERRAFORM_GITHUB_PROVIDER_VERSION}"'"#m' config/infra/versions.tf
perl -0pi -e 's#^- Terraform image `.*` pinned to `.*`$#- Terraform image `'"${DEV_TERRAFORM_IMAGE}"'` pinned to `'"${dev_terraform_image_lock}"'`#m; s#^- GitHub provider `integrations/github` with `= .*`$#- GitHub provider `integrations/github` with `= '"${DEV_TERRAFORM_GITHUB_PROVIDER_VERSION}"'`#m' README.md
sync_workflow_allowlist

# End with a short machine-readable summary for maintainers.
printf '%s\n' 'updated config/lockfile.env and aligned infra/README workflow pins'
