# Adoption Plan

## 1. Goal

Introduce the agent in a narrow production-phase workflow without expanding into a general-purpose AI system.

## 2. Phase 0: Manual pilot

Choose one small implementation task.

Recommended:

- error handling addition,
- log addition,
- limited driver behavior change,
- Kconfig/DTS/recipe small change.

Use the templates manually first.

## 3. Phase 1: Pre-implementation Agent

Run only `Pre-Implementation Strategy Agent`.

Measure:

- Did it identify the correct files?
- Did it expose unknowns early?
- Did it produce useful CR explanation points?

## 4. Phase 2: Post-change Agent

Run `Post-Change CR Package Agent` after code change.

Measure:

- Did it reduce CR explanation effort?
- Did it find missing error handling?
- Did it summarize changes clearly?
- Did it disclose missing Coverity/build evidence?

## 5. Phase 3: Team usage

Standardize:

- request template,
- CR review package template,
- evidence policy,
- numbering rule.

Do not add RAG, Redmine automation, or automatic ticket updates until this workflow is accepted.

## 6. Success metrics

- CR preparation time reduced.
- Review comments about “why this change?” reduced.
- Missing evidence found before CR.
- Design/code mismatch found before CR.
- Agent output accepted by at least one other reviewer.
