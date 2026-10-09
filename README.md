<p align="center">
  <img src="https://raw.githubusercontent.com/SkYn3t-Lab/skinflint-tests/main/assets/skinflint-header.jpg" alt="Skinflint: a grey fox in spectacles and a patched coat inspecting a coin at a desk stacked with coins and jars" width="100%">
</p>

<p align="center">
  <b>Make Claude Code say more with fewer tokens.</b><br>
  Shorter answers, leaner code, trimmed tool output. Zero dependencies.
</p>

<p align="center">
  <img alt="Claude Code plugin" src="https://img.shields.io/badge/Claude%20Code-plugin-1FB5A8">
  <img alt="Dependencies: none" src="https://img.shields.io/badge/dependencies-none-2ea44f">
  <img alt="Linux, macOS, Windows" src="https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-0B0F14">
  <img alt="License: MIT" src="https://img.shields.io/badge/license-MIT-blue">
</p>

---

Every token Claude writes, and every line of tool output it reads, is paid for
again on each later turn. skinflint cuts the ones that carry nothing and
keeps every one that carries a fact.

<p align="center"><b>70% fewer output tokens and 40% lower cost on everyday questions &middot; 32% fewer output tokens and 24% lower cost on tool-using tasks &middot; the lowest of four plugins tested on both &middot; zero dependencies</b></p>

- **Tighter answers.** The answer first, the likely cause and its fix, no
  filler, no recap, no wall of headings and bullets.
- **Leaner code.** The smallest change that works: reuse, then the standard
  library, then the platform, before any new code or dependency.
- **Trimmed tool output.** Long command output is cleaned and cut before
  Claude reads it. Error lines from the cut part are kept, and the full text
  is saved to a file Claude can search instead of re-running the command.
- **Nothing to install.** Pure POSIX `sh` + `awk` on Linux, macOS and WSL; on
  Windows a small program built on first use with the compiler that ships
  with Windows. No Node, no Python, no package manager.
