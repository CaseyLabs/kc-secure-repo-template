#!/bin/sh
# Shared AI-agent setup checks used by make scan and behavioral regression tests.
#
# AGENTS.md asks agents and maintainers to keep skill entrypoints aligned and the
# root guidance short. These checks enforce that outside the model, so drift is
# caught in review instead of surfacing as a skill that silently stops loading.

# Shared Claude Code deny rules that derived repositories should keep. Each rule
# matches the flag in any argument position (see docs/ai-agent-support.md).
AGENT_REQUIRED_DENY_RULES='Bash(git push --force*)
Bash(git push * --force*)
Bash(git push -f*)
Bash(git push * -f*)
Bash(git commit --no-verify*)
Bash(git commit * --no-verify*)
Bash(git commit -n*)
Bash(git commit * -n*)'

# Frontmatter keys from the Agent Skills specification. Canonical skills under
# .agents/skills/ are shared by Codex and Claude Code, so they use only these;
# host-only keys such as `disable-model-invocation` belong in the
# .claude/skills/ entrypoints instead.
AGENT_PORTABLE_SKILL_KEYS='name description license compatibility metadata'

# Print the top-level keys of a SKILL.md YAML frontmatter block, one per line.
agent_frontmatter_keys() {
	awk '
		NR == 1 && $0 == "---" { in_frontmatter = 1; next }
		in_frontmatter && $0 == "---" { exit }
		in_frontmatter && /^[A-Za-z0-9_-]+:/ { sub(/:.*/, ""); print }
	' "$1"
}

# Print one frontmatter value. Handles plain one-line values and YAML block
# scalars (`|` or `>`), whose indented lines are printed as-is so two files can
# be compared exactly.
agent_frontmatter_value() {
	awk -v key="$2" '
		NR == 1 && $0 == "---" { in_frontmatter = 1; next }
		in_frontmatter && $0 == "---" { exit }
		!in_frontmatter { exit }
		in_block {
			if ($0 ~ /^[A-Za-z0-9_-]+:/) { exit }
			print
			next
		}
		index($0, key ":") == 1 {
			value = substr($0, length(key) + 2)
			sub(/^[[:space:]]+/, "", value)
			if (value ~ /^[|>][-+]?$/) { in_block = 1; next }
			print value
			exit
		}
	' "$1"
}

