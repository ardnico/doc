# Numbering Rule for CR Materials

## 1. Purpose

CR documents must be easy to reference during review.

Every CR-facing section must use stable numbering.

## 2. Required style

Use this format:

```md
## 1. Review Scope
### 1.1 Target Change
### 1.2 Non-goals

## 2. Functional Implementation Intent
### 2.1 Functional Unit A
### 2.2 Functional Unit B
```

## 3. Tables

Tables must include a `No.` column.

Example:

```md
| No. | File | Change | Reason |
|---:|---|---|---|
| 5.1.1 | drivers/xxx/foo.c | Add error path | Required by design |
```

## 4. References

When a reviewer asks about a point, they should be able to say:

- `See 4.2.1 for API evidence.`
- `See 7.4 for resource cleanup check.`
- `See 12.1 for proposed fix.`

## 5. Stability

Do not renumber unrelated sections when making small updates if review comments already exist.
