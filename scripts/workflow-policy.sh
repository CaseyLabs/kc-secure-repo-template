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
# Kept alongside zizmor: its excessive-permissions audit accepts a workflow
# whose jobs each set permissions without a top-level block.
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
# --no-config stops a checked-in zizmor.yml from disabling audits; inline
# ignore comments are rejected separately by check_workflow_scanner_suppressions.
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
		--no-config \
		.
}

# zizmor honors inline "# zizmor: ignore[audit]" comments and has no flag to turn
# them off, so a pull request could silence the audits above from inside the file
# it changes. Reject them in workflows and local actions; a derived repository
# that needs a reviewed suppression should record it in run_workflow_security_scan
# instead (see docs/github-ci.md).
check_workflow_scanner_suppressions() {
	hits=$(find . \( -path ./.git -o -path ./.cache -o -path ./.tmp -o -path ./dist \) -prune -o \
		-type f \( -path './.github/workflows/*.yml' -o -path './.github/workflows/*.yaml' -o -name action.yml -o -name action.yaml \) \
		-exec grep -Hn 'zizmor:[[:space:]]*ignore' {} +) || true
	[ -z "${hits}" ] && return 0
	printf '%s\n' "${hits}" >&2
	printf 'inline zizmor ignore is not allowed in template workflows\n' >&2
	return 1
}

# Policy for the optional distroless `runtime` stage in the Dockerfile. Derived
# repositories that delete the stage are not checked. When the stage exists it
# must (1) build FROM the `RUNTIME_BASE_IMAGE` arg that `make build` fills with
# the digest lock, (2) keep that lock digest-pinned, (3) end as a non-root user,
# and (4) use an exec-form ENTRYPOINT, because distroless images have no shell.
# An empty lock is allowed: it means the selector was left blank, and
# `make build` refuses to build the runtime image without a pinned lock.
# Arguments: Dockerfile path, lockfile path (both default to the repository's).
check_runtime_image_policy() {
	runtime_dockerfile=${1:-Dockerfile}
	runtime_lockfile=${2:-config/lockfile.cfg}

	# Print the `AS runtime` FROM line, then that stage's instructions. Dockerfile
	# keywords and stage names are case-insensitive, so match on lowercase.
	runtime_stage=$(awk '
		{ line = tolower($0) }
		line ~ /^[[:space:]]*from[[:space:]]/ {
			in_stage = (line ~ /[[:space:]]as[[:space:]]+runtime[[:space:]]*$/)
		}
		in_stage { print }
	' "${runtime_dockerfile}")
	[ -n "${runtime_stage}" ] || return 0

	runtime_from=$(printf '%s\n' "${runtime_stage}" | head -n 1)
	case "${runtime_from}" in
	*'${RUNTIME_BASE_IMAGE'[:}]*) ;;
	*)
		printf 'runtime stage in %s must build FROM ${RUNTIME_BASE_IMAGE...}\n' "${runtime_dockerfile}" >&2
		return 1
		;;
	esac

	runtime_lock=$(sed -n "s/^DEV_DISTROLESS_STATIC_IMAGE_LOCK='\(.*\)'\$/\1/p" "${runtime_lockfile}")
	if [ -n "${runtime_lock}" ] && ! printf '%s\n' "${runtime_lock}" | grep -Eq '^[^@]+@sha256:[a-f0-9]{64}$'; then
		printf 'DEV_DISTROLESS_STATIC_IMAGE_LOCK must be pinned by digest in %s\n' "${runtime_lockfile}" >&2
		return 1
	fi

	# The last USER instruction wins in Docker, so judge that one. Only a literal
	# user name or non-zero UID passes: root, UID 0 (in any spelling), and
	# variables that cannot be checked here are rejected.
	runtime_user=$(printf '%s\n' "${runtime_stage}" | sed -n 's/^[[:space:]]*[Uu][Ss][Ee][Rr][[:space:]]\{1,\}\([^[:space:]]*\).*/\1/p' | tail -n 1)
	runtime_user=${runtime_user%%:*}
	if [ -z "${runtime_user}" ] || [ "${runtime_user}" = root ] ||
		printf '%s\n' "${runtime_user}" | grep -Eq '^0+$|[$]'; then
		printf 'runtime stage in %s must set a non-root USER\n' "${runtime_dockerfile}" >&2
		return 1
	fi

	runtime_entrypoint=$(printf '%s\n' "${runtime_stage}" | sed -n 's/^[[:space:]]*[Ee][Nn][Tt][Rr][Yy][Pp][Oo][Ii][Nn][Tt][[:space:]]\{1,\}//p' | tail -n 1)
	case "${runtime_entrypoint}" in
	'['*) ;;
	*)
		printf 'runtime stage in %s must use an exec-form ENTRYPOINT\n' "${runtime_dockerfile}" >&2
		return 1
		;;
	esac
}
