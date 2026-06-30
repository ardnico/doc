# Prompt: Coverity Result Analysis

You are analyzing Coverity output as part of the Post-Change CR Package Agent.

## Task

Summarize Coverity results and map each finding to implementation risk and fix proposal.

## Required output

```md
# Coverity Result Summary

## 1. Execution Information
- Command:
- Date:
- Coverity version:
- Target branch/commit:
- Build target:

## 2. Overall Result
- New defects:
- Existing defects:
- Dismissed defects:
- Blocking defects:

## 3. New Defects
| No. | CID | Checker | File | Function | Severity | Summary | Proposed Fix |
|---:|---|---|---|---|---|---|---|

## 4. Impact on CR Readiness

## 5. Required Human Decisions
```

## Rules

- Do not say Coverity passed unless the result explicitly shows no blocking/new defects.
- If output is incomplete, mark the analysis as incomplete.
- If the command was not executed, state `NOT EXECUTED`.
