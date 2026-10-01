---
name: skinflint-help
description: >
  Show the skinflint commands and settings. Use for "/skinflint-help",
  "skinflint help" or "how do I use skinflint".
---

Show this card and stop.

| Say or type | What happens |
|---|---|
| `/skinflint`, `skinflint on` | Turn it on for this session |
| `stop skinflint`, `normal mode`, `/skinflint off` | Turn it off for this session |
| `/skinflint-review` | Review the current diff for code that can be removed |
| `/skinflint-audit [path]` | Rank everything removable, code and prose |
| `/skinflint-debt` | List every shortcut marked with a `skinflint:` comment |
| `/skinflint-stats` | Show how much tool output has been trimmed so far |

A switch only works as the whole message; a sentence that mentions it does
not switch anything.

While it is on, long tool output is shortened before Claude reads it. When
lines are cut, the full text is saved and the note in the output names the
file.

Settings, as environment variables: `SKINFLINT_DEFAULT_MODE=off` starts
sessions off, `SKINFLINT_COMPRESS=0` leaves tool output alone,
`SKINFLINT_MAX_BYTES` sets how large output may be before lines are cut
(default 8000). The README lists the rest.
