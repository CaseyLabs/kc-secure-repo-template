# AI Agent Support

This repository includes optional guidance for AI coding tools. These files are
part of the template because maintainers often use agents for reviews,
maintenance, and repetitive repository tasks.

## Files And Directories

- `AGENTS.md`: durable repository rules for coding agents.
- `CLAUDE.md`: a small Claude Code shim that imports `AGENTS.md`.
- `.agents/code_review.md`: repository-specific `/review` checklist.
- `.agents/skills/`: task-specific workflows for compatible agents.
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
- remove skills that do not apply to the derived project
- add subtree `AGENTS.md` files only where a directory has real local hazards or
  verification needs
- keep `CLAUDE.md` shims small when Claude Code compatibility is useful

Do not put secrets, credentials, private URLs, or unreviewed operational details
in agent guidance.

## Common Uses

- `/review`: inspect a change using `.agents/code_review.md`.
- `$security-review`: run the explicit security review skill when installed and
  supported by the agent.
- PR handoff drafting: summarize real diffs and validations after substantive
  changes are complete.

Agent support is optional for humans using the template. The repository should
remain understandable through `README.md`, `docs/`, `Makefile`, and subsystem
READMEs without requiring an AI tool.
