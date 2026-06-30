# Agent Boundary

## 1. What the agents replace

The agents partially replace the following manual preparation tasks:

- reading detailed design before implementation,
- identifying implementation targets,
- preparing explanations for CR,
- collecting official API evidence,
- checking implementation gaps after code changes,
- summarizing static analysis/Coverity results,
- preparing fix proposals.

## 2. What the agents do not replace

The agents do not replace:

- design approval,
- implementation ownership,
- final CR judgment,
- formal test execution,
- Redmine closure,
- release approval.

## 3. Human responsibility

Humans remain responsible for:

- deciding implementation method,
- judging design ambiguity,
- approving interface changes,
- confirming hardware behavior,
- accepting residual risks,
- determining whether CR can proceed.

## 4. Why this boundary exists

The highest-cost part of CR is not usually reading code. It is reconstructing:

- why this code exists,
- why this API was used,
- whether this matches the design,
- whether error paths and risks were checked,
- whether generated changes are explainable.

The agents focus on that explanation and evidence gap.
