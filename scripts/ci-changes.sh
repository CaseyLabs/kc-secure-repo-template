#!/bin/sh
# shellcheck shell=sh
set -eu

# Decide which expensive test jobs need to run for the current GitHub Actions
# event. The workflow itself is still triggered for every pull request so
# required checks do not get stuck pending when a change is intentionally skipped.
#
# Classification order (first match wins, anything unknown runs both jobs):
#   1. src, build/test scripts, shared config, test.yml -> test-code + test-repo
#   2. prose (root guidance, docs/, .agents/ and .claude/ Markdown, config
#      subtree AGENTS.md/CLAUDE.md)                     -> neither job
#   3. other scripts (allowlist), .github/, .gitignore, remaining config/,
#      non-Markdown agent files                         -> test-repo only
#   4. everything else                                   -> test-code + test-repo

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
	# commit by default. Its first parent is the current base and the merge commit
	# is the exact tree under test, so this comparison excludes changes that exist
	# only because the pull request base advanced independently.
	github_sha=${GITHUB_SHA:-}
	if [ -z "${github_sha}" ]; then
		return 1
	fi
	if ! git rev-parse --verify -q "${github_sha}^{commit}" >/dev/null 2>&1; then
		return 1
	fi
	if ! git rev-parse --verify -q "${github_sha}^1" >/dev/null 2>&1; then
		return 1
	fi
	if ! git rev-parse --verify -q "${github_sha}^2" >/dev/null 2>&1; then
		return 1
	fi

	# Never collapse a delete/add pair into a rename: both paths can belong to
	# different test categories. Quoted output also turns unusual pathnames into
	# deliberately unrecognized input, which takes the conservative run-all path.
	LC_ALL=C git -c core.quotePath=true diff --no-renames --name-only \
		"${github_sha}^1" "${github_sha}" --
}

# Paths that affect BOTH test jobs: the src/ example workspace and everything
# `make test` (src mode) executes.
#
# Invariant: `make test` in src mode only uses scripts/test.sh, scripts/build.sh,
# the Dockerfile/.dockerignore build inputs, the Makefile, and the two shared
# config files below. If test.sh or build.sh ever start calling another script,
# add that script here, or test-code will be skipped when it changes.
is_source_test_path() {
	case "$1" in
	src/* | Dockerfile | .dockerignore | Makefile | scripts/build.sh | scripts/test.sh | config/project.cfg | config/lockfile.cfg | .github/workflows/test.yml)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# Prose that cannot affect build or execution behavior: skips both test jobs.
is_recognized_prose_path() {
	case "$1" in
	AGENTS.md | CLAUDE.md | README.md | LICENSE.md | code_review.md | docs/*.md | .agents/*.md | .claude/*.md | config/*/AGENTS.md | config/*/CLAUDE.md)
		return 0
		;;
	*)
		return 1
		;;
	esac
}

# Paths that only the generated-repository (test-repo) job exercises. Scripts
# are an explicit allowlist so a newly added script falls back to both jobs.
is_repo_only_path() {
	case "$1" in
	scripts/clean.sh | scripts/dist.sh | scripts/example.sh | scripts/infra.sh | scripts/k8s-test-local.sh | scripts/k8s.sh | scripts/logs.sh | scripts/renovate.sh | scripts/run.sh | scripts/scan.sh | scripts/shell.sh | scripts/status.sh | scripts/stop.sh | scripts/template.sh | scripts/update.sh | scripts/workflow-policy.sh | scripts/ci-changes.sh)
		return 0
		;;
	.github/* | .gitignore | .claude/* | .agents/* | config/*)
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
		test_repo=true
	elif is_recognized_prose_path "${path}"; then
		:
	elif is_repo_only_path "${path}"; then
		test_repo=true
	else
		# Unknown paths, including Git-quoted pathnames, run both jobs. New
		# repository surfaces must opt into a narrower category deliberately.
		test_code=true
		test_repo=true
	fi
done <<EOF
${changed_files}
EOF

write_output test_code "${test_code}"
write_output test_repo "${test_repo}"
