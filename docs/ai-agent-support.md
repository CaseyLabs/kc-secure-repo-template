# AI Agent Support

This repository includes optional guidance for AI coding tools. These files are
part of the template because maintainers often use agents for reviews,
maintenance, and repetitive repository tasks.

## Files And Directories

- `AGENTS.md`: shared durable repository rules for Codex CLI and Claude Code.
- `.agents/code_review.md`: repository-specific `/review` checklist.
- `.agents/skills/`: task-specific workflows for compatible agents.
- `.claude/skills/`: Claude Code entrypoints that load the canonical workflows
  from `.agents/skills/` when selected.
- `.claude/settings.json`: shared Claude Code deny rules for force-pushes and
  skipped commit hooks.
- `.githooks/commit-msg`: opt-in hook that rejects AI attribution in commit
  messages.
- `config/k8s/AGENTS.md` and `config/infra/AGENTS.md`: local rules for
  subtrees with extra hazards and verification needs.

The root guidance stays short so it is useful in agent context. More detailed
review and task workflows live under `.agents/` where they can be loaded only
when relevant.

## Why This Is Included

The template has security, release, workflow, and packaging rules that are easy
to weaken accidentally. Agent guidance records those durable constraints close to
the code so automated changes are more likely to preserve them.

The guidance is also meant to help derived repositories keep changes small,
reviewable, and grounded in the actual `Makefile`, scripts, workflows, and
configuration files.

## Adapting It

For a derived repository:

- keep `AGENTS.md` focused on durable project rules
- keep review-specific behavior in `.agents/code_review.md`
- keep task-specific workflows in `.agents/skills/`
- keep Claude entrypoint names and descriptions aligned with the canonical
  skills; edit workflow instructions only in `.agents/skills/`
- remove skills that do not apply to the derived project
  and their corresponding `.claude/skills/` entrypoints; `make scan` fails
  when one side is left behind
- add subtree `AGENTS.md` files only where a directory has real local hazards or
  verification needs

Codex builds its startup instruction chain from the repository root to its
working directory. When a task reaches another subtree, the root guidance
explicitly requires reading that subtree's `AGENTS.md`. Claude Code reads
`AGENTS.md` directly, including subtree guidance when opening files there.
This template assumes a Claude Code version and configuration that support
direct loading; it no longer ships `CLAUDE.md` import files.

Direct loading requires Claude Code v2.1.277 or later with its built-in
`agents-md` plugin enabled; use v2.1.281 or later for the session types excluded
by earlier releases. If an ancestor or local `CLAUDE.md`/`CLAUDE.local.md` prevents
loading, select `claude-md-and-agents-md` under Project instructions in `/config`.
The `.claude/skills/` entrypoints remain necessary for Claude skill discovery.

Do not put secrets, credentials, private URLs, or unreviewed operational details
in agent guidance.

## Guardrails Outside The Model

Rules that must always hold are enforced by tooling, not only written in
`AGENTS.md`:

- `.claude/settings.json` denies `git push --force`/`-f` and
  `git commit --no-verify`/`-n` when the flag immediately follows its
  subcommand. Later arguments are not scanned for those strings, which avoids
  blocking ordinary commands such as a commit message that mentions `-n`.
- Claude Code deny rules match command text, so they are not a security
  boundary: flags later in the command, bundled flags (`git commit -an`), and
  global options (`git -C . push -f`) are not matched. Branch protection and
  the `make scan` commit recheck are the real controls; these rules stop common
  agent mistakes early. Codex relies on its own sandbox and approval settings.
