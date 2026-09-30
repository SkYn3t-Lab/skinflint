---
name: token-miser-audit
description: >
  Read-only audit of a diff, file or repository for things that cost tokens
  without earning them, in code and in prose, ranked by size. Use for
  "/token-miser-audit", "token-miser audit", "what can I cut", or "audit this
  for bloat".
---

Find what can be removed from the target and report it, biggest first. Change
nothing.

## Target

- No argument: the working-tree `git diff`, staged and unstaged. If that is
  empty, the last commit.
- A path: that file or directory.
- "repo": the whole tree, skipping vendored, generated and lock files.

## Look for

Code:
- a hand-written version of something the standard library or an installed
  dependency already provides;
- an abstraction, wrapper or factory with a single user;
- a new dependency doing what a few lines could;
- options and settings that are never changed;
- code written for a future that has no caller yet.

Prose (comments, docstrings, READMEs, docs):
- comments that repeat what the code plainly says;
- padding, hedging and repeated content;
- long explanations that one sentence would carry;
- headings, tables and emoji that add length but no information;
- stale sections, dead links, old TODO lists.

## Leave alone

Validation of untrusted input, error handling that protects data, security,
accessibility, simplifications already marked with a comment, and comments
that explain why rather than what.

## Report

One finding per line, largest saving first, no introduction:

```
path:line  code|prose  what is excess -> what replaces it (about N lines)
```

Mark a finding `(verify)` when removing it could change behaviour you cannot
confirm from what you read. Prefer a few certain findings to many guesses.
Finish with two lines: the counts by kind with the rough total removable, and
the single largest cut.