# Check that canonical skills and Claude entrypoints stay paired and aligned.
check_agent_skill_policy() {
	agent_policy_status=0

	for agent_skill_file in .agents/skills/*/SKILL.md; do
		[ -f "${agent_skill_file}" ] || continue
		agent_skill_name=${agent_skill_file#.agents/skills/}
		agent_skill_name=${agent_skill_name%/SKILL.md}
		agent_entry_file=.claude/skills/${agent_skill_name}/SKILL.md

		if [ "$(agent_frontmatter_value "${agent_skill_file}" name)" != "${agent_skill_name}" ]; then
			printf '%s: frontmatter name must match the skill directory\n' "${agent_skill_name}" >&2
			agent_policy_status=1
		fi
		if [ -z "$(agent_frontmatter_value "${agent_skill_file}" description)" ]; then
			printf '%s: canonical skill needs a description\n' "${agent_skill_name}" >&2
			agent_policy_status=1
		fi
		for agent_key in $(agent_frontmatter_keys "${agent_skill_file}"); do
			case " ${AGENT_PORTABLE_SKILL_KEYS} " in
			*" ${agent_key} "*) ;;
			*)
				printf '%s: non-portable frontmatter key %s in %s (move host-only keys to the .claude/skills entrypoint)\n' \
					"${agent_skill_name}" "${agent_key}" "${agent_skill_file}" >&2
				agent_policy_status=1
				;;
			esac
		done

		if [ ! -f "${agent_entry_file}" ]; then
			printf '%s: missing Claude entrypoint %s\n' "${agent_skill_name}" "${agent_entry_file}" >&2
			agent_policy_status=1
			continue
		fi
		if [ "$(agent_frontmatter_value "${agent_entry_file}" name)" != "${agent_skill_name}" ]; then
			printf '%s: frontmatter name in %s must match the skill directory\n' "${agent_skill_name}" "${agent_entry_file}" >&2
			agent_policy_status=1
		fi
		# Claude selects skills by the entrypoint description, Codex by the
		# canonical one; identical text keeps routing the same in both tools.
		if [ "$(agent_frontmatter_value "${agent_entry_file}" description)" != "$(agent_frontmatter_value "${agent_skill_file}" description)" ]; then
			printf '%s: entrypoint description differs from %s\n' "${agent_skill_name}" "${agent_skill_file}" >&2
			agent_policy_status=1
		fi
		# Entrypoints are regular files (archives need no symlink support) that
		# point at the canonical workflow with a relative link.
		if ! grep -Fq "](../../../.agents/skills/${agent_skill_name}/SKILL.md)" "${agent_entry_file}"; then
			printf '%s: entrypoint must link to ../../../.agents/skills/%s/SKILL.md\n' "${agent_skill_name}" "${agent_skill_name}" >&2
			agent_policy_status=1
		fi
	done

	for agent_entry_file in .claude/skills/*/SKILL.md; do
		[ -f "${agent_entry_file}" ] || continue
		agent_skill_name=${agent_entry_file#.claude/skills/}
		agent_skill_name=${agent_skill_name%/SKILL.md}
		if [ ! -f ".agents/skills/${agent_skill_name}/SKILL.md" ]; then
			printf '%s: Claude entrypoint has no canonical skill in .agents/skills/\n' "${agent_skill_name}" >&2
			agent_policy_status=1
		fi
	done

	# security-review is documented as explicit-invocation only in both tools.
	# Derived repositories may delete the skill, but not make it implicit.
	if [ -d .agents/skills/security-review ]; then
		if ! grep -Eq '^disable-model-invocation:[[:space:]]*true[[:space:]]*$' .claude/skills/security-review/SKILL.md 2>/dev/null ||
			! grep -Eq '^[[:space:]]+allow_implicit_invocation:[[:space:]]*false[[:space:]]*$' .agents/skills/security-review/agents/openai.yaml 2>/dev/null; then
			printf '%s\n' 'security-review: must stay manual-only (disable-model-invocation: true and allow_implicit_invocation: false)' >&2
			agent_policy_status=1
		fi
	fi

	return "${agent_policy_status}"
}

# Keep the always-loaded root guidance small. Codex and Claude Code load the
# whole root AGENTS.md into every session, and Codex stops reading project docs
# at 32 KiB by default, so long guidance costs context and can be truncated.
# Derived repositories can raise the budget in config/project.cfg.
check_agent_guidance_size() {
	agent_max_lines=${AGENT_GUIDANCE_MAX_LINES:-150}
	agent_max_bytes=${AGENT_GUIDANCE_MAX_BYTES:-12288}
	[ -f AGENTS.md ] || return 0

	agent_lines=$(wc -l <AGENTS.md | tr -d ' ')
	agent_bytes=$(wc -c <AGENTS.md | tr -d ' ')
	if [ "${agent_lines}" -gt "${agent_max_lines}" ] || [ "${agent_bytes}" -gt "${agent_max_bytes}" ]; then
		printf 'AGENTS.md has %s lines and %s bytes; the budget is %s lines and %s bytes. Move task procedures into skills or docs (see docs/ai-agent-support.md).\n' \
			"${agent_lines}" "${agent_bytes}" "${agent_max_lines}" "${agent_max_bytes}" >&2
		return 1
	fi
}

# Require the shared Claude Code deny rules. A plain text match keeps this
# check free of host tools beyond grep; the file is reviewed JSON.
check_agent_settings_policy() {
	if [ ! -f .claude/settings.json ]; then
		printf '%s\n' '.claude/settings.json is missing; restore the shared deny rules (see docs/ai-agent-support.md)' >&2
		return 1
	fi

	agent_policy_status=0
	agent_rules_file=$(mktemp)
	printf '%s\n' "${AGENT_REQUIRED_DENY_RULES}" >"${agent_rules_file}"
	while IFS= read -r agent_rule; do
		if ! grep -Fq "\"${agent_rule}\"" .claude/settings.json; then
			printf '.claude/settings.json: missing deny rule %s\n' "${agent_rule}" >&2
			agent_policy_status=1
		fi
	done <"${agent_rules_file}"
	rm -f "${agent_rules_file}"
	return "${agent_policy_status}"
}
