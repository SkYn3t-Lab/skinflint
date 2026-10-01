---
name: skinflint-review
description: >
  Review a diff or file for code that can be deleted or made simpler. One line
  per finding, no praise. Use for "/skinflint-review", "skinflint review"
  or "review this for bloat".
---

Review the current diff (or the file named) for code that does not need to
exist or could be much smaller. Ignore style.

Flag:
- an abstraction, wrapper or factory with one user;
- something the standard library, the platform or an installed dependency
  already does;
- a new dependency that a few lines would replace;
- a setting that never changes;
- code for a case nobody calls yet.

Do not flag validation of untrusted input, error handling that protects data,
security, accessibility, or anything the task asked for.

One finding per line, no introduction:

```
path:line: what is over-built. What to use instead.
```

End with one line: the number of findings and roughly how many lines they
would remove.
