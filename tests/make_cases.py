#!/usr/bin/env python3
"""Write the test cases in tests/cases/, one directory per case.

Maintainer tool: the cases themselves are plain files, so the runners
(golden.sh, golden.ps1) need no Python. Each case directory holds
  hook        activate | prompt | subagent | compress
  input.json  the hook payload, exact bytes
  env         optional, KEY=VALUE lines
  setup/      optional files placed in the sandbox first:
                cfg/   is CLAUDE_CONFIG_DIR
                xdg/   is XDG_CONFIG_HOME (the config file lives in xdg/token-miser/)
                work/  is the working directory
Expected output ("expected") and end state ("state") are recorded by
golden.sh --record and then must hold for both implementations.
Every case is named after the SPEC.md section it exercises.
"""
import json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'cases')
cases = []


def case(name, hook, payload, env=None, setup=None):
    raw = payload if isinstance(payload, (bytes, str)) else json.dumps(payload, ensure_ascii=False, separators=(',', ':'))
    if isinstance(raw, str):
        raw = raw.encode('utf-8')
    cases.append((name, hook, raw, env or {}, setup or {}))


def bash(stdout, stderr='', cmd='make', tuid='toolu_1', sid='s1', extra=None, resp_extra=None):
    r = {'stdout': stdout, 'stderr': stderr, 'interrupted': False, 'isImage': False}
    r.update(resp_extra or {})
    p = {'session_id': sid, 'tool_name': 'Bash', 'tool_input': {'command': cmd}, 'tool_response': r}
    if tuid is not None:
        p['tool_use_id'] = tuid
    p.update(extra or {})
    return p


def lines(n, fmt='line {i}: some ordinary build output here'):
    return '\n'.join(fmt.format(i=i) for i in range(1, n + 1))


SKILL = 'skills/token-miser/SKILL.md'

# ---------- 5.1 SessionStart ----------
case('5.1-startup', 'activate', {'session_id': 's1', 'source': 'startup'})
case('5.1-clear', 'activate', {'session_id': 's1', 'source': 'clear'})
case('5.1-compact', 'activate', {'session_id': 's1', 'source': 'compact'})
case('5.1-unknown-source', 'activate', {'session_id': 's1', 'source': 'weird'})
case('5.1-no-source', 'activate', {'session_id': 's1'})
case('5.1-resume', 'activate', {'session_id': 's1', 'source': 'resume'})
case('5.1-fork', 'activate', {'session_id': 's1', 'source': 'fork'})
case('5.1-statusline-set', 'activate', {'source': 'startup'},
     setup={'cfg/settings.json': '{"statusLine": {"type": "command", "command": "x"}}'})
case('5.1-statusline-unset', 'activate', {'source': 'startup'}, setup={'cfg/settings.json': '{"model": "x"}'})
case('5.1-off-env', 'activate', {'source': 'startup'}, env={'TOKEN_MISER_DEFAULT_MODE': 'OFF'})
case('5.1-off-config', 'activate', {'source': 'startup'}, setup={'xdg/token-miser/config.json': '{"defaultMode": "Off"}'})
case('5.1-env-beats-config', 'activate', {'source': 'resume'}, env={'TOKEN_MISER_DEFAULT_MODE': 'on'},
     setup={'xdg/token-miser/config.json': '{"defaultMode": "off"}'})
case('5.1-project-off', 'activate', {'source': 'startup'},
     setup={'xdg/token-miser/config.json': '{"defaultMode": "on"}', 'work/.claude/token-miser.json': '{"defaultMode": "off"}'})
case('5.1-project-keeps-user-key', 'activate', {'source': 'resume'},
     setup={'xdg/token-miser/config.json': '{"defaultMode": "off"}', 'work/.claude/token-miser.json': '{"sections": {"code": false}}'})
case('5.1-project-invalid', 'activate', {'source': 'resume'},
     setup={'xdg/token-miser/config.json': '{"defaultMode": "off"}', 'work/.claude/token-miser.json': '{"defaultMode": on}'})