- `.githooks/commit-msg` and `make scan` reject AI attribution in commits; see
  the [commit rules](gitops-conventions.md#commits).
- Keep personal permission changes in `.claude/settings.local.json`, which is
  not shared or packaged.
- `make scan` checks the agent setup (`scripts/agent-policy.sh`):
  - every `.agents/skills/<name>/SKILL.md` has a matching
    `.claude/skills/<name>/SKILL.md` entrypoint and vice versa, with the same
    `name` and `description` and a relative link to the canonical file
  - canonical skills use only portable Agent Skills frontmatter keys (`name`,
    `description`, `license`, `compatibility`, `metadata`)
  - `repo-security-review` stays manual-only in both tools
  - root `AGENTS.md` stays within `AGENT_GUIDANCE_MAX_LINES` and
    `AGENT_GUIDANCE_MAX_BYTES` from `config/project.cfg`
  - `.claude/settings.json` keeps the shared deny rules in `permissions.deny`

## Maintaining Agent Guidance

Treat agent guidance like code: small, reviewed, and backed by checks.

- Add a rule only after an agent got something wrong without it, and phrase it
  as a check the agent can act on.
- Delete rules that agents already follow unprompted or that restate what the
  `Makefile`, scripts, or docs already make obvious.
- Put rules that must never break into a hook, deny rule, or `make scan` check,
  not into more emphatic wording.
- Keep one source per fact: durable rules in `AGENTS.md`, review criteria in
  `.agents/code_review.md`, procedures in the owning skill or doc, linked with
  a one-line trigger.
- When an agent repeats a mistake despite a rule, the rule is probably unclear
  or buried; rewrite or shorten it instead of adding another.
- Keep canonical skill frontmatter portable and put host-only keys in the
  `.claude/skills/` entrypoints or `agents/openai.yaml`.
- When Codex or Claude Code changes how it loads instructions or skills,
  update this page and the version notes above together.

## Skills

- `repo-adaptation`: project customization, with optional language guidance in
  `references/language-guidance.md`.
- `github-hardening`: GitHub controls, with Terraform procedures in
  `references/terraform.md`.
- `workflow-validation`: checks shared across repository workflows.
- `release-integrity`: artifact verification and release evidence.
- `repo-security-review`: explicitly invoked security analysis.
- `pr-draft-summary`: PR handoff text grounded in the diff and completed checks.

The references live inside their owning canonical skill directories and load
only for relevant tasks. The former `language-profile-guidance` and
`terraform-hardening` skill commands are replaced by `repo-adaptation` and
`github-hardening`, respectively. The former `security-review` skill is now
`repo-security-review` so it does not shadow Claude Code's built-in
`/security-review` command.

## Common Uses

- Codex CLI: use `/skills` to browse skills and `$skill-name` to select one.
- Claude Code: use `/skills` to browse skills and `/skill-name` to select one.
- Security review: explicitly invoke `$repo-security-review` in Codex or
  `/repo-security-review` in Claude. Codex's `agents/openai.yaml` policy and Claude's
  entrypoint `disable-model-invocation: true` prevent automatic invocation.
- Change review: use Codex's `/review` to select a diff, or ask either tool to
  review a specified diff using `.agents/code_review.md` without editing files.
  The checklist is loaded through the root instructions; its filename does not
  register a command or replace a tool's built-in review workflow.
- PR handoff drafting: summarize real diffs and validations after substantive
  changes are complete.

## Verify Discovery And Invocation

After changing guidance, start a fresh session in the repository:

- In Codex, ask it to list its loaded instruction sources and use `/skills` to
  confirm the repository skills appear. Start in `config/infra/` or `config/k8s/`
  to check the corresponding nested instruction chain.
- In Claude Code, use `/context` to confirm the root `AGENTS.md` loaded,
  and `/skills` to confirm the project entrypoints appear. Read a file under
  `config/infra/` or `config/k8s/` to check its local `AGENTS.md`.
- Try `$pr-draft-summary` in Codex or `/pr-draft-summary` in Claude on a prepared
  change, asking for text only. Confirm it reads the canonical workflow and
  reports only validation that actually ran.
- Ask for a PR handoff without naming a skill to check automatic selection.
  Confirm `repo-security-review` is not selected for ordinary review requests; then
  invoke it explicitly on a small named diff and confirm it proceeds.
- If a skill is missing or behaves differently, check user/plugin skills with
  the same name and local settings before changing the shared instructions.

Claude entrypoints use regular files with relative links so Git checkouts and
template archives do not require symlink support. The archive includes
`.claude/skills/`, `.claude/settings.json`, and the canonical `.agents/` files;
other `.claude/` files, such as personal `settings.local.json`, are not part of
the template manifest. `.claude/` is excluded from Docker build
context, like `.agents/`.

See the official [Codex instruction discovery guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[Codex skills guide](https://learn.chatgpt.com/docs/build-skills),
[Claude memory guide](https://code.claude.com/docs/en/memory), and
[Claude skills guide](https://code.claude.com/docs/en/skills) for current behavior.

Agent support is optional for humans using the template. The repository should
remain understandable through `README.md`, `docs/`, `Makefile`, and subsystem
READMEs without requiring an AI tool.
