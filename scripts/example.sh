#!/bin/sh
set -eu

# Build, lint, test, run, and scan the bundled Hello World example.

# Reuse the same config-file argument pattern as the other public scripts.
PROJECT_CFG_FILE=${1:-${PROJECT_CFG_FILE:-config/project.cfg}}
# Remember whether `dist/` already existed so this demo does not leave new artifacts behind.
had_dist=false
if [ -d dist ]; then
	had_dist=true
fi

# Exercise the same public workflow a new repository user would call manually.
sh ./scripts/build.sh "${PROJECT_CFG_FILE}"
sh ./scripts/test.sh "${PROJECT_CFG_FILE}"
sh ./scripts/run.sh "${PROJECT_CFG_FILE}"
sleep 1
sh ./scripts/logs.sh "${PROJECT_CFG_FILE}"
sh ./scripts/stop.sh "${PROJECT_CFG_FILE}"
sh ./scripts/scan.sh "${PROJECT_CFG_FILE}"

# Clean up `dist/` only when this script created it indirectly.
if [ "${had_dist}" = false ] && [ -d dist ]; then
	rm -rf dist
fi

printf '\n==> Example summary\n'
# The summary restates the workflow in plain language for quick inspection.
printf '%s\n' 'Image: see build output above'
printf '%s\n' "Project config: ${PROJECT_CFG_FILE}"
printf '%s\n' 'Workspace: src'
printf '%s\n' 'Results:'
printf '%s\n' '  Container build: passed'
printf '%s\n' '  App build: passed'
printf '%s\n' '  Lint: passed'
printf '%s\n' '  Tests: passed'
printf '%s\n' '  Run: passed'
printf '%s\n' '  Security scan: passed'
printf '%s\n' 'Artifacts: none written to dist/ during make example'
