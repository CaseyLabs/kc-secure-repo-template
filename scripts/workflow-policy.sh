#!/bin/sh
# Shared workflow checks used by make scan and behavioral regression tests.

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

# zizmor's unpinned-uses audit rejects any action ref that is not a full commit
# SHA (see run_workflow_security_scan). This check adds the template-only rule
# that each pinned SHA keeps a reviewed "# vX.Y.Z" release tag comment, so
# reviewers and Dependabot can see which release the SHA should match.
check_workflow_action_pins() {
	list_workflow_entries | while IFS="$(printf '\t')" read -r workflow ref comment; do
		case "${comment}" in
		v*) ;;
		*)
			printf '%s must keep a reviewed release tag comment for %s\n' "${workflow}" "${ref}" >&2
			exit 1
			;;
		esac
	done
}

# Require every workflow to opt into only the token scopes it needs. This avoids
# old repository defaults silently granting write-scoped GITHUB_TOKEN access.
check_workflow_permissions_policy() {
	for workflow in .github/workflows/*.yml; do
		if ! grep -Eq '^permissions:[[:space:]]*($|[{])' "${workflow}"; then
			printf '%s: missing top-level permissions block; set explicit workflow permissions\n' "${workflow}" >&2
			return 1
		fi
	done
}

# zizmor's dangerous-triggers audit rejects pull_request_target and workflow_run.
# It does not flag issue_comment, which lets any commenter start a run, so the
# template keeps that ban here. A derived repository that needs comment-driven
# automation should add a reviewed, metadata-only workflow and adjust this check.
check_workflow_trigger_policy() {
	awk '
		{
			line = $0
			sub(/[[:space:]]+#.*$/, "", line)
			if (line ~ /(^|[^A-Za-z0-9_-])issue_comment([^A-Za-z0-9_-]|$)/) {
				printf "%s:%d: issue_comment is not allowed in template workflows\n", FILENAME, FNR
				found = 1
			}
		}
		END {
			exit found ? 1 : 0
		}
	' .github/workflows/*.yml
}

# Run zizmor, the GitHub Actions security analyzer, against workflows and local
# actions under the given directory. Its audits cover the rules this file used
# to reimplement in awk: full-SHA action pins (unpinned-uses), privileged
# triggers (dangerous-triggers), untrusted metadata in run steps
# (template-injection), and missing token scopes (excessive-permissions).
# --offline keeps results deterministic, so the scanner also gets no network,
# and the checkout is mounted read-only because zizmor only reads it.
# Usage: run_workflow_security_scan <digest-pinned image> <directory>
run_workflow_security_scan() {
	docker run --rm --user "${docker_uid:-$(id -u)}:${docker_gid:-$(id -g)}" \
		--cap-drop=ALL \
		--security-opt=no-new-privileges:true \
		--network=none \
		-e HOME=/tmp \
		-v "$2:/workspace:ro" \
		-w /workspace \
		"$1" \
		--offline \
		--strict-collection \
		--collect=workflows,actions \
		--persona=regular \
		.
}
