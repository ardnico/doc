# Review Checkpoints

## 1. Functional correctness

- Does the implementation satisfy each design requirement?
- Are non-goals preserved?
- Is behavior change explained?
- Are public interfaces unchanged or approved?

## 2. Evidence

- Is the target version identified?
- Is official API evidence linked?
- Is the design document version identified?
- Are source paths and functions shown?
- Are Redmine/past issue links shown when relevant?

## 3. Robustness

- Are return values checked?
- Are bounds checked?
- Are NULL pointers handled?
- Are resources released on all error paths?
- Is cleanup order correct?
- Are race conditions considered?
- Is hardware state assumption justified?

## 4. Linux / driver points

- probe/remove symmetry
- init/exit symmetry
- devm_* lifetime
- IRQ handler constraints
- locking and concurrency
- sysfs/debugfs/procfs behavior
- device node and udev behavior
- Kconfig/Makefile integration
- Yocto recipe/bbappend integration
- boot/suspend/resume effects

## 5. Static analysis / Coverity

- Was Coverity executed?
- Are there new defects?
- Are defects mapped to changed files?
- Are fixes proposed?
- If not executed, is that disclosed?

## 6. CR readiness

Do not proceed as READY when:

- evidence is missing,
- design mismatch is unexplained,
- critical error handling is missing,
- Coverity is required but not executed,
- build status is unknown and required.
