# Privacy

skinflint is a Claude Code plugin that runs entirely on your own computer.
This page says what it reads, what it keeps, and what it sends.

## What it sends

Nothing. skinflint makes no network connection of any kind. It has no
server, no account, no analytics and no telemetry, and its author receives
no information about you or your use of it.

## What it reads

Claude Code hands each hook its own input, and skinflint reads only that:

- the text of a prompt you submit, to see whether it is one of the on and
  off switches (for example `stop skinflint`);
- the output of a tool call, to trim it before Claude reads it;
- the `outputStyle` setting in your Claude Code settings files, and
  skinflint's own configuration files and `SKINFLINT_*` environment
  variables, to decide how to behave;
- the standard environment variables that say where your home and
  configuration folders are, to find those files.

It looks at nothing else on your computer, and it never looks for
credentials.

## What it keeps

skinflint writes to one folder, `skinflint` inside your Claude Code
configuration folder (normally `~/.claude/skinflint`), readable only by
your user account:

| File | Holds | Removed |
|---|---|---|
| `sessions/<session>.mode` | `on` or `off` for that session | at the next session start once it is more than 7 days old |
| `sessions/<session>.<tool>.last` | the previous output of that tool, so that an identical repeat can be dropped | at the next session start once it is more than 7 days old |
| `spill/*.txt` | the full text of a tool output that was trimmed, so that Claude can search it instead of running the command again | when there are more than 60, the oldest are deleted until 40 remain |
| `stats` | two numbers: bytes trimmed and how many times | never; delete it whenever you like |

Tool output that looks like it holds a credential (a private key, an API
key, a token or a password) is never written to `spill`.

Set `SKINFLINT_SPILL=0` to keep no copies of trimmed output, and
`SKINFLINT_DEDUP=0` to keep no previous output.

On Windows, skinflint also builds its own program from the source in this
repository the first time it runs, and keeps it in the plugin's data folder.

## Removing it

Uninstall the plugin and delete the `skinflint` folder described above.
Nothing remains anywhere else.

## What skinflint does not control

Claude Code and the Claude models are provided by Anthropic and are covered
by Anthropic's own privacy policy. skinflint changes how much text Claude
reads and writes; it does not change where Claude Code sends it.

## Questions

Open an issue at https://github.com/SkYn3t-Lab/skinflint/issues.