case('3-project-sections', 'prompt', {'prompt': 'x'},
     setup={'xdg/token-miser/config.json': '{"sections": {"prose": false}}', 'work/.claude/token-miser.json': '{"sections": {"prose": true, "code": false}}'})
case('5.1-config-bom', 'activate', {'source': 'resume'}, setup={'xdg/token-miser/config.json': '\ufeff{"defaultMode": "off"}'})
case('5.1-config-invalid', 'activate', {'source': 'resume'}, setup={'xdg/token-miser/config.json': '{"defaultMode": off}'})
case('5.1-config-wrong-type', 'activate', {'source': 'resume'}, setup={'xdg/token-miser/config.json': '{"defaultMode": false}'})
case('5.1-env-invalid', 'activate', {'source': 'resume'}, env={'TOKEN_MISER_DEFAULT_MODE': 'lite'})
case('5.1-session-off', 'activate', {'session_id': 's1', 'source': 'compact'}, setup={'cfg/token-miser/sessions/s1.mode': 'off'})
case('5.1-session-on-beats-default', 'activate', {'session_id': 's1', 'source': 'resume'},
     env={'TOKEN_MISER_DEFAULT_MODE': 'off'}, setup={'cfg/token-miser/sessions/s1.mode': ' ON\n'})
case('5.1-session-garbage', 'activate', {'session_id': 's1', 'source': 'resume'},
     env={'TOKEN_MISER_DEFAULT_MODE': 'off'}, setup={'cfg/token-miser/sessions/s1.mode': 'maybe'})
case('3-no-prose', 'activate', {'source': 'startup'}, setup={'xdg/token-miser/config.json': '{"sections": {"prose": false}}'})
case('3-no-code', 'activate', {'source': 'startup'}, setup={'xdg/token-miser/config.json': '{"sections": {"code": false}}'})
case('3-neither', 'activate', {'source': 'startup'},
     setup={'xdg/token-miser/config.json': '{"sections": {"prose": false, "code": false}}'})
case('3-output-style', 'activate', {'source': 'startup'}, setup={'work/.claude/settings.json': '{"outputStyle": "Explanatory"}'})
case('3-output-style-default', 'activate', {'source': 'startup'}, setup={'work/.claude/settings.json': '{"outputStyle": " Default "}'})
case('3-output-style-local-first', 'activate', {'source': 'startup'},
     setup={'work/.claude/settings.local.json': '{"outputStyle": "default"}', 'work/.claude/settings.json': '{"outputStyle": "Learning"}'})
case('3-output-style-empty-skipped', 'activate', {'source': 'startup'},
     setup={'work/.claude/settings.json': '{"outputStyle": "  "}', 'cfg/settings.json': '{"outputStyle": "Learning", "statusLine": 1}'})
case('3-output-style-not-string', 'activate', {'source': 'startup'}, setup={'work/.claude/settings.json': '{"outputStyle": 3}'})
case('3-explicit-prose-wins', 'prompt', {'prompt': 'x'},
     setup={'xdg/token-miser/config.json': '{"sections": {"prose": true}}', 'work/.claude/settings.json': '{"outputStyle": "Learning"}'})
case('1-invalid-json', 'activate', '{"source": "startup",}')
case('1-not-object', 'activate', '["startup"]')
case('1-invalid-utf8', 'activate', b'{"source": "st\xffartup"}')
case('1-empty-input', 'activate', '')
case('1-trailing-garbage', 'activate', '{"source": "resume"} x')

# ---------- 5.2 UserPromptSubmit ----------
case('5.2-plain', 'prompt', {'session_id': 's1', 'prompt': 'fix the bug'})
case('5.2-no-prompt', 'prompt', {'session_id': 's1'})
for i, f in enumerate(['stop token-miser', 'token-miser off', 'token-miser mode off', '/token-miser off',
                       'disable token-miser', 'turn off token-miser', 'deactivate token-miser', 'normal mode']):
    case('5.2-off-%d' % i, 'prompt', {'session_id': 's1', 'prompt': f})
