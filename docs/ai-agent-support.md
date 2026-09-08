# AI Agent Support

This repository includes optional guidance for AI coding tools. These files are
part of the template because maintainers often use agents for reviews,
maintenance, and repetitive repository tasks.

## Files And Directories

- `AGENTS.md`: durable repository rules for coding agents.
- `CLAUDE.md`: a small Claude Code shim that imports `AGENTS.md`.
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
- keep `CLAUDE.md` shims small when Claude Code compatibility is useful

Do not put secrets, credentials, private URLs, or unreviewed operational details
in agent guidance.

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
- In Claude Code, use `/context` to confirm the root `CLAUDE.md` import loaded,
  and `/skills` to confirm the project entrypoints appear. Read a file under
  `config/infra/` or `config/k8s/` to check its local `CLAUDE.md` import.
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
