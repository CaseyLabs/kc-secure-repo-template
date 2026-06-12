#!/bin/sh
# shellcheck shell=sh
set -eu

# Decide which expensive test jobs need to run for the current GitHub Actions
# event. The workflow itself is still triggered for every pull request so
# required checks do not get stuck pending when a change is intentionally skipped.

write_output() {
	key=$1
	value=$2

	if [ -n "${GITHUB_OUTPUT:-}" ]; then
		printf '%s=%s\n' "${key}" "${value}" >>"${GITHUB_OUTPUT}"
	else
		printf '%s=%s\n' "${key}" "${value}"
	fi
}

run_all() {
	write_output test_code true
	write_output test_repo true
}

changed_files_from_event() {
	# Main-branch pushes should keep running the full validation stack. The
	# detector is mainly for pull requests, where skipped jobs can still satisfy
	# branch protection when they are skipped by job-level conditions.
	if [ "${GITHUB_EVENT_NAME:-}" != pull_request ]; then
		return 1
	fi

	# On pull_request events, actions/checkout checks out GitHub's synthetic merge
	# commit by default. Comparing its two parents is fast and avoids calling the
	# GitHub API or granting pull-requests: read.
	if ! git rev-parse --verify -q "${GITHUB_SHA}^1" >/dev/null; then
		return 1
	fi
	if ! git rev-parse --verify -q "${GITHUB_SHA}^2" >/dev/null; then
		return 1
	fi

	git diff --name-only "${GITHUB_SHA}^1" "${GITHUB_SHA}^2"
}

is_source_test_path() {
	case "$1" in
	src/* | Dockerfile | .dockerignore | Makefile | scripts/* | config/project.cfg | config/lockfile.cfg | .github/workflows/test.yml)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

is_docs_or_agent_path() {
	case "$1" in
	docs/* | .agents/* | AGENTS.md | CLAUDE.md | README.md | LICENSE.md | code_review.md | *.md)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

changed_files_file=${CI_CHANGED_FILES_FILE:-}

if [ -n "${changed_files_file}" ]; then
	[ -f "${changed_files_file}" ] || {
		printf 'missing changed-files fixture: %s\n' "${changed_files_file}" >&2
		exit 1
	}
	changed_files=$(cat "${changed_files_file}")
else
	if ! changed_files=$(changed_files_from_event); then
		run_all
		exit 0
	fi
fi

# If the diff is unexpectedly empty, prefer validation over a silent skip.
if [ -z "${changed_files}" ]; then
	run_all
	exit 0
fi

test_code=false
test_repo=false

while IFS= read -r path; do
	[ -n "${path}" ] || continue

	if is_source_test_path "${path}"; then
		test_code=true
	fi

	if ! is_docs_or_agent_path "${path}"; then
		test_repo=true
	fi
done <<EOF
${changed_files}
EOF

write_output test_code "${test_code}"
write_output test_repo "${test_repo}"