for i, f in enumerate(['/token-miser', '/token-miser on', 'token-miser on', 'token-miser mode', 'token-miser mode on',
                       'start token-miser', 'enable token-miser', 'turn on token-miser', 'activate token-miser', 'use token-miser']):
    case('5.2-on-%d' % i, 'prompt', {'session_id': 's1', 'prompt': f}, setup={'cfg/token-miser/sessions/s1.mode': 'off'})
for i, f in enumerate(['  Stop   Token Miser! ', '`/token-miser off`', "'normal mode.'", 'TOKENMISER OFF', '"stop token-miser"',
                       'stop\ttoken-miser\n', 'Token Miser Mode Off.']):
    case('5.2-form-%d' % i, 'prompt', {'session_id': 's1', 'prompt': f})
for i, f in enumerate(['add a normal mode toggle', "don't stop token-miser", 'stop token-miser now', 'please turn off token-miser',
                       'normal mode?', 'stop token-miser!!', '`stop token-miser"']):
    case('5.2-not-switch-%d' % i, 'prompt', {'session_id': 's1', 'prompt': f})
case('5.2-off-quiet', 'prompt', {'session_id': 's1', 'prompt': 'hi'}, setup={'cfg/token-miser/sessions/s1.mode': 'off'})
case('5.2-bad-sid', 'prompt', {'session_id': '../x', 'prompt': 'stop token-miser'})
case('5.2-long-sid', 'prompt', {'session_id': 'a' * 129, 'prompt': 'stop token-miser'})
case('5.2-no-prose', 'prompt', {'prompt': 'x'}, setup={'xdg/token-miser/config.json': '{"sections": {"prose": false}}'})
case('5.2-no-code', 'prompt', {'prompt': 'x'}, setup={'xdg/token-miser/config.json': '{"sections": {"code": false}}'})

# ---------- 5.3 SubagentStart ----------
case('5.3-on', 'subagent', {'session_id': 's1', 'agent_type': 'Explore'})
case('5.3-off', 'subagent', {'session_id': 's1'}, setup={'cfg/token-miser/sessions/s1.mode': 'off'})

# ---------- 4.1 eligibility ----------
BIG = lines(300)
case('4.1-small', 'compress', bash('hello'))
case('4.1-mode-off', 'compress', bash(BIG), setup={'cfg/token-miser/sessions/s1.mode': 'off'})
case('4.1-compress-off', 'compress', bash(BIG), env={'TOKEN_MISER_COMPRESS': '0'})
case('4.1-read-never', 'compress', {'session_id': 's1', 'tool_name': 'Read', 'tool_use_id': 't', 'tool_response': BIG},
     env={'TOKEN_MISER_TOOLS': 'Read'})
case('4.1-tools-list', 'compress', {'session_id': 's1', 'tool_name': 'Grep', 'tool_use_id': 't', 'tool_response': {'content': BIG}},
     env={'TOKEN_MISER_TOOLS': ' Bash , Grep'})
case('4.1-tools-list-miss', 'compress', bash(BIG), env={'TOKEN_MISER_TOOLS': 'Grep'})
case('4.1-mcp', 'compress', {'session_id': 's1', 'tool_name': 'mcp__srv__q', 'tool_use_id': 't',
                             'tool_response': [{'type': 'text', 'text': BIG}]})
