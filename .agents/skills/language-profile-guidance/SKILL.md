---
name: language-profile-guidance
description: Use when adding or revising optional language-specific guidance for Go, Node.js, SQL, or small polyglot derived repositories without bloating the generic template. Keep language behavior optional. Do not use for generic template policy, routine validation, GitHub-settings-only work, or release-integrity-only work.
---

# Language profile guidance

Use this skill when adding or revising optional language-specific guidance for derived repositories.

## Use this skill when
- updating Go, Node.js, SQL, or polyglot guidance
- revising language-specific documentation
- deciding whether a language-specific check belongs in the template, docs, or a derived repository
- extending default validation guidance for a specific ecosystem

## Do not use this skill when
- the task is about generic template policy
- the task is about GitHub-side settings
- the task is about release-integrity design
- the task is just routine validation of existing behavior
- the task would make one language stack mandatory for all derived repositories

## Goals
- Improve usability for common project types without turning the template into a framework.
- Keep language-specific logic optional.
- Preserve the generic template's stable interface and security posture.

## Method
- Keep language-specific behavior optional rather than mandatory in the generic template.
- Do not break generic usage for repositories that do not use that language stack.
- Prefer documentation and examples over hard-coding specialized behavior into the base template.
- Keep the public interface stable even when language-specific implementation details differ.
- When adding language-specific checks, explain where they belong: template, docs, CI helper scripts, or derived repositories.
- Use `repo-adaptation` as the companion skill when language guidance changes the customization surface.

## Guidance areas
- Go: formatting, vetting, tests, vulnerability checks
- Node.js: lockfile-based installs, deterministic CI commands
- SQL: read-only validation in CI, dialect-appropriate linting or formatting
- Polyglot: keep one clear primary build path

## Output expectations
- State what language-specific guidance changed.
- Explain why it remains optional.
- Note whether the change belongs in docs, scripts, examples, or derived repositories.
