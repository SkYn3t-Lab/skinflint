---
name: skinflint-stats
description: >
  Show everything skinflint has saved so far: tool output trimmed, the
  estimated saving on replies, and what the plugin itself costs. Use for
  "/skinflint-stats", "skinflint stats" or "how much has skinflint saved".
---

Read the file `skinflint/stats` inside the Claude Code configuration
folder (`$CLAUDE_CONFIG_DIR` if set, otherwise `~/.claude`). It holds up to
five lines: `saved <bytes>`, `events <count>`, `reply <bytes>`,
`replies <count>` and `injected <bytes>`. A missing line counts as 0. Do not
read any other file there. If the file does not exist, say that nothing has
been recorded yet and stop.

Report four figures, each in bytes and in tokens (bytes divided by 4,
rounded), one short line each:

1. Tool output trimmed: `saved`, across `events` tool results. Measured.
2. Replies: `reply * 51 / 49`, across `replies` replies. Say plainly that
   this one is an estimate: in the plugin's benchmark Claude wrote 49% of the
   output it wrote without the plugin, and this applies that ratio to the
   replies actually written. What Claude would have written without the
   plugin is never recorded, so it cannot be measured.
3. Cost of the plugin: `injected`, the rules and reminders it adds to the
   conversation. Measured.
4. Net: the first plus the second minus the third.

Then one sentence of context: trimmed tool output and the plugin's own text
are input, which is sent again with each later request in the session, and
replies are output, which costs several times more per token than input, so
the net in bytes understates the saving in money when the reply figure is
the large one.
