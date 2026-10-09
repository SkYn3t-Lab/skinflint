# skinflint behaviour specification

This file is the contract. There are two implementations, POSIX sh + awk
(`hooks/*.sh`, `hooks/lib/*.awk`) and C# (`hooks/win/skinflint.cs`), and
for the same input and the same files on disk they must produce the same
bytes, apart from the platform differences named in section 8. The tests, in
the [skinflint-tests](https://github.com/SkYn3t-Lab/skinflint-tests) repository, are generated from this document, not from either implementation.

## 1. Units and text rules

- **Bytes.** Every size, limit and count of "characters" is a count of UTF-8
  bytes. A cut never splits a UTF-8 sequence: a cut that would land inside
  one moves to the nearest boundary that keeps less text.
- **Lines.** Text is split on `\n` only. `n` lines means `n - 1` newlines;
  text ending in `\n` has an empty last line. `\r` is ordinary content except
  where 4.2 says otherwise.
- **Case and space.** Lower-casing and trimming are ASCII only. Whitespace is
  space, tab, `\n`, `\r`, `\v`, `\f`.
- **Regexes** below are POSIX ERE over bytes. `\t`, `\r`, `\x1b` and `\x07`
  denote those single bytes. No other escapes are used.
- **JSON in.** Input is parsed as RFC 8259 JSON. `\uXXXX` escapes decode to
  UTF-8; a valid surrogate pair decodes to one code point; an unpaired
  surrogate decodes to U+FFFD. Invalid UTF-8 in the raw input, or any parse
  error, makes the hook a no-op (section 7). With a duplicate key, the last
  occurrence wins for lookups.
- **JSON out.** Strings are written with `"` and `\` escaped, `\b \f \n \r \t`
  for those bytes, `\u00xx` (lower-case hex) for every other byte below 0x20,
  and everything else, including non-ASCII, written as raw UTF-8. Output
  never contains insignificant whitespace.

## 2. Files

`CLAUDE_DIR` is `$CLAUDE_CONFIG_DIR` when set and non-empty, else
`$HOME/.claude` (`%USERPROFILE%\.claude` on Windows). State lives in
`STATE = CLAUDE_DIR/skinflint/`:

| Path | Content | Written by |
|---|---|---|
| `STATE/sessions/<sid>.mode` | `on` or `off`, nothing else | UserPromptSubmit, on a switch |
| `STATE/sessions/<sid>.<tool>.last` | `<tool_use_id>`, `\n`, then the previous unit (4.5) | PostToolUse, dedup |
| `STATE/spill/<tool>-<tool_use_id>-<slot>.txt` | one full original text slot | PostToolUse, elide |
| `STATE/stats` | five counters, one per line (2.1) | every hook that changes one |

- `<sid>` is `session_id` from the payload. It is used only when it matches
  `^[A-Za-z0-9_-]{1,128}$`; otherwise the session has no state (mode is the
  default, nothing is written, no dedup).
- `<tool>` is the tool name with every byte outside `[A-Za-z0-9_-]` removed,
  or `tool` if nothing remains. `<tool_use_id>` has the same bytes removed.
- Files are written in place, with permissions 0600 on POSIX, and only when
  the directory is writable. A write that cannot be done is skipped silently;
  it never fails the hook. Concurrent hooks can race; every reader treats a
  file it cannot parse as absent, except `stats`, which is then left
  unchanged rather than reset.
- Files are read only when they are regular files. A missing or unreadable
  file is treated as absent.
- **Pruning.** At SessionStart with source `startup`, files in
  `STATE/sessions/` older than 7 days are deleted. After a PostToolUse that
  wrote a spill file, when `STATE/spill/` holds more than 60 `.txt` files the
  oldest are deleted until 40 remain.

### 2.1 Stats

`STATE/stats` holds exactly these five lines, each a name, one space and a
decimal count:

    saved <bytes>
    events <count>
    reply <bytes>
    replies <count>
    injected <bytes>

- `saved` and `events`: bytes removed from tool output and how many tool
  results were changed (4.6).
- `reply` and `replies`: bytes of final replies written while the mode was
  `on`, and how many (5.4).
- `injected`: bytes of context the plugin itself added, the text X of every
  `additionalContext` printed by 5.1, 5.2 and 5.3.

A hook adds to the counters it names and rewrites the file. A file holding
only the first two lines, as written before the other three existed, is read
with those three at 0. A missing file starts all five at 0. Any other content
is left unchanged and nothing is added.

All five are measured. What the plugin saved on replies is not among them: in
a live session each prompt is answered once, with the plugin on, so the reply
Claude would have written without it does not exist. The benchmark did
measure both, by running the same tool-using tasks with and without the
plugin, and with it Claude's final replies were 56% of the size. Readers of
this file (the stats skill and the status line) apply that measured ratio to
the replies counted here, `reply * 44 / 56`, and say that the result is an
estimate.

The stats skill also gives the net in dollars. `saved` and `injected` are
input and replies are output, which costs five times as much per token on
every current Claude model, so the reply estimate counts five times:
`(saved - injected + 5 * reply * 44 / 56) / 4` tokens at $4 per million, the
API input price of Claude Opus 5.5. The price is written by hand here, in
`skills/skinflint-stats/SKILL.md` and in the README section "Seeing what it
saves".

**Config file**: `$XDG_CONFIG_HOME/skinflint/config.json`, else
`$HOME/.config/skinflint/config.json` (`%APPDATA%\skinflint\config.json`
on Windows). Keys, all optional:

```json
{ "defaultMode": "on", "sections": { "prose": true, "code": true } }
```

Any value of the wrong type is ignored.

**Project config file**: `./.claude/skinflint.json` (`.` is the hook
process's working directory, the project), same keys. Each valid key in it
replaces the config file's value for that key, so a project can turn
skinflint off (`{ "defaultMode": "off" }`) or drop one section.

**Environment**, all optional:

| Variable | Effect |
|---|---|
| `SKINFLINT_DEFAULT_MODE` | `on` or `off` (any case); beats the config file |
| `SKINFLINT_COMPRESS=0` | PostToolUse does nothing |
| `SKINFLINT_DEDUP=0` | no dedup |
| `SKINFLINT_SPILL=0` | no spill files |
| `SKINFLINT_TOOLS` | comma-separated tool names that replace the default list in 5.1 |
| `SKINFLINT_MAX_BYTES` | elide threshold, default 8000 |
| `SKINFLINT_HEAD_LINES` | default 60 |
| `SKINFLINT_TAIL_LINES` | default 40 |

A numeric variable is used when it is all ASCII digits, and at most 9 of
them, with a value above 0; otherwise the default applies.

## 3. Mode

- **Default mode**: `SKINFLINT_DEFAULT_MODE` if valid, else config
  `defaultMode` if it is the string `on` or `off` (any case), else `on`.
- **Session mode**: the trimmed, lower-cased content of `<sid>.mode` if that
  is `on` or `off`, else the default mode.
- Mode is per session. Compaction keeps the session id, so a switch made
  before compaction survives it.

**Sections.** `prose` and `code` both start as true. Config `sections.prose`
and `sections.code` override them when they are booleans. Then, unless the
config set `sections.prose` explicitly, the first of these files that holds
a string `outputStyle` decides: `./.claude/settings.local.json`,
`./.claude/settings.json`, `CLAUDE_DIR/settings.json` (`.` is the hook
process's working directory). A trimmed value that is empty is skipped; a
value equal to `default` (any case) stops the search with no change; any
other value turns `prose` off, because a custom output style already governs
prose.

## 4. PostToolUse processing

A tool call that fails (for Bash, a non-zero exit) reaches hooks as
PostToolUseFailure, not PostToolUse, and that event cannot replace the
output, so skinflint leaves failed calls as they are. Measured with Claude
Code 2.1.285: `ls` of a missing path fired only PostToolUseFailure.

### 4.1 Eligibility

The hook does nothing unless all of these hold:

1. session mode is `on` and `SKINFLINT_COMPRESS` is not `0`;
2. `tool_name` is a string and in the tool list: `SKINFLINT_TOOLS` if set
   (exact, trimmed names), else `Bash`, `PowerShell`, `Agent`, `WebFetch`,
   `WebSearch`, `Grep`, `Glob`, and any name starting with `mcp__`. `Read`,
   `Edit`, `Write`, `MultiEdit`, `NotebookEdit` and `NotebookRead` are never
   eligible, list or not;
3. `tool_response` is present and not null;
4. `tool_response` is not an object with `isImage` true, `interrupted`
   true, or a `persistedOutputPath` member (Claude Code already saved that
   output in full and shows Claude only a short preview of it);
5. no string value directly inside `tool_input` contains `skinflint/spill`
   or `skinflint\spill` (reading a spill file back must not be cut again);
6. the response has at least one text slot (4.1.1);
7. the response, and any object whose members hold slots, has no duplicate
   keys.

#### 4.1.1 Text slots

A text slot is a string the hook may rewrite:

- the response itself, if it is a string;
- in a response object, the value of each member named `stdout`, `stderr`,
  `output`, `content`, `text` or `result` that is a string;
- in a response that is an array, or in an array value of a `content`
  member: the `text` member of each element that is an object whose `type`
  member is the string `text`.

Slots are numbered 1, 2, ... in document order. Nothing else is rewritten.

#### 4.1.2 NUL characters

Before dedup and before 4.2, every U+0000 is removed from every slot, and
each one removed counts as one saved byte in 4.6. Windows programs that write
UTF-16 reach the hook with a NUL after every ASCII character; without them
the text reads normally. Everything after this step, spill files included,
sees the slot without NULs.

### 4.2 Per-slot pipeline

Each slot is processed on its own. A slot of 1024 bytes or less passes
unchanged. For a larger slot:

1. **Clean** the whole text (4.2.1) and collapse **exact repeats** (4.2.2).
2. If the result is longer than `MAX` bytes and has more than `HEAD + TAIL`
   lines, **cut by lines** (4.2.7). Done.
3. Otherwise run **timestamp runs**, **stack frames**, **passing tests** and
   **long lines** (4.2.3 to 4.2.6) over the whole text, in that order. If the
   result is still longer than `MAX` bytes, **cut by bytes** (4.2.8).

Each step works on the result of the one before. Marker lines added by one
step are ordinary lines to the steps after it.

**View commands.** For `Bash` and `PowerShell`, when `tool_input.command`,
after skipping leading whitespace, leading `NAME=value` words and a leading
`sudo`, starts with a word that, ASCII lower-cased, is `cat`, `head`,
`tail`, `sed`, `nl`, `less`, `more`, `bat`, `batcat`, `diff`, `jq`, `xxd`,
`od`, `get-content`, `gc` or `type`, or with `git show`, `git diff` or
`git cat-file`, and the command contains no `|`, the caller asked to see that
text as it is: nothing above applies, and a slot longer than
`MAX + floor(MAX / 2)` bytes is cut by lines when it has more than
`HEAD + TAIL` lines, else by bytes, with no other change. Cutting a view is
safe for edits: Claude Code only edits a file after reading it with `Read`,
which is never trimmed.

#### 4.2.1 Clean

1. Remove every match of `\x1b\[[0-9;?]*[ -/]*[@-~]` and of
   `\x1b\][^\x07\x1b\n]*(\x07|\x1b\\)`.
2. For each line: if it ends in `\r`, set that `\r` aside. If what remains
   still contains `\r`, keep only the part after its last `\r` (a terminal
   would have drawn over the rest). Remove trailing spaces and tabs. Put the
   set-aside `\r` back.
3. Replace every run of three or more `\n` bytes with two.

#### 4.2.2 Exact repeats

A run of 3 or more consecutive identical lines that are not empty becomes the
first line followed by `[skinflint: line above repeated N more times]`,
where N is the run length minus 1.

#### 4.2.3 Timestamp runs

A line's *timestamp key* is what follows a leading timestamp. A leading
timestamp is an optional `[`, then
`[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}` or
`[0-9]{2}:[0-9]{2}:[0-9]{2}`, then optionally `[.,][0-9]+`, then optionally
`Z` or `[+-][0-9]{2}:?[0-9]{2}`, then an optional `]`, then any spaces or
tabs; each optional part is taken whenever it is present. A run of 3 or more
consecutive lines that all have a timestamp and equal, non-empty keys becomes:
the first line, `[skinflint: N more lines like this, differing only in
timestamp]`, the last line. N is the run length minus 2.

#### 4.2.4 Stack frames

A *frame* is one of:
- a line matching `^[ \t]+at [^ \t]`;
- a line matching `^[ \t]*#[0-9]+[ \t]`;
- a line matching `^[ \t]+File "[^"]*", line [0-9]+`, together with the line
  after it if that line starts with 4 spaces and is not itself a frame line
  of any of the three kinds.

A run of 8 or more consecutive frames keeps its first 3 and last 2 frames,
with `[skinflint: N stack frames omitted]` between them.

#### 4.2.5 Passing tests

A *pass line* matches one of `^(ok|PASS|PASSED)([ \t:]|$)`,
`[ \t](ok|PASS|PASSED)$`, `^[ \t]*(PASS|PASSED)[ \t]`, or contains U+2713
CHECK MARK, and is not an *error line* (4.3). A run of 10 or more
consecutive pass lines becomes the first, `[skinflint: N more passing
lines]`, the last. N is the run length minus 2.

#### 4.2.6 Long lines

A line longer than 4096 bytes keeps its first 2048 and last 512 bytes, with
` [skinflint: N bytes cut from this line] ` (with those surrounding spaces)
between them.

#### 4.2.7 Cut by lines

The original slot is saved to a spill file (4.4). With N the number of lines,
A = HEAD + 1 and B = N - TAIL: the *head block* is lines 1 to HEAD, the *tail
block* lines B + 1 to N, and lines A to B are cut. Unless this is a view
command, 4.2.3 to 4.2.6 are applied to the head block and to the tail block,
each on its own. The output is the head block, one marker line, the rescued
lines of 4.3, the tail block. The marker is
`[skinflint: cut lines A-B of N` + RESCUE + `.` + SAVED + `]`.

#### 4.2.8 Cut by bytes

The original slot is saved to a spill file (4.4). The output is the first
`floor(MAX / 2)` bytes, then
`\n[skinflint: cut K bytes from the middle.` + SAVED + `]\n`, then the last
`floor(MAX / 2)` bytes. K is the number of bytes removed.

RESCUE and SAVED:
- RESCUE is empty when the cut lines hold no error line. Otherwise it is
  `; kept S error line below, with 1 line of context` (`lines` when S is
  not 1), followed by `; the full text has more` when there are more than 12.
- SAVED is ` Full text: PATH (search it rather than re-running)` when the
  spill was written, ` Full text not saved: it looks like it holds a
  credential` when 4.4 refused it for that reason, and empty otherwise.

### 4.3 Error lines and rescue

An *error line* matches, after ASCII lower-casing, the word-bounded
(`(^|[^a-z0-9_])` ... `([^a-z0-9_]|$)`) alternation `error|errors|err|fail|
failed|failure|failures|failing|fatal|exception|traceback|panic|denied|
refused|timeout|timed out|assert|assertion|assertionerror|segfault|
segmentation fault|abort|aborted|critical|warning|warnings|undefined
reference|cannot|can't|not found|no such file|unable to|unexpected`, and
does not match any of these, which report an absence of errors:
`(^|[^0-9])0 (errors?|failed|failures?|warnings?)`,
`no (errors|failures|warnings)`,
`(errors?|failures?|failed|warnings?)[ \t]*[:=][ \t]*0([^0-9]|$)`.

Rescue, over the cut lines only: the first 12 error lines, S in all, are kept,
each with the line before and after it when those are also in the cut.
Overlapping or adjacent groups merge. Between two groups that are not
adjacent, a line `[...]` is inserted. A kept line longer than 300 bytes keeps
its first 300 bytes plus `...`.

### 4.4 Spill

The spill file is written unless `SKINFLINT_SPILL=0`, the payload has no
usable `tool_use_id` (non-empty after sanitising), or the original slot
matches any of the patterns below, which look like credentials. The file
holds the original slot bytes exactly. PATH is the absolute path of the
file, with the platform's separator.

- `-----BEGIN [A-Z ]*PRIVATE KEY-----`
- `AKIA[0-9A-Z]{16}`
- `gh[pousr]_[A-Za-z0-9]{36}`, `github_pat_[A-Za-z0-9_]{22}`
- `xox[abprs]-[A-Za-z0-9-]{10}`
- `sk-[A-Za-z0-9_-]{20}`
- after ASCII lower-casing:
  `(password|passwd|secret|token|api[_-]?key)["']?[ \t]*[:=][ \t]*["']?[^ \t"']{8}`
  and `authorization:[ \t]*bearer[ \t]+[^ \t]{16}`

### 4.5 Dedup

Runs before 4.2, unless `SKINFLINT_DEDUP=0`, the session has no valid
`<sid>`, or the payload has no usable `tool_use_id`. The *unit* is all slots
joined with the single byte 0x1E. When the unit is from 2048 to 1048576
bytes:

- if `<sid>.<tool>.last` holds a different `tool_use_id` and exactly this
  unit, the output is a duplicate. Slot 1 becomes
  `[skinflint: same output as the previous TOOL call (B bytes, N lines).
  It starts:]` followed by `\n` and the unit's first 5 lines (each cut as in
  4.3), and every other slot becomes empty;
