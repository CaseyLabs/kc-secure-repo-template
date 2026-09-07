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

# Reject privileged or untrusted event triggers by default. These events can be
# safe only for tightly reviewed metadata-only automation, but this template's
# default CI paths build and scan pull request contents as untrusted code.
check_workflow_trigger_policy() {
	awk '
		{
			line = $0
			sub(/[[:space:]]+#.*$/, "", line)
			if (line ~ /(^|[^A-Za-z0-9_-])pull_request_target([^A-Za-z0-9_-]|$)/) {
				printf "%s:%d: pull_request_target is not allowed in template workflows\n", FILENAME, FNR
				found = 1
			}
			if (line ~ /(^|[^A-Za-z0-9_-])issue_comment([^A-Za-z0-9_-]|$)/) {
				printf "%s:%d: issue_comment is not allowed in template workflows\n", FILENAME, FNR
				found = 1
			}
			if (line ~ /(^|[^A-Za-z0-9_-])workflow_run([^A-Za-z0-9_-]|$)/) {
				printf "%s:%d: workflow_run requires a dedicated reviewed policy exception\n", FILENAME, FNR
				found = 1
			}
		}
		END {
			exit found ? 1 : 0
		}
	' .github/workflows/*.yml
}

# Block direct interpolation of actor-controlled event metadata into shell. Pass
# untrusted values through reviewed metadata-only steps or allowlisted values.
check_workflow_metadata_policy() {
	for workflow in .github/workflows/*.yml; do
		awk '
			function is_untrusted_metadata(line) {
				return line ~ /\$\{\{[^}]*github\.event\.(issue|comment)\./ ||
					line ~ /\$\{\{[^}]*github\.event\.pull_request\.(title|body|head_ref|head\.ref|head\.label)/ ||
					line ~ /\$\{\{[^}]*github\.event\.workflow_run\./ ||
					line ~ /\$\{\{[^}]*github\.head_ref/
			}
			{
				line = $0
				sub(/[[:space:]]+#.*$/, "", line)
				indent = match($0, /[^ ]/) ? RSTART - 1 : 0
				if (in_run && indent <= run_indent && line !~ /^[[:space:]]*$/) {
					in_run = 0
				}
				if (in_run && is_untrusted_metadata(line)) {
					printf "%s:%d: untrusted github.event metadata must not be interpolated directly into run steps\n", FILENAME, FNR
					found = 1
				}
				if (line ~ /^[[:space:]]*(-[[:space:]]*)?run:[[:space:]]*/) {
					run_indent = indent
					if (is_untrusted_metadata(line)) {
						printf "%s:%d: untrusted github.event metadata must not be interpolated directly into run steps\n", FILENAME, FNR
						found = 1
					}
					if (line ~ /^[[:space:]]*(-[[:space:]]*)?run:[[:space:]]*[>|]/) {
						in_run = 1
					}
				}
			}
			END {
				exit found ? 1 : 0
			}
		' "${workflow}" || return 1
	done
}
