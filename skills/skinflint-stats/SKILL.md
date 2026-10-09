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
2. Replies: `reply * 44 / 56`, across `replies` replies. Say plainly that
   this one is an estimate built on a measurement: the plugin's benchmark ran
   the same tool-using tasks with and without the plugin, and with it Claude's
   final replies were 56% of the size. That measured ratio is applied here to the replies actually
   written, because in a live session each prompt is answered only once, with
   the plugin on, so there is no second reply to compare against.
3. Cost of the plugin: `injected`, the rules and reminders it adds to the
   conversation. Measured.
4. Net: the first plus the second minus the third.

Then a fifth line, the net in dollars. Trimmed tool output and the plugin's
own text are input and replies are output, which costs five times as much
per token, so the tokens of the second figure count five times:
`(saved - injected + 5 * reply * 44 / 56) / 4` tokens, times $4 per million.
That is the API price of Claude Opus 5.5 ($4 per million input tokens, $20
per million output tokens); say so, and say that it is a floor, because text
that stays in the conversation is sent again with each later request and
that repeat is not counted. Give it to the cent.