- the file is then rewritten with this `tool_use_id` and this unit.

A duplicate skips 4.2 entirely; otherwise each slot goes through 4.2.

### 4.6 Result

The change is kept only if the total bytes saved across all slots are at
least 64. Then the hook prints

    {"hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":R}}

where R is the response rebuilt: a string response is re-encoded; an object
or array is written with the same members and elements in the same order,
every rewritten slot re-encoded, and every other value copied as its exact
original JSON text. Keys are re-encoded. In `STATE/stats`, `saved` gains the
bytes saved and `events` gains 1.

## 5. The other hooks

### 5.1 SessionStart

Mode `off`: no output. Otherwise, for every source, the reminder line
(section 6). This is where the rules reach the conversation: once when the
session starts, and again after `/clear` or a compaction, each of which
removes the earlier copy and fires this hook with that source. The full text
in `skills/skinflint/SKILL.md` is read only when the skill is invoked.

Printed as
`{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":X}}`.

### 5.2 UserPromptSubmit

The *command form* of `prompt`: lower-cased, trimmed, surrounding backticks
or quotes removed, one trailing `.` or `!` removed, runs of whitespace
turned into one space, and `skin flint` and `skin-flint` turned into
`skinflint`. The prompt is a switch only when the whole command form is
one of:

- off: `stop skinflint`, `skinflint off`, `skinflint mode off`,
  `/skinflint off`, `disable skinflint`, `turn off skinflint`,
  `deactivate skinflint`, `normal mode`
