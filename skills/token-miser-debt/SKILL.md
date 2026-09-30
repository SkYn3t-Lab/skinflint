---
name: token-miser-debt
description: >
  List every deliberate shortcut marked with a `token-miser:` comment in the
  repository, so skipped work is tracked instead of forgotten. Use for
  "/token-miser-debt", "token-miser debt" or "what did we skip".
---

Collect every comment that contains `token-miser:` in the current repository
and report them as a ledger. Change nothing.

Search with one command, skipping vendored and generated folders:

```sh
git grep -n "token-miser:" -- . ':!node_modules' ':!dist' ':!build' 2>/dev/null || grep -rn "token-miser:" --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=dist --exclude-dir=build .
```

Report one line per shortcut, grouped by file, no introduction:

```
path:line  what was left out  ->  when it would be worth adding
```

Take both halves from the comment itself; if the comment gives no trigger for
adding it, write "no trigger given". End with one line: the number of
shortcuts and how many files hold them. If there are none, say so in one line.
