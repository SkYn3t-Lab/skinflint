---
name: token-miser-stats
description: >
  Show how much tool output token-miser has trimmed so far. Use for
  "/token-miser-stats", "token-miser stats" or "how much has token-miser saved".
---

Read the file `token-miser/stats` inside the Claude Code configuration
folder (`$CLAUDE_CONFIG_DIR` if set, otherwise `~/.claude`). It holds two
lines, `saved <bytes>` and `events <count>`. Do not read any other file there.

Report it in one short paragraph: bytes of tool output removed, an estimate in
tokens (bytes divided by 4, rounded), and how many tool results were
shortened. Every trimmed line would otherwise have been sent again with each
later request in its session, so say that the real saving is larger than
this one-time figure. If the file does not exist, say that nothing has been
trimmed yet.
