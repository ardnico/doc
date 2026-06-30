# Production Phase CR Workflow

## 1. Purpose

This workflow defines how agents are used in the production phase of waterfall-style development.

The goal is to make code review easier by preparing implementation rationale, evidence, and post-change check results before CR.

## 2. Workflow

```text
1. Detailed design is available
   ↓
2. Pre-Implementation Strategy Agent runs
   ↓
3. Developer and reviewers confirm implementation method
   ↓
4. Code is changed
   ↓
5. Build / local checks / Coverity are executed when available
   ↓
6. Post-Change CR Package Agent runs
   ↓
7. CR Review Package is generated
   ↓
8. CR is held
   ↓
9. Fixes are applied based on CR comments
   ↓
10. Handoff to testing
```

## 3. Agent placement

### 3.1 Pre-Implementation Strategy Agent

Runs before coding.

Main output:

- implementation strategy,
- feature-level implementation intent,
- official API evidence,
- CR explanation draft,
- human review questions.

### 3.2 Post-Change CR Package Agent

Runs after coding.

Main output:

- CR review package,
- post-change check report,
- vulnerability/robustness findings,
- coding rule findings,
- Coverity summary,
- design difference analysis,
- fix proposals.

## 4. CR timing

CR should not be held immediately after code modification.

Recommended timing:

```text
Code changed
  ↓
Post-change Agent executed
  ↓
Blocking gaps fixed or disclosed
  ↓
CR package generated
  ↓
CR held
```

## 5. CR readiness

Use one of the following states.

| State | Meaning |
|---|---|
| READY | Evidence is sufficient and no blocking gaps are found. |
| READY WITH RISKS | CR can proceed, but risks or missing evidence must be disclosed. |
| NOT READY | Blocking gaps exist. Fix or clarify before CR. |

## 6. Minimum CR package

A CR package must include:

1. Review scope
2. Functional implementation intent
3. Design evidence
4. Official API evidence
5. Code change summary
6. Behavior change summary
7. Risk and robustness check
8. Coding rule check
9. Coverity/static analysis result
10. Design difference analysis
11. Fix proposal list
12. Remaining questions
