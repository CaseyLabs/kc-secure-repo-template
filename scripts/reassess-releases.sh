#!/bin/sh
# Read-only reassessment of the three newest published, stable releases.
set -eu
. ./config/project.cfg
repo=${GITHUB_REPOSITORY:-}
[ -n "${repo}" ] || { printf 'GITHUB_REPOSITORY is required\n' >&2; exit 1; }
[ -n "${GH_TOKEN:-}" ] || { printf 'GH_TOKEN with contents:read is required\n' >&2; exit 1; }
output_dir=${REASSESS_OUTPUT_DIR:-.tmp/reassessment}
mkdir -p "${output_dir}"
image=${DEV_SCAN_GRYPE_IMAGE_LOCK}
case "${image}" in *@sha256:*) ;; *) printf 'Grype image must be digest pinned\n' >&2; exit 1 ;; esac
failed=false
scanner_tmp=$(mktemp -d)
trap 'rm -rf "${scanner_tmp}"' EXIT
trap 'exit 1' HUP INT TERM
# The release list is read-only; findings are retained in this workflow's
# artifact and require human triage before any quarantine or replacement.
if ! gh release list --repo "${repo}" --limit 100 --json tagName,isDraft,isPrerelease,publishedAt >"${scanner_tmp}/releases.json"; then
	printf 'failed to list releases for %s\n' "${repo}" >&2
	exit 1
fi
jq -r '[.[] | select(.isDraft == false and .isPrerelease == false)] | sort_by(.publishedAt) | reverse | .[:3] | .[].tagName' \
	"${scanner_tmp}/releases.json" >"${output_dir}/tags.txt"
while IFS= read -r tag; do
	[ -n "${tag}" ] || continue
	case "${tag}" in *[!A-Za-z0-9._-]*) printf 'invalid release tag from API\n' >&2; exit 1 ;; esac
	release_dir="${output_dir}/${tag}"
	mkdir -p "${release_dir}"
	if ! gh release download "${tag}" --repo "${repo}" --pattern template.spdx.json --dir "${release_dir}" --clobber; then
		printf 'missing retained SBOM for %s\n' "${tag}" >&2
		failed=true
		continue
	fi
	# The scanner runs nonroot, so give its database and scratch files a
	# writable mount instead of relying on the image's root-owned /tmp.
	if ! docker run --rm --user "$(id -u):$(id -g)" --network=bridge \
		--cap-drop=ALL --security-opt=no-new-privileges:true \
		-e HOME=/tmp -e XDG_CACHE_HOME=/tmp/cache -e GRYPE_DB_CACHE_DIR=/tmp/grype-db \
		-v "${scanner_tmp}:/tmp" \
		-v "$(pwd)/${release_dir}:/evidence:ro" "${image}" \
		"sbom:/evidence/template.spdx.json" --fail-on critical -o table >"${release_dir}/grype-report.txt"; then
		printf 'new critical finding or scanner failure for %s\n' "${tag}" >&2
		failed=true
	fi
done <"${output_dir}/tags.txt"
[ "${failed}" = false ]
