---
name: token-miser-help
description: >
  Show the token-miser commands and settings. Use for "/token-miser-help",
  "token-miser help" or "how do I use token-miser".
---

Show this card and stop.

| Say or type | What happens |
|---|---|
| `/token-miser`, `token-miser on` | Turn it on for this session |
| `stop token-miser`, `normal mode`, `/token-miser off` | Turn it off for this session |
| `/token-miser-review` | Review the current diff for code that can be removed |
| `/token-miser-audit [path]` | Rank everything removable, code and prose |
| `/token-miser-debt` | List every shortcut marked with a `token-miser:` comment |
| `/token-miser-stats` | Show how much tool output has been trimmed so far |

A switch only works as the whole message; a sentence that mentions it does
not switch anything.

While it is on, long tool output is shortened before Claude reads it. When
lines are cut, the full text is saved and the note in the output names the
file.

Settings, as environment variables: `TOKEN_MISER_DEFAULT_MODE=off` starts
sessions off, `TOKEN_MISER_COMPRESS=0` leaves tool output alone,
`TOKEN_MISER_MAX_BYTES` sets how large output may be before lines are cut
(default 8000). The README lists the rest.