case('4.1-unknown-tool', 'compress', {'session_id': 's1', 'tool_name': 'Frob', 'tool_use_id': 't', 'tool_response': BIG})
case('4.1-image', 'compress', bash(BIG, resp_extra={'isImage': True}))
case('4.1-interrupted', 'compress', bash(BIG, resp_extra={'interrupted': True}))
case('4.1-persisted', 'compress', bash(BIG, resp_extra={'persistedOutputPath': '/x/y.txt', 'persistedOutputSize': 99999}))
case('4.1-spill-read', 'compress', bash(BIG, cmd='grep -n x ~/.claude/token-miser/spill/Bash-1.txt'))
case('4.1-spill-read-win', 'compress', bash(BIG, cmd='findstr x C:\\u\\.claude\\token-miser\\spill\\a.txt'))
case('4.1.2-nul-one', 'compress', bash(BIG + '\u0000'))
case('4.1.2-nul-utf16', 'compress', bash('\u0000'.join('Windows tool line %d of UTF-16 output\r\n' % i for i in range(200))))
case('4.1.2-nul-few', 'compress', bash('ok' + '\u0000' * 10 + 'done'))
case('4.1-dup-key', 'compress', '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t","tool_response":{"stdout":%s,"stdout":"x"}}' % json.dumps(BIG))
case('4.1-null-response', 'compress', {'session_id': 's1', 'tool_name': 'Bash', 'tool_response': None})
case('4.1-no-slots', 'compress', {'session_id': 's1', 'tool_name': 'Bash', 'tool_response': {'files': [BIG]}})

# ---------- 4.1.1 shapes and 4.6 rebuild ----------
case('4.6-string-response', 'compress', {'session_id': 's1', 'tool_name': 'Agent', 'tool_use_id': 't', 'tool_response': BIG})
case('4.6-stdout-and-stderr', 'compress', bash(BIG, lines(200, 'warn {i}: deprecated call in module {i}')))
case('4.6-raw-copy', 'compress',
     '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t","tool_response":{"code": 1.50e+3 ,"stdout":%s,"meta":{"a":[1, 2 ,"\\u00e9\\/x"],"b":null},"stderr":""}}' % json.dumps(BIG))
