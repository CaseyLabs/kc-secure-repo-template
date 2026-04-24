#!/bin/sh
set -eu

# Print the list of files that belong in the distributed template archive.
list_template_files() {
	export LC_ALL=C

	cat <<'EOF' |
AGENTS.md
CLAUDE.md
Dockerfile
LICENSE.md
Makefile
README.md
code_review.md
.dockerignore
.gitignore
.agents
.github
docs
config
scripts
src
EOF
		while IFS= read -r path; do
			[ -n "${path}" ] || continue
			# Expand directories into their files, but skip build outputs and local state.
			if [ -d "${path}" ]; then
				find "${path}" \
					-type d \( -name dist -o -name .terraform -o -name node_modules -o -name coverage -o -name .cache -o -name .tmp \) -prune -o \
					-type f \
					! -name '.terraform.lock.hcl' \
					! -name '*.tfstate' \
					! -name '*.tfstate.*' \
					! -name '*.tfplan' \
					! -name '*.tfvars' \
					! -name 'crash.log' \
					! -path 'src/app' \
					-print
			elif [ -e "${path}" ]; then
				printf '%s\n' "${path}"
			fi
		done |
		LC_ALL=C sort
}

# Write a manifest file so release builds and tests can verify exactly what ships.
write_manifest() {
	mkdir -p dist
	{
		printf '%s\n' 'kc-secure-repo-template build manifest'
		list_template_files
	} >dist/template-manifest.txt
}

# Package the manifest-listed files into a reproducible release tarball.
write_release() {
	SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH:-0}
	export SOURCE_DATE_EPOCH

	write_manifest
	file_list=$(mktemp)
	trap 'rm -f "${file_list}"' EXIT INT TERM
	tail -n +2 dist/template-manifest.txt >"${file_list}"

	# Normalize ordering, timestamps, and ownership so repeated builds match byte-for-byte.
	tar --sort=name \
		--mtime="@${SOURCE_DATE_EPOCH}" \
		--owner=0 \
		--group=0 \
		--numeric-owner \
		--pax-option='delete=atime,delete=ctime' \
		-cf - \
		-T "${file_list}" |
		gzip -n >dist/kc-secure-repo-template.tar.gz
}

# Dispatch to the requested helper action.
case "${1:-}" in
files)
	list_template_files
	;;
manifest)
	write_manifest
	;;
release)
	write_release
	;;
*)
	printf 'usage: %s {files|manifest|release}\n' "$0" >&2
	exit 1
	;;
esac
