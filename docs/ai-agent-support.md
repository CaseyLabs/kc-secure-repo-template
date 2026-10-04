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
  and their corresponding `.claude/skills/` entrypoints
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

## Skills

- `repo-adaptation`: project customization, with optional language guidance in
  `references/language-guidance.md`.
- `github-hardening`: GitHub controls, with Terraform procedures in
  `references/terraform.md`.
- `workflow-validation`: checks shared across repository workflows.
- `release-integrity`: artifact verification and release evidence.
- `security-review`: explicitly invoked security analysis.
- `pr-draft-summary`: PR handoff text grounded in the diff and completed checks.

The references live inside their owning canonical skill directories and load
only for relevant tasks. The former `language-profile-guidance` and
`terraform-hardening` skill commands are replaced by `repo-adaptation` and
`github-hardening`, respectively.

## Common Uses

- Codex CLI: use `/skills` to browse skills and `$skill-name` to select one.
- Claude Code: use `/skills` to browse skills and `/skill-name` to select one.
- Security review: explicitly invoke `$security-review` in Codex or
  `/security-review` in Claude. Codex's `agents/openai.yaml` policy and Claude's
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
  Confirm `security-review` is not selected for ordinary review requests; then
  invoke it explicitly on a small named diff and confirm it proceeds.
- If a skill is missing or behaves differently, check user/plugin skills with
  the same name and local settings before changing the shared instructions.

Claude entrypoints use regular files with relative links so Git checkouts and
template archives do not require symlink support. The archive includes
`.claude/skills/` and the canonical `.agents/` files; other `.claude/` settings
are not part of the template manifest. `.claude/` is excluded from Docker build
context, like `.agents/`.

See the official [Codex instruction discovery guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md),
[Codex skills guide](https://learn.chatgpt.com/docs/build-skills),
[Claude memory guide](https://code.claude.com/docs/en/memory), and
[Claude skills guide](https://code.claude.com/docs/en/skills) for current behavior.

Agent support is optional for humans using the template. The repository should
remain understandable through `README.md`, `docs/`, `Makefile`, and subsystem
READMEs without requiring an AI tool.
