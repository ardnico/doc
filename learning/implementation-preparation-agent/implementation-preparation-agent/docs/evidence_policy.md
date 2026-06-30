# Evidence Policy

## 1. Purpose

This policy defines how agents must handle evidence for CR-oriented implementation support.

## 2. Primary evidence

Primary evidence includes:

- approved design documents,
- official documentation,
- official README files,
- source code,
- git diff / commits,
- Redmine tickets,
- datasheets,
- build logs,
- Coverity/static analysis results,
- test logs.

Generated summaries are not primary evidence.

## 3. Official API evidence

When official APIs are used, agents must collect:

- API name,
- target version,
- official document URL/path,
- section or anchor,
- relevant rule or description,
- mapping to code usage,
- match status.

If version information is missing, mark it as `UNKNOWN`.

## 4. Version discipline

Version must be checked at the beginning of the task when the implementation depends on:

- Linux kernel APIs,
- Yocto / WRLinux behavior,
- compiler behavior,
- Coverity behavior,
- hardware/datasheet behavior,
- external libraries,
- project README instructions.

## 5. Missing evidence

Do not hide missing evidence.

Use one of:

- `OK`
- `MISSING`
- `UNKNOWN`
- `NOT APPLICABLE`

## 6. Forbidden behavior

Agents must not:

- invent documentation links,
- cite unofficial pages as official evidence unless explicitly marked,
- claim Coverity passed without result,
- claim build passed without log,
- merge old and new document versions,
- treat assumptions as design decisions.