case('4.6-blocks', 'compress', {'session_id': 's1', 'tool_name': 'mcp__a__b', 'tool_use_id': 't', 'tool_response': {
    'content': [{'type': 'text', 'text': BIG}, {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
                {'type': 'text', 'text': 'short', 'annotations': {'x': 1}}], 'isError': False}})
case('4.6-output-key', 'compress', {'session_id': 's1', 'tool_name': 'Agent', 'tool_use_id': 't', 'tool_response': {'output': BIG, 'n': 3}})
case('4.6-result-key', 'compress', {'session_id': 's1', 'tool_name': 'WebFetch', 'tool_use_id': 't',
                                    'tool_response': {'bytes': 5, 'code': 200, 'result': BIG, 'url': 'https://x'}})
case('4.6-block-dup-key', 'compress', '{"session_id":"s1","tool_name":"mcp__a","tool_use_id":"t","tool_response":[{"type":"text","text":%s,"text":"y"}]}' % json.dumps(BIG))
case('4.6-savings-under-64', 'compress', bash('x' * 1030 + '   \n' * 10))

# ---------- 4.2.1 clean ----------
case('4.2.1-ansi', 'compress', bash('\n'.join('\x1b[32mok\x1b[0m test %d \x1b]8;;http://x\x07link\x1b]8;;\x07' % i for i in range(60))))
case('4.2.1-trailing', 'compress', bash('\n'.join('value %d   \t' % i for i in range(200)) + '   '))
case('4.2.1-crlf', 'compress', bash('\r\n'.join('value %d  ' % i for i in range(200)) + '  \r'))
case('4.2.1-progress', 'compress', bash('\n'.join('fetch %d%%\rfetch 50%%\rfetch 100%% done %d' % (i, i) for i in range(80))))
case('4.2.1-progress-crlf', 'compress', bash('\n'.join('a %d\rb %d  \r' % (i, i) for i in range(120))))
case('4.2.1-blank-runs', 'compress', bash('\n\n\n\n' + '\n\n\n\n'.join('block %d' % i for i in range(150)) + '\n\n\n'))
# ---------- 4.2.2 repeats ----------
case('4.2.2-repeats', 'compress', bash('start\n' + 'same line\n' * 40 + 'mid\n' + 'x\nx\n' + 'y\ny\ny\n' + '\n\n' + 'end ' * 300))
case('4.2.2-repeats-to-cut', 'compress', bash(('dup\n' * 5000) + lines(150)))
# ---------- 4.2.3 timestamps ----------
case('4.2.3-iso', 'compress', bash('\n'.join('2026-09-30T12:00:%02d.%03dZ INFO heartbeat ok' % (i % 60, i) for i in range(50)) + '\ndone'))
case('4.2.3-bracket', 'compress', bash('\n'.join('[12:00:%02d] worker idle' % (i % 60) for i in range(40)) + '\n[12:01:00] worker busy\n' + 'tail ' * 200))
case('4.2.3-offset', 'compress', bash('\n'.join('2026-09-30 12:00:%02d,5+02:00  poll' % (i % 60) for i in range(40)) + '\n' + 'z' * 1200))
case('4.2.3-two-runs', 'compress', bash('\n'.join('09:00:%02d a' % i for i in range(20)) + '\n' + '\n'.join('09:01:%02d b' % i for i in range(20)) + '\n' + 'q' * 1100))
# ---------- 4.2.4 frames ----------
js = 'TypeError: x is undefined\n' + '\n'.join('    at fn%d (/app/src/m%d.js:%d:%d)' % (i, i, i, i) for i in range(20)) + '\n'
case('4.2.4-js', 'compress', bash(js * 3))
py = 'Traceback (most recent call last):\n' + '\n'.join('  File "/app/m%d.py", line %d, in f%d\n    return f%d(x)' % (i, i, i, i + 1) for i in range(15)) + '\nValueError: bad\n'
case('4.2.4-python', 'compress', bash(py * 2))
gdb = '\n'.join('#%d  0x0000%04x in f%d () at a.c:%d' % (i, i, i, i) for i in range(12)) + '\n' + 'r' * 1100
case('4.2.4-gdb', 'compress', bash(gdb))
case('4.2.4-short-run', 'compress', bash(('    at a (b.js:1:1)\n' * 7).replace('a (', 'q (') + 'x' * 1100))
# ---------- 4.2.5 passes ----------
case('4.2.5-jest', 'compress', bash('\n'.join('  \u2713 case %d (3 ms)' % i for i in range(40)) + '\n  \u2715 broken case\n    Error: boom\n' + '\n'.join('  \u2713 later %d' % i for i in range(12))))
case('4.2.5-go', 'compress', bash('\n'.join('ok  \tgithub.com/acme/project/pkg/m%d\t0.0%ds' % (i, i % 10) for i in range(60)) + '\nFAIL\tpkg/bad\t0.1s'))
case('4.2.5-pass-with-error-word', 'compress', bash('\n'.join('PASS tests/unit/test_module_%d.py' % i for i in range(9)) + '\nPASS error handling suite\n' + '\n'.join('PASS tests/unit/test_other_%d.py' % i for i in range(40))))
case('4.2.5-trailing-ok', 'compress', bash('\n'.join('test_case_%d ... ok' % i for i in range(60))))
# ---------- 4.2.6 long lines ----------
case('4.2.6-long-line', 'compress', bash('head\n' + 'a' * 3000 + '\u00e9' * 1000 + 'b' * 3000 + '\ntail'))
case('4.2.6-long-lines-many', 'compress', bash('\n'.join(('%d:' % i) + 'x' * 5000 for i in range(3))))
# ---------- 4.2.7 cut by lines, 4.3 rescue ----------
case('4.2.7-plain', 'compress', bash(lines(3000)))
case('4.2.7-errors', 'compress', bash(lines(500) + '\nERROR: disk full\n' + lines(300) + '\nfatal: bad object abc\nnext line\n' + lines(400)))
case('4.2.7-many-errors', 'compress', bash('\n'.join(('error %d here' % i) if i % 7 == 0 else ('fine %d' % i) for i in range(2000))))
case('4.2.7-no-error-phrases', 'compress', bash('\n'.join(['build 0 errors, 0 warnings', 'no failures found', 'errors: 0', 'failed=0', 'Errors = 0 of 3'] * 400)))
case('4.2.7-error-at-edges', 'compress', bash(lines(60) + '\nerror at first cut line\n' + lines(500) + '\nerror at last cut line\n' + lines(40)))
case('4.2.7-error-word-bounds', 'compress', bash('\n'.join(['terror in the night', 'errorless', 'my_error here', 'failover done', 'the failure mode', 'errno=2', 'panic!', "can't open", 'no such file or directory'] * 300)))
case('4.2.7-long-rescued-line', 'compress', bash(lines(100) + '\nerror ' + 'q' * 600 + '\n' + lines(200)))
case('4.2.7-env-limits', 'compress', bash(lines(400)), env={'TOKEN_MISER_MAX_BYTES': '2000', 'TOKEN_MISER_HEAD_LINES': '5', 'TOKEN_MISER_TAIL_LINES': '3'})
case('4.2.7-env-invalid', 'compress', bash(lines(400)), env={'TOKEN_MISER_MAX_BYTES': '12x', 'TOKEN_MISER_HEAD_LINES': '0', 'TOKEN_MISER_TAIL_LINES': '9999999999'})
case('4.2.7-stamps-in-head', 'compress', bash('\n'.join('12:00:%02d tick' % (i % 60) for i in range(100)) + '\n' + lines(3000)))
# ---------- 4.2.8 cut by bytes ----------
case('4.2.8-bytes', 'compress', bash('\n'.join(('{"k%d": "' % i) + 'v' * 3000 + '"}' for i in range(10))))
case('4.2.8-utf8-boundary', 'compress', bash('\u65e5\u672c' * 3000))
case('4.2.8-astral', 'compress', bash('\U0001F600' * 3000))
# ---------- 4.2 view commands ----------
case('4.2-view-small', 'compress', bash(lines(250, 'line {i}: text with trailing spaces   '), cmd='cat notes.txt'))
case('4.2-not-view-same-text', 'compress', bash(lines(250, 'line {i}: text with trailing spaces   '), cmd='make'))
case('4.2-view-medium', 'compress', bash(lines(400, 'line {i}: text with trailing spaces   '), cmd='cat notes.txt'))
case('4.2-view-large', 'compress', bash(lines(2000) + '\nERROR x\n' + lines(100), cmd='  FOO=1 BAR=2 sudo cat big.txt'))
case('4.2-view-git', 'compress', bash(lines(3000), cmd='git diff HEAD~1'))
case('4.2-view-git-log-not-view', 'compress', bash(lines(3000), cmd='git log'))
case('4.2-view-pipe-not-view', 'compress', bash(lines(3000), cmd='cat x | grep y'))
case('4.2-view-bytes', 'compress', bash('z' * 40000, cmd='cat one-line.txt'))

def pwsh(stdout, cmd):
    p = bash(stdout, cmd=cmd)
    p['tool_name'] = 'PowerShell'
    return p

case('4.2-powershell', 'compress', pwsh(lines(3000), 'Get-ChildItem -Recurse'))
case('4.2-powershell-view', 'compress', pwsh(lines(250, 'line {i}: text with trailing spaces   '), 'Get-Content .\\notes.txt'))
case('4.2-powershell-view-alias', 'compress', pwsh(lines(250, 'line {i}: text with trailing spaces   '), 'GC notes.txt'))
case('4.2-powershell-view-pipe', 'compress', pwsh(lines(250, 'line {i}: text with trailing spaces   '), 'Get-Content x.txt | Select-String y'))
# ---------- 4.4 spill ----------
case('4.4-credential', 'compress', bash(lines(300) + '\nexport API_KEY="abcd1234efgh"\n' + lines(300)))
case('4.4-private-key', 'compress', bash('-----BEGIN OPENSSH PRIVATE KEY-----\n' + lines(400)))
case('4.4-github-token', 'compress', bash(lines(200) + '\ntoken ghp_' + 'A1b2' * 9 + '\n' + lines(200)))
case('4.4-bearer', 'compress', bash(lines(200) + '\nAuthorization: Bearer abcdefghijklmnopqrstuv\n' + lines(200)))
case('4.4-spill-off', 'compress', bash(lines(400)), env={'TOKEN_MISER_SPILL': '0'})
case('4.4-no-tool-use-id', 'compress', bash(lines(400), tuid=None))
case('4.4-tuid-sanitised', 'compress', bash(lines(400), tuid='../../evil id'))
case('4.4-tool-name-sanitised', 'compress', {'session_id': 's1', 'tool_name': 'mcp__a.b/c', 'tool_use_id': 't9', 'tool_response': lines(400)})
# ---------- 4.5 dedup ----------
UNIT = lines(300)
case('4.5-dup', 'compress', bash(UNIT, tuid='t2'), setup={'cfg/token-miser/sessions/s1.Bash.last': 't1\n' + UNIT + '\x1e'})
case('4.5-same-id', 'compress', bash(UNIT, tuid='t1'), setup={'cfg/token-miser/sessions/s1.Bash.last': 't1\n' + UNIT + '\x1e'})
case('4.5-different', 'compress', bash(UNIT, tuid='t2'), setup={'cfg/token-miser/sessions/s1.Bash.last': 't1\n' + UNIT + 'x\x1e'})
case('4.5-dedup-off', 'compress', bash(UNIT, tuid='t2'), env={'TOKEN_MISER_DEDUP': '0'},
     setup={'cfg/token-miser/sessions/s1.Bash.last': 't1\n' + UNIT + '\x1e'})
case('4.5-no-session', 'compress', bash(UNIT, tuid='t2', sid=''))
case('4.5-small-unit', 'compress', bash(lines(40), tuid='t2'), setup={'cfg/token-miser/sessions/s1.Bash.last': 't1\n' + lines(40) + '\x1e'})
case('4.5-dup-blocks', 'compress', {'session_id': 's1', 'tool_name': 'mcp__x', 'tool_use_id': 't2',
                                    'tool_response': [{'type': 'text', 'text': UNIT}, {'type': 'text', 'text': 'b'}]},
     setup={'cfg/token-miser/sessions/s1.mcp__x.last': 't1\n' + UNIT + '\x1eb'})
# ---------- stats (2) ----------
case('2-stats-new', 'compress', bash(lines(400)))
case('2-stats-add', 'compress', bash(lines(400)), setup={'cfg/token-miser/stats': 'saved 100\nevents 2\n'})
case('2-stats-corrupt', 'compress', bash(lines(400)), setup={'cfg/token-miser/stats': 'saved lots\n'})
# ---------- 1 JSON details ----------
case('1-escapes', 'compress', bash('\n'.join('tab\there "q" back\\slash \u00e9 \U0001F600 ctl\x01 del\x7f %d' % i for i in range(300))))
case('1-lone-surrogate', 'compress', '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t","tool_response":{"stdout":"%s\\ud800 x \\udc00\\ud83d\\ude00","stderr":""}}' % ('abc \\u00e9\\n' * 400))
case('1-escaped-slash', 'compress', '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t","tool_response":{"stdout":"%s","stderr":""}}' % ('a\\/b\\\\c\\"d\\n' * 500))
case('1-uppercase-hex', 'compress', '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t","tool_response":{"stdout":"%s","stderr":""}}' % ('\\u00C9\\u00e9 x\\n' * 500))
case('1-bad-escape', 'compress', '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t","tool_response":{"stdout":"a\\x b","stderr":""}}')
case('1-raw-control', 'compress', '{"session_id":"s1","tool_name":"Bash","tool_use_id":"t","tool_response":{"stdout":"a\tb","stderr":""}}')

if os.path.isdir(OUT):
    shutil.rmtree(OUT)
seen = set()
for name, hook, raw, env, setup in cases:
    assert name not in seen, name
    seen.add(name)
    d = os.path.join(OUT, name)
    os.makedirs(d)
    open(os.path.join(d, 'hook'), 'w').write(hook + '\n')
    open(os.path.join(d, 'input.json'), 'wb').write(raw)
    if env:
        open(os.path.join(d, 'env'), 'w').write(''.join('%s=%s\n' % kv for kv in sorted(env.items())))
    for rel, content in setup.items():
        p = os.path.join(d, 'setup', rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, 'wb').write(content.encode('utf-8') if isinstance(content, str) else content)
print('%d cases' % len(cases))