- on: `/skinflint`, `/skinflint on`, `skinflint on`, `skinflint mode`,
  `skinflint mode on`, `start skinflint`, `enable skinflint`,
  `turn on skinflint`, `activate skinflint`, `use skinflint`

A sentence that merely contains one of these is not a switch. A switch
writes `<sid>.mode`. Then: when the resulting mode is `off` and this prompt
switched it, the context is
`SKINFLINT OFF. Write normally until the user turns it back on.`; when this
prompt switched the mode `on`, the context is the reminder line (section 6),
because a session that started `off` has not seen the rules; when the mode
is `on` and the prompt is not a switch, the context is the one line
`SKINFLINT ON.`, which points back at the rules the session already holds;
otherwise there is no output. Printed as
`{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":X}}`.

### 5.3 SubagentStart

Mode `on`: the reminder line followed by
` You are a subagent: write your final report the same way.`, printed as
`{"hookSpecificOutput":{"hookEventName":"SubagentStart","additionalContext":X}}`.
Mode `off`: no output.

### 5.4 Stop

Never prints anything. Mode `on` and `last_assistant_message` a non-empty
string: in `STATE/stats`, `reply` gains the bytes of that string and
`replies` gains 1. The text itself is not kept.

## 6. Reminder line

`SKINFLINT ON.`, then ` Prose: answer first, then only what the user
needs to act; a question with one answer gets one or two sentences; for a
problem, the likely cause and its fix, not every possibility; for a comparison, the pick first, then at most three
one-sentence reasons; sentences, no headings or bullet lists (number steps
only when they run in order).` when `prose` is on, then ` Code: smallest
change that works, reuse before writing, nothing speculative; the code
first, then one line only if the user must change something to use it; no
alternatives, demos or tests unless asked; when asked to write or
show code, reply with it and create no file unless the user named one.` when
`code` is on, then
` Code, commit messages and security warnings stay in full sentences. Apply
these rules at once, without weighing them.`

## 7. Failure behaviour

A hook never exits non-zero and never writes to stderr unless
`SKINFLINT_DEBUG=1`. Unreadable input, a parse error, an unexpected shape,
an unwritable directory: the hook prints nothing (or only what it had fully
decided before the failure, never a partial JSON document) and exits 0.

## 8. Platforms

| | POSIX (Linux, macOS, BSD, WSL) | Windows |
|---|---|---|
| Runs | `sh` + `awk` from the hook line | `skinflint.exe`, compiled on first use with the .NET Framework `csc.exe` that ships with Windows, into `${CLAUDE_PLUGIN_DATA}` |
| From Git Bash | n/a | the hook line runs the exe directly |
| From PowerShell | n/a | the hook line loads the exe into the running PowerShell (no second process) |
| Path separator | `/` | `/` as well: every Windows file API accepts it, so printed paths read the same everywhere. `\` in inherited paths is turned into `/` |

## 9. Speed

On POSIX a hook runs one `sh` and one `awk` and nothing else, except
`mkdir` the first time the state directories are needed, `find` when
SessionStart prunes old sessions, and `ls` when the spill directory needs
pruning. On Windows a hook is one process when launched from Git Bash, and
no process beyond the shell Claude Code already started when launched from
PowerShell.