- **Faster than every other plugin measured.** On every hook, on Linux and on
  Windows from Git Bash, PowerShell 5.1 and PowerShell 7, skinflint's hooks
  finish first (see [Faster hooks](#faster-hooks)).
- **Tested to the byte.** One written [specification](SPEC.md), two
  implementations, 188 test cases that must produce identical bytes on both.

Same model, same question, one difference: skinflint. Both answers are
verbatim from the [benchmark run](https://github.com/SkYn3t-Lab/skinflint-tests/tree/main/benchmarks/results/2026-10-08-heldout/questions/runs),
the first repetition of each:

> What is the difference between git stash pop and git stash apply?

<table>
<tr><th align="left" width="50%">No plugin: 356 output tokens</th>
<th align="left" width="50%">skinflint: 87 output tokens</th></tr>
<tr valign="top"><td>

Both reapply stashed changes to your working tree; the difference is what happens to the stash entry afterward.

- **`git stash apply`** reapplies the changes and **keeps** the entry in the stash list. You can apply it again (e.g. on another branch) and must remove it yourself with `git stash drop` when done.
- **`git stash pop`** reapplies the changes and **removes** the entry from the stash list, as long as it applied cleanly. It is effectively `apply` followed by `drop`.

If `pop` hits a merge conflict, the stash is *not* dropped. After resolving the conflicts you need to run `git stash drop` manually.

Both default to the most recent stash (`stash@{0}`) and accept a specific one, e.g. `git stash apply stash@{2}`. Both also take `--index` to restore the staged/unstaged distinction, which is otherwise lost (everything comes back unstaged).

Use `pop` for the common "set aside, then resume" case, and `apply` when you want the same changes in more than one place or want a safety copy until you're sure the result is right.

</td><td>

`git stash apply` applies the stashed changes and leaves the entry in the stash list; `git stash pop` applies them and then drops the entry. If `pop` hits a conflict, the stash is kept, so you have to `git stash drop` it yourself after resolving.

</td></tr>
</table>

## What it trims

| | The waste | What skinflint does |
|---|---|---|
| **Prose** | Preambles, recaps, hedging, headings and bullet walls nobody asked for | A short paragraph of rules when the session starts, and a two-word marker with every prompt |
| **Code** | Abstractions with one user, boilerplate "for later", new dependencies for a few lines | A decision ladder: reuse, standard library, platform, installed dependency, then the least new code |
| **Tool output** | Build logs, test runs, stack traces and listings read into context and billed again every turn | Cleaned and cut before Claude reads it; errors kept; the full text saved to a file |

```mermaid
%%{init: {"flowchart": {"curve": "basis", "wrappingWidth": 320}}}%%
flowchart LR
    S(["Session start"]) -->|the rules, once| M(["Claude"])
    U(["Every prompt"]) -->|two-word marker| M
    A(["Every subagent"]) -->|same rules| M
    M -->|runs a tool| T[["Bash, PowerShell, Grep, Glob,<br/>web, MCP, subagents"]]
    T -->|raw output| C["skinflint:<br/>clean, fold, cut, save"]
    C -->|same shape, far smaller| M
    R["Read / Edit / Write"] -.->|never touched| M
    linkStyle default interpolate basis
    style M fill:#0B0F14,stroke:#1FE0C4,color:#e6edf3
    style C fill:#0B0F14,stroke:#E040FB,color:#e6edf3
    style R fill:#1f1f1f,stroke:#6e7681,color:#c9d1d9
```

Tool output is the part that compounds: every line read into the
conversation is sent again with each later request, so cutting it once pays
off on every turn after.

---

## Everything it does

### Answers and code

- **The rules once, a marker after.** A short paragraph of rules is added when
  the session starts, and again after `/clear` or a compaction, so it is never
  summarised away. Every prompt in between carries only `SKINFLINT ON.`, which
  points back at it. Measured over twenty prompts in one conversation, the
  answers were as short at the end as at the start (see
  [A long session](#a-long-session)). Nothing longer is added: in testing, a full ruleset at
  session start cost more as input than it saved. The full rules are in the
  `skinflint` skill.
- **Code first, one line after.** Code comes before any words about it,
  followed by one line only when you must change something to use it. No
  second version, no usage demo, no test file nobody asked for, and
  code you asked to see arrives in the reply rather than in a new file.
- **No narration between tool calls.** No "now I will..." before each command
  and no summary of a result it is about to act on.
- **Shortcuts you can find again.** A corner deliberately cut in the code gets
  a `skinflint:` comment naming its limit, and `/skinflint-debt` lists
  them all later.
- **Subagents follow the same rules.** Every subagent Claude starts is told to
  report back the same way.
- **On and off per session, or per project.** The mode belongs to the session
  and survives compaction; another session keeps its own. A project can turn
  it off, or drop the prose or code rules, with `.claude/skinflint.json`.
- **Switches that don't misfire.** Only a whole message such as
  `stop skinflint` switches it; "add a normal mode toggle" does not.
- **Plays well with output styles.** If you use a custom output style, the prose
  rules step aside for it. Prose and code rules can each be switched off.

### Tool output

Applied to Bash, PowerShell, Grep, Glob, WebFetch, WebSearch, subagent results
and every MCP tool:

| Noise | Becomes |
|---|---|
| Colour codes, trailing spaces, blank-line runs | removed |
| Progress bars redrawn with `\r` | only the final state |
| The same line repeated | one line + "repeated N more times" |
| Log lines that differ only in their timestamp | first, a count, last |
| 40-frame stack traces (JavaScript, Java, C#, Python, gdb) | first 3 and last 2 frames |
| Hundreds of passing tests (Jest, Go, pytest, TAP, "PASS") | first, a count, last; failures always kept |
| A 500 KB line of minified JSON | its head and tail |
| Windows UTF-16 output (a NUL after every letter) | plain text |
| Still over 8 KB | first 60 and last 40 lines, plus the first 12 error lines from the middle with one line of context each |
| The exact same output as last time | a one-line note and its first lines |

- **Nothing is lost.** Whenever lines are cut, the full text is saved to a file
  and the note tells Claude where, so it searches the file instead of running
  the command again.
- **Knows an error from a success.** "0 errors", "no failures" and
  "errors: 0" are not treated as errors; "terror" and "errorless" are not
  either.
- **Secrets stay off disk.** Output that looks like it holds a private key, an
  API key, a token or a password is never saved to a file.
- **Leaves alone what must stay exact.** Read, Edit and Write are never
  touched. `cat`, `head`, `git diff`, `Get-Content` and similar commands are
  kept whole up to 12 KB, because Claude asked to see that text; beyond that
  only their head and tail are kept, with the full text saved. Claude Code
  edits a file only after reading it with Read, so this never changes what an
  edit is based on. Failed commands and output Claude Code already saved to
  disk pass through unchanged.
- **Keeps the tool's own shape.** Only the text fields change; every other
  field of the result is passed on byte for byte. Cuts never split a UTF-8
  character.
- **Cleans up after itself.** The newest 40 saved outputs are kept, and session
  state older than a week is removed.

### Everywhere, with nothing to install

- **Linux, macOS, WSL:** POSIX `sh` + `awk`. Tested with mawk, gawk, BWK awk
  (macOS) and busybox awk, under dash, bash and busybox `sh`.
- **Windows:** a small program compiled on first use by the C# compiler that
  ships with Windows. Works from Git Bash, Windows PowerShell 5.1 and
  PowerShell 7, and PowerShell's script execution policy does not matter.
- **No network access**, ever. No telemetry, no update check.
- **Private state.** Everything it writes lives in `~/.claude/skinflint/`,
  readable only by you.

### Extras

- `/skinflint-stats` shows everything saved so far: tool output trimmed, the
  estimated saving on replies, and what the plugin itself adds, with the net.
- `/skinflint-debt` lists every shortcut marked with a `skinflint:`
  comment, with when it would be worth doing properly.
- `/skinflint-review` reviews your diff for code that can be deleted.
- `/skinflint-audit` ranks everything removable in a file, diff or repo, code
  and prose, biggest first.
- A status line showing the mode and roughly how many tokens have been saved,
  net of what the plugin adds.

### Seeing what it saves

The hooks keep five counters in one small file, and `/skinflint-stats` turns
them into four figures:

| Figure | Where it comes from |
|---|---|
| Tool output trimmed | Measured: the bytes removed from tool results, and how many results were shortened |
| Replies | Estimated: the bytes of the replies Claude actually wrote, times 44/56 |
| Cost of the plugin | Measured: the bytes of rules and reminders skinflint itself added to your conversations |
| Net | The first two minus the third |

Only the reply figure is an estimate. The benchmark below ran the same
tool-using tasks with and without the plugin, and with it Claude's final
replies were 56% of the size; in
your own sessions each prompt is answered once, with the plugin on, so there
is no second reply to compare, and that measured ratio is applied to what was
written. The plugin counts the length of each final reply and keeps none of
its text.

The net can be small or negative in a short session, because the rules are
added at its start whatever the replies come to. Bytes also understate the
money side: trimmed tool output and the plugin's own text are input, while
replies are output, which costs five times as much per token on every current
Claude model. So `/skinflint-stats` also gives the net in dollars, with the
reply figure counted five times, at the API price of Claude Opus 5.5 ($4 per
million input tokens, $20 per million output tokens). It is a floor: text
that stays in the conversation is sent again with each later request, and
that repeat is not counted.

## How it compares

Measured in the benchmarks below, or read from each plugin's own code:

| | skinflint | [chisle](https://github.com/JayPokale/Chisle) | [ponytail](https://github.com/dietrichgebert/ponytail) | [caveman](https://github.com/JuliusBrussee/caveman) |
|---|---|---|---|---|
| Questions: output tokens (% of no plugin) | **30%** | 85% | 64% | 78% |
| Questions: cost (% of no plugin) | **60%** | 101% | 86% | 98% |
| Questions: worst single one (% of no plugin) | **85%** | 170% | 220% | 111% |
| Questions: answers graded correct (no plugin 58/60) | 60/60 | 58/60 | 56/60 | 58/60 |
| Tool-using tasks: output tokens (% of no plugin) | **68%** | 89% | 97% | 87% |
| Tool-using tasks: cost (% of no plugin) | **76%** | 86% | 102% | 92% |
| Tool-using tasks: checks passed | 24/24 | 24/24 | 24/24 | 24/24 |
| Trims tool output | **yes, 4.2%** | yes, 4.0% | no | no |
| Needs a runtime | **no** | Node.js | Node.js | Node.js |
| Prompt hook, Linux / Windows Git Bash | **7 ms / 79 ms** | 38 ms / 102 ms | 38 ms / 92 ms | 44 ms / 146 ms |
| Works on Windows without Git Bash | **yes** | yes | yes | no, its hooks fail under PowerShell |
| Trims PowerShell tool output (Windows' default shell tool) | **yes** | no | no tool-output trimming | no tool-output trimming |
| Steers subagents | **yes** | no | yes | no |
| Keeps secrets out of saved output | **yes** | no | saves no output | saves no output |
| Network calls | **none** | an update check | none | none |

## Install

You need Claude Code and nothing else. Install once per computer.

**1. Open a terminal** (Terminal on macOS and Linux, PowerShell or Git Bash on
Windows). Run these two commands there, not inside a Claude Code session:

```sh
claude plugin marketplace add SkYn3t-Lab/skinflint
claude plugin install skinflint@skinflint
```

- The first command tells Claude Code where to find the plugin: this GitHub
  repository. Claude Code calls such a source a *marketplace*. It prints
  `Successfully added marketplace: skinflint`.
- The second installs the plugin for your user, in every project. The name
  reads *plugin*@*marketplace*; here both are called `skinflint`.

**2. Start a new Claude Code session.** A session that was already open picks
the plugin up after you type `/reload-plugins` in it.

**3. Check it works.** In the session, type `/skinflint-help`: it lists the
commands below. From a terminal, `claude plugin list` includes
`skinflint@skinflint`. On Windows the very first hook builds a small helper
program, which takes under a second and happens once.

If you use another plugin that does the same job, uninstall it first, or
everything is trimmed twice.

**Prefer to stay inside Claude Code?** Type the same two steps as slash
commands. The second opens a panel: choose *Install for you*.

```text
/plugin marketplace add SkYn3t-Lab/skinflint
/plugin install skinflint@skinflint
```

**If adding the marketplace fails**, git on your computer cannot reach the
repository. Claude Code clones it with your normal git setup, so sign in to
GitHub the way you usually do (for example `gh auth login`) and run the
command again.

### Update

```sh
claude plugin marketplace update skinflint
claude plugin update skinflint@skinflint
```

The first fetches the latest version from GitHub, the second installs it.
Start a new session (or `/reload-plugins`) to use it.

### Remove

```sh
claude plugin uninstall skinflint@skinflint
claude plugin marketplace remove skinflint
```

The first removes the plugin; the second removes the marketplace entry as
well. Either one alone switches skinflint off.

## Use

| Say or type | What happens |
|---|---|
| `/skinflint`, `skinflint on` | Turn it on for this session |
| `stop skinflint`, `normal mode`, `/skinflint off` | Turn it off for this session |
| `/skinflint-stats` | Everything saved so far: tool output, replies (estimated) and the plugin's own cost |
| `/skinflint-debt` | List every shortcut marked with a `skinflint:` comment |
| `/skinflint-review` | Review the current diff for code that can be removed |
| `/skinflint-audit [path]` | Rank everything removable, code and prose, biggest first |
| `/skinflint-help` | Show this list |

A switch works only as the whole message: "add a normal mode toggle" does not
turn anything off. The mode belongs to the session and survives compaction.

## Settings

Environment variables, in `settings.json` under `env` or in your shell:

| Variable | Effect |
|---|---|
| `SKINFLINT_DEFAULT_MODE=off` | Sessions start off; turn it on per session |
| `SKINFLINT_COMPRESS=0` | Leave tool output alone |
| `SKINFLINT_DEDUP=0` | Do not replace repeated output |
| `SKINFLINT_SPILL=0` | Do not save full text to disk |
| `SKINFLINT_TOOLS=Bash,Grep` | Only these tools |
| `SKINFLINT_MAX_BYTES` | Size before lines are cut (default 8000) |
| `SKINFLINT_HEAD_LINES`, `SKINFLINT_TAIL_LINES` | Lines kept at each end (60, 40) |

A config file does the same for the mode and for which parts of the rules load:
`~/.config/skinflint/config.json` (`%APPDATA%\skinflint\config.json` on
Windows):

```json
{ "defaultMode": "on", "sections": { "prose": true, "code": true } }
```

A project can override any of these keys in `.claude/skinflint.json` at its
root, for example `{ "defaultMode": "off" }` to keep skinflint out of one
repository. The environment variable still wins over both files, and a switch
typed in a session wins over everything for that session.

If you use a custom output style, the prose rules step aside for it.

**Status line** (optional): `sh "<plugin>/hooks/statusline.sh"`, or on Windows
`powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin>\hooks\win\statusline.ps1"`.
It shows the mode and roughly how many tokens have been saved, net of what the
plugin adds; the saving on replies in that figure is an estimate.

State lives in `~/.claude/skinflint/`: per-session mode, the last output of
each tool for the duplicate check, saved full texts (the newest 40 are kept)
and a running total.

## Numbers

The benchmark figures in this section come from one run on 2026-10-08:
skinflint 0.5.0,
[chisle](https://github.com/JayPokale/Chisle) at commit `c200401`, [ponytail](https://github.com/dietrichgebert/ponytail) at `c982cd4` and [caveman](https://github.com/JuliusBrussee/caveman) at
`6571943`, each loaded as a real plugin through `claude -p` on Claude Opus
5.5, three times per task. Every run happens in a throwaway configuration that
holds nothing but the login, inside a sandbox in which the home directory is
empty, so the plugin is the only difference between two runs of a task. None
of the 465 runs ended in an error, and the transcripts of the 165 tool-using
runs confirm that each plugin's hooks loaded in every one of its runs.

Three repetitions leave noise: one skinflint version measured 85% of
no-plugin cost on the tool-using tasks one day and 72% the next, and this one
76%. Read a single figure as good to about ten points. skinflint was the
lowest of the four in every run.

### Everyday questions

Twenty developer requests, five each of short and long coding tasks and short
and long explanations. skinflint's rules were adjusted against an earlier set
of twenty; these twenty were written afterwards and run once, so no figure
here comes from a question the rules were tuned on. A separate judge, which sees only the question and the
answer and never which plugin wrote it, graded every answer for correctness.

<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/SkYn3t-Lab/skinflint-tests/main/assets/charts/output-overall-dark.png">
  <img src="https://raw.githubusercontent.com/SkYn3t-Lab/skinflint-tests/main/assets/charts/output-overall-light.png" width="720" alt="Output tokens as a share of no plugin: skinflint 30%, chisle 85%, ponytail 64%, caveman 78%">
</picture></p>

| Plugin | Output tokens, all questions | Cost | Average question | Worst question | Questions longer than no plugin | Answers graded correct |
|---|--:|--:|--:|--:|--:|--:|
| **skinflint** | **30%** | **60%** | **30%** | **85% (pagination)** | **0** | 60/60 |
| [chisle](https://github.com/JayPokale/Chisle) | 85% | 101% | 103% | 170% (throttle) | 9 | 58/60 |
| [ponytail](https://github.com/dietrichgebert/ponytail) | 64% | 86% | 86% | 220% (nullcheck) | 5 | 56/60 |
| [caveman](https://github.com/JuliusBrussee/caveman) | 78% | 98% | 65% | 111% (pagination) | 1 | 58/60 |
| no plugin | 100% | 100% | 100% | 100% | 0 | 58/60 |

Output tokens and cost are a share of what the same model wrote and cost with
no plugin, so lower is better. Cost is what Claude Code reported for each run
at list price, so it includes the text each plugin adds to the conversation.
skinflint is shortest overall and in every kind of question, has the best
worst case, and no question came out longer than without it. The judge passed
all 60 of its answers, against 58 with no plugin, 58 each for chisle and
caveman and 56 for ponytail.

<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/SkYn3t-Lab/skinflint-tests/main/assets/charts/output-by-kind-dark.png">
  <img src="https://raw.githubusercontent.com/SkYn3t-Lab/skinflint-tests/main/assets/charts/output-by-kind-light.png" width="720" alt="Output tokens by kind of question for each plugin">
</picture></p>

| Kind of question | skinflint | [chisle](https://github.com/JayPokale/Chisle) | [ponytail](https://github.com/dietrichgebert/ponytail) | [caveman](https://github.com/JuliusBrussee/caveman) |
|---|--:|--:|--:|--:|
| Coding, short | **19%** | 123% | 73% | 56% |
| Coding, long | **28%** | 79% | 52% | 81% |
| Explaining, short | **20%** | 88% | 81% | 41% |
| Explaining, long | **47%** | 99% | 97% | 83% |

<details>
<summary>Every question (skinflint shortest on 19 of 20)</summary>

| Question | Kind | No plugin, tokens | skinflint | chisle | ponytail | caveman |
|---|---|--:|--:|--:|--:|--:|
| `throttle` | coding, short | 449 | **28** | 170 | 101 | 90 |
| `flatten` | coding, short | 197 | **12** | 111 | 37 | 46 |
| `timeout` | coding, short | 483 | **13** | 64 | 33 | 16 |
| `nullcheck` | coding, short | 132 | **19** | 147 | 220 | 62 |
| `slugify` | coding, short | 293 | **18** | 143 | 55 | 75 |
| `lru` | coding, long | 3407 | **12** | 79 | 74 | 39 |
| `pagination` | coding, long | 2317 | **85** | 141 | 124 | 111 |
| `parser` | coding, long | 16436 | 18 | 64 | **11** | 81 |
| `logrotate` | coding, long | 6053 | **34** | 94 | 95 | 84 |
| `queue` | coding, long | 4194 | **35** | 87 | 95 | 95 |
| `lookahead` | explain, short | 616 | **18** | 77 | 73 | 26 |
| `indexes` | explain, short | 889 | **15** | 80 | 74 | 30 |
| `gitstash` | explain, short | 321 | **25** | 116 | 71 | 42 |
| `cors` | explain, short | 847 | **28** | 98 | 89 | 56 |
| `racecond` | explain, short | 761 | **19** | 85 | 89 | 48 |
| `sqlnosql` | explain, long | 1001 | **20** | 107 | 105 | 81 |
| `outage` | explain, long | 2369 | **57** | 93 | 90 | 86 |
| `microfront` | explain, long | 1302 | **44** | 103 | 98 | 72 |
| `authdesign` | explain, long | 2401 | **56** | 101 | 101 | 89 |
| `memleak` | explain, long | 1768 | **40** | 98 | 94 | 80 |

Figures are % of no plugin, the lowest in bold. Every prompt is in
[`benchmarks/tasks-heldout.tsv`](https://github.com/SkYn3t-Lab/skinflint-tests/blob/main/benchmarks/tasks-heldout.tsv) and every answer with its grade
in [`benchmarks/results/2026-10-08-heldout/questions/`](https://github.com/SkYn3t-Lab/skinflint-tests/tree/main/benchmarks/results/2026-10-08-heldout/questions).

</details>

### Tool-using tasks

Questions show what a plugin does to an answer. Most Claude Code work is not
that: Claude reads files, runs commands and edits code over several turns, and
there a plugin's own text is paid for again on every one of them. So the same
plugins were run on eight tasks in a small generated project, each with one
planted problem (a failing test, an outage in a log, a script to extend, a
convention to enforce) and a check that runs or reads what Claude left behind
and passes or fails it.

| Plugin | Cost | Output tokens | Input tokens | Turns | Final reply size | Checks passed |
|---|--:|--:|--:|--:|--:|--:|
| **skinflint** | **76%** | **68%** | **87%** | **84%** | **56%** | 24/24 |
| [chisle](https://github.com/JayPokale/Chisle) | 86% | 89% | 103% | 84% | 80% | 24/24 |
| [ponytail](https://github.com/dietrichgebert/ponytail) | 102% | 97% | 115% | 84% | 102% | 24/24 |
| [caveman](https://github.com/JuliusBrussee/caveman) | 92% | 87% | 109% | 92% | 73% | 24/24 |
| no plugin | 100% | 100% | 100% | 100% | 100% | 24/24 |

Every plugin got every task right, so the difference is what it cost to get
there. skinflint is the only one of the four that lowers input
tokens: the others add several thousand bytes of rules to every session,
which is sent again with each request, while skinflint adds one short
paragraph per session.

<details>
<summary>Every task, cost as % of no plugin</summary>

| Task | What Claude was asked | No plugin, cost | skinflint | chisle | ponytail | caveman |
|---|---|--:|--:|--:|--:|--:|
| `bugfix` | The tests are failing. Find out why and fix it. | $0.10 | **91** | 111 | 124 | 111 |
| `logs` | The api went down last night. Look at logs/service.log and tell me what happened. | $0.20 | **71** | 72 | 111 | 77 |
| `dryrun` | Add a --dry-run option to scripts/backup.sh that shows what it would copy without copying anything, and update the README to match. | $0.14 | **64** | 85 | 95 | 100 |
| `compose` | Does docker-compose.yml follow our conventions? Fix whatever does not. | $0.12 | **81** | 82 | 91 | 84 |
| `mail` | Which scripts send mail without going through the shared helper? Fix them. | $0.11 | **87** | 98 | 106 | 100 |
| `bump` | Bump the version to 1.4.0 everywhere. The change is a new --json flag on the low-stock report. | $0.11 | **86** | 95 | 103 | 96 |
| `disk` | What is using the space under data/ ? | $0.08 | **68** | 75 | 84 | 87 |
| `review` | Review app/inventory.py and tell me what is wrong with it. Do not change any file. | $0.10 | **68** | 86 | 96 | 91 |

The lowest is in bold. The project generator, the prompts and the checks are in
[`benchmarks/agentic/`](https://github.com/SkYn3t-Lab/skinflint-tests/blob/main/benchmarks/agentic), and every run with its verdict in
[`benchmarks/results/2026-10-08-heldout/agentic/`](https://github.com/SkYn3t-Lab/skinflint-tests/tree/main/benchmarks/results/2026-10-08-heldout/agentic).

</details>

### A long session

The runs above are one prompt each. skinflint sends its rules once, when the
session starts, and only two words with each prompt after that, so the same
twenty questions were also asked one after another in a single conversation,
in both orders, twice per plugin, to see whether the rules still hold late.

| Plugin | Prompts 1-5 | 6-10 | 11-15 | 16-20 | Whole session | Cost |
|---|--:|--:|--:|--:|--:|--:|
| **skinflint** | **48%** | **42%** | **57%** | **52%** | **50%** | **56%** |
| [chisle](https://github.com/JayPokale/Chisle) | 90% | 80% | 80% | 87% | 83% | 86% |
| [ponytail](https://github.com/dietrichgebert/ponytail) | 93% | 88% | 95% | 106% | 94% | 96% |
| [caveman](https://github.com/JuliusBrussee/caveman) | 86% | 85% | 88% | 90% | 87% | 92% |
| no plugin | 100% | 100% | 100% | 100% | 100% | 100% |

Output tokens and cost as a share of no plugin. skinflint is as short at the
end of the session as at the start. The runner and every session are in
[`benchmarks/multiturn/`](https://github.com/SkYn3t-Lab/skinflint-tests/blob/main/benchmarks/multiturn) and
[`benchmarks/results/2026-10-08-heldout/multiturn/`](https://github.com/SkYn3t-Lab/skinflint-tests/tree/main/benchmarks/results/2026-10-08-heldout/multiturn).

### Less tool output

Output-token rules only shape what Claude writes; tool output is what it reads,
and every line of it is sent again with each later request. To measure that
part (on 2026-09-30; the trimming code has not changed since), 7,677 real tool results from 627 of the author's own Claude Code sessions
were replayed through each plugin's PostToolUse hook, in session order, exactly
as Claude Code would have sent them:

| Plugin | Tool output removed | Results shortened |
|---|--:|--:|
| **skinflint** | **4.2%** | **97** |
| [chisle](https://github.com/JayPokale/Chisle) | 4.0% | 84 |
| [ponytail](https://github.com/dietrichgebert/ponytail) | 0% (no tool-output hook) | 0 |
| [caveman](https://github.com/JuliusBrussee/caveman) | 0% (no tool-output hook) | 0 |

Most tool results are short and pass through untouched; the saving comes from
the 97 long ones skinflint shortened. Results Claude Code had already saved
to a file (21 of them) are left out for both, since Claude only ever saw a
short preview of those.

### What it saves in dollars

The cost columns above are the answer, measured and not extrapolated: Claude
Code reports what each run cost at list price, and with skinflint the same
work cost 76% of the no-plugin price on tool-using tasks and 60% on
questions. On $100 of Claude Code use that is roughly $24 to $40
kept, depending on how much of the work is tools and how much is answers.
Trimmed tool output adds to that in long sessions, where every line read is
sent again on each later turn; the benchmark tasks are too short to show it.

The benchmark scripts and their results live in their own repository,
[skinflint-tests](https://github.com/SkYn3t-Lab/skinflint-tests), so that installing the plugin does not download them.
Reproduce everything from a clone of it with
`ARMS="none:- skinflint:<dir> ..." bash benchmarks/run-arms-sandboxed.sh OUTDIR 3 claude-opus-5-5`,
`bash benchmarks/grade.sh OUTDIR GRADES.json`,
`python3 benchmarks/analyze-arms.py OUTDIR GRADES.json`,
`ARMS="none:- skinflint:<dir> ..." bash benchmarks/agentic/run-agentic.sh OUTDIR 3 claude-opus-5-5`,
`python3 benchmarks/agentic/analyze-agentic.py OUTDIR`
and, for tool output,
`python3 benchmarks/replay.py --arm skinflint='sh <dir>/hooks/run.sh compress' ~/.claude/projects --out R.json`.
The data behind every benchmark number here is in
[`benchmarks/results/2026-10-08-heldout/`](https://github.com/SkYn3t-Lab/skinflint-tests/tree/main/benchmarks/results/2026-10-08-heldout),
the hook timings in
[`benchmarks/results/2026-10-05/`](https://github.com/SkYn3t-Lab/skinflint-tests/tree/main/benchmarks/results/2026-10-05);
the replay is in
[`benchmarks/results/2026-09-30/`](https://github.com/SkYn3t-Lab/skinflint-tests/tree/main/benchmarks/results/2026-09-30).

### Faster hooks

Every hook Claude Code runs costs time on every prompt, tool call and session
start. Each plugin's own hook commands were timed the way Claude Code runs
them, as medians of 41 interleaved rounds so that load on the machine falls on
every plugin alike, on 2026-10-05, with [`benchmarks/speed.py`](https://github.com/SkYn3t-Lab/skinflint-tests/blob/main/benchmarks/speed.py) on Linux
and [`benchmarks/speed.ps1`](https://github.com/SkYn3t-Lab/skinflint-tests/blob/main/benchmarks/speed.ps1) on Windows 11. The three plugins that need Node.js ran on the current
long-term-support release, 22.23.3, from nodejs.org; an older Node.js starts
more slowly and would add to their times.

<p align="center"><picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/SkYn3t-Lab/skinflint-tests/main/assets/charts/speed-dark.png">
  <img src="https://raw.githubusercontent.com/SkYn3t-Lab/skinflint-tests/main/assets/charts/speed-light.png" width="720" alt="Hook time on every prompt for each plugin, on Linux and three Windows shells">
</picture></p>

| Linux, ms | startup | prompt | subagent | 30 KB log | 150 KB log | 150 KB JSON |
|---|--:|--:|--:|--:|--:|--:|
| **skinflint** | **10** | **7** | **7** | **10** | **12** | **14** |
| [chisle](https://github.com/JayPokale/Chisle) | 134 | 38 | no hook | 57 | 58 | 60 |
| [ponytail](https://github.com/dietrichgebert/ponytail) | 37 | 38 | 32 | no hook | no hook | no hook |
| [caveman](https://github.com/JuliusBrussee/caveman) | 43 | 44 | no hook | no hook | no hook | no hook |

| Windows 11, ms | startup | prompt | subagent | small output | 3000 lines | 30 KB log |
|---|--:|--:|--:|--:|--:|--:|
| **skinflint**, Git Bash | **80** | **79** | **81** | **82** | **102** | **106** |
| [chisle](https://github.com/JayPokale/Chisle), Git Bash | 197 | 102 | no hook | 103 | 138 | 134 |
| [ponytail](https://github.com/dietrichgebert/ponytail), Git Bash | 94 | 92 | 88 | no hook | no hook | no hook |
| [caveman](https://github.com/JuliusBrussee/caveman), Git Bash | 145 | 146 | no hook | no hook | no hook | no hook |
| **skinflint**, PowerShell 5.1 | **183** | **182** | **189** | **187** | **216** | **220** |
| [chisle](https://github.com/JayPokale/Chisle), PowerShell 5.1 | 303 | 209 | no hook | 211 | 248 | 245 |
| [ponytail](https://github.com/dietrichgebert/ponytail), PowerShell 5.1 | 210 | 212 | 208 | no hook | no hook | no hook |
| [caveman](https://github.com/JuliusBrussee/caveman), PowerShell 5.1 | fails | fails | no hook | no hook | no hook | no hook |
| **skinflint**, PowerShell 7 | **286** | **288** | **305** | **292** | **334** | **338** |
| [chisle](https://github.com/JayPokale/Chisle), PowerShell 7 | 411 | 319 | no hook | 316 | 363 | 361 |
| [ponytail](https://github.com/dietrichgebert/ponytail), PowerShell 7 | 310 | 312 | 315 | no hook | no hook | no hook |
| [caveman](https://github.com/JuliusBrussee/caveman), PowerShell 7 | fails | fails | no hook | no hook | no hook | no hook |

The fastest time in each column and shell is in bold. "no hook" means the
plugin does not run anything at that point (ponytail and caveman do not trim
tool output at all). caveman's hook commands are written in shell syntax, so
they fail under PowerShell, which Claude Code uses on Windows when Git Bash is
not installed. ponytail's prompt and subagent hooks print nothing on an ordinary
prompt: they only report mode changes. skinflint needs no runtime: on Linux a hook is one
`sh` and one `awk`; on Windows, Git Bash runs the compiled program directly,
and PowerShell loads it into the PowerShell that is already running, so no
second process starts.

## How one hook line runs everywhere

Claude Code runs a plugin's hook command with `sh` on Linux and macOS, with Git
Bash on Windows, and with PowerShell on Windows without Git Bash. Each hook is
one command that reads correctly in both languages: `sh` sees a no-op group
and then `exec`s the right program, so it never reads further; PowerShell
sees the `sh` lines inside a block comment and runs the lines after it.
`tools/stamp.sh` writes these lines into `.claude-plugin/plugin.json`, and embeds
the awk program (`hooks/lib/skinflint.awk`) in `hooks/run.sh`, so that the POSIX
hook is one file that runs no other.

## Tests

The tests live in [skinflint-tests](https://github.com/SkYn3t-Lab/skinflint-tests). Clone it beside this repository and
run:

```sh
sh skinflint-tests/tests/golden.sh                                            # POSIX
powershell -ExecutionPolicy Bypass -File skinflint-tests\tests\golden.ps1     # Windows
```

Both test the plugin in `../skinflint`; set `PLUGIN_ROOT` to test another copy.
`tests/cases/` holds one case per behaviour in SPEC.md, each with its input,
expected output and expected files on disk. `golden.sh` runs every case through
the real hook line; `golden.ps1` runs it through the Windows program. Both pass
on dash, bash and busybox `sh`, with mawk, gawk, BWK awk and busybox awk, and on
Windows PowerShell 5.1 and PowerShell 7. `tests/make_cases.py` regenerates the
cases (the only part that needs Python).

## License

MIT. See [LICENSE](LICENSE). What skinflint reads and keeps is in
[PRIVACY.md](PRIVACY.md); the terms of use are in [TERMS.md](TERMS.md).
