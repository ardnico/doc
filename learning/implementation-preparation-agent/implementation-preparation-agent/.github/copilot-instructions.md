# Copilot Instructions: CR-Oriented Implementation Support

This repository uses Copilot as a production-phase implementation support assistant.

Do not behave as a generic coding assistant. Follow `AGENTS.md`.

## Main workflow

There are two supported modes.

### Mode A: Pre-Implementation Strategy

Use this before coding.

Goal:

- understand the detailed design,
- identify candidate implementation locations,
- prepare functional implementation intent,
- collect official API evidence with version information,
- prepare CR explanation draft.

Prompt:

- `prompts/pre_implementation_strategy_prompt.md`

Template:

- `templates/pre_implementation_strategy_report.md`

### Mode B: Post-Change CR Package

Use this after code changes.

Goal:

- inspect git diff,
- explain changes for CR,
- check vulnerability/robustness gaps,
- check coding rules,
- analyze Coverity/static analysis results,
- compare with design,
- propose fixes for gaps.

Prompt:

- `prompts/post_change_cr_package_prompt.md`

Templates:

- `templates/cr_review_package.md`
- `templates/post_change_check_report.md`
- `templates/fix_proposal_list.md`

## Hard rules

- Always separate facts, assumptions, and recommendations.
- Always confirm target versions before referencing official APIs or documentation.
- Never claim Coverity passed unless an actual result is provided or executed.
- Never hide design differences.
- Never invent missing specifications.
- Use stable section numbering in CR-facing documents.
- Prefer minimal, reviewable changes.
- Include file paths and function names when discussing code.
- Include document version, section, page, and URL/path when discussing evidence.

## CR readiness

Use one of:

- READY
- READY WITH RISKS
- NOT READY

Do not mark READY when:

- design evidence is missing,
- official API evidence is missing for API-based changes,
- build result is unknown and required,
- Coverity/static checks are required but not executed,
- critical robustness gaps remain,
- implementation differs from design without explanation.
