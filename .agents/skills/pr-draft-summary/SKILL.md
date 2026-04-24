---
name: pr-draft-summary
description: Draft a concise pull request handoff after substantive repository changes are finished or ready for review. Trigger when wrapping up code, test, script, workflow, release, security, documentation-with-behavior-impact, or template customization changes and the user needs a PR title/body grounded in the real diff, commits, and validations run. Do not use for tiny chat-only answers, speculative plans, or changes that are not ready for PR handoff.
---

# PR draft summary

## Overview

Prepare a reviewer-ready PR title and body for this secure repository template. Keep the handoff concise, factual, and aligned with the actual branch state.

## Workflow

1. Inspect the current branch and working tree.
2. Review the relevant diff, changed files, and recent commits.
3. Identify the user-facing or maintainer-facing reason for the change.
4. List only validation that actually ran in this thread.
5. Draft the PR handoff in the output format below.

Use repository evidence first. Good inputs include `git status --short --branch`, `git diff --stat`, `git diff --name-only`, `git log --oneline --decorate -5`, and the validation commands already run.

## PR content rules

- Keep the title imperative or conventional-commit style when that fits the branch.
- Keep the body short, grouped, and easy to scan.
- Explain why the change exists when the motivation is not obvious from the file list.
- Preserve important review reasoning, especially security, reproducibility, release, or template-boundary tradeoffs.
- List only checks that actually ran. Do not imply remote CI, release, package, or publication success unless verified live.
- Call out skipped or unavailable validation directly when relevant.
- Avoid mentioning unrelated files or uncommitted work that is outside the PR.
- Do not include generated marketing copy, broad background, or claims not supported by the diff.

## Output format

Return this block:

```markdown
## Branch

<branch-name>

## Title

<PR title>

## Body

### Summary
- <one concise bullet>
- <one concise bullet if useful>

### Validation
- `<command>` <result>
```

If the user asks for direct PR creation or update, use the same title and body content unless live branch or GitHub state shows it needs adjustment.
