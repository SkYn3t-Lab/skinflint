#!/usr/bin/env python3
"""Estimate what each plugin would save you per month, from your own usage.

  python3 benchmarks/usage.py [~/.claude/projects] [RESULTS_DIR]

Reads your Claude Code transcripts (only token counts and sizes, never their
text) and prints, per plugin, the dollars per 30 days it would have saved:

- Output: every output token your sessions produced, priced per model, times
  the share of output tokens that plugin removes in the head-to-head
  benchmark (arms.json).
- Tool output: the output your sessions read from the tools the replay covers
  (Bash, PowerShell, Agent, WebFetch, WebSearch, Grep, Glob and MCP tools;
  results Claude Code saved to disk excluded), times the share that plugin removes in the replay
  (replay.json). A removed tool-output token is paid once as a cache write
  (1.25 x input) and again as a cache read on each later request that re-reads
  it; the number of later requests is the median measured in your own
  transcripts, counted up to the next compaction.

Prices are Anthropic's first-party list prices per million tokens
(platform.claude.com/docs/en/about-claude/pricing, read 2026-09-30). Models
not in the table are counted but not priced, and are reported.
"""
import glob, json, os, statistics, sys

PRICES = {  # model id prefix: input, output, cache read ($ per million tokens)
    'claude-fable-5-1': (10.00, 50.00, 0.25), 'claude-fable-5': (10.00, 50.00, 1.00),
    'claude-opus-5-5': (4.00, 20.00, 0.20), 'claude-opus-5': (5.00, 25.00, 0.50),
    'claude-opus-4-8': (5.00, 25.00, 0.50), 'claude-opus-4-7': (5.00, 25.00, 0.50), 'claude-opus-4-6': (5.00, 25.00, 0.50),
    'claude-sonnet-5-5': (2.00, 10.00, 0.20), 'claude-sonnet-5': (2.00, 10.00, 0.20), 'claude-sonnet-4-6': (3.00, 15.00, 0.30),
    'claude-haiku-4-5': (1.00, 5.00, 0.10),
}
TOOLS = {'Bash', 'PowerShell', 'Agent', 'Task', 'WebFetch', 'WebSearch', 'Grep', 'Glob'}

def price(model):
    for k in sorted(PRICES, key=len, reverse=True):
        if model.startswith(k):
            return PRICES[k]
    return None

src = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else '~/.claude/projects')
res = sys.argv[2] if len(sys.argv) > 2 else os.path.join(os.path.dirname(os.path.abspath(__file__)), 'results', '2026-09-30')
arms = json.load(open(os.path.join(res, 'arms.json')))
replay = json.load(open(os.path.join(res, 'replay.json')))

out_tokens, tool_bytes, days, unpriced = {}, {}, set(), {}
later = []
for path in sorted(glob.glob(os.path.join(src, '**', '*.jsonl'), recursive=True)):
    seen, requests, results, model, names = set(), 0, [], None, {}
    for line in open(path, encoding='utf-8', errors='replace'):
        try:
            d = json.loads(line)
        except Exception:
            continue
        if d.get('timestamp'):
            days.add(d['timestamp'][:10])
        if d.get('type') == 'system' and d.get('subtype') == 'compact_boundary':
            later += [requests - i for i, _ in results]
            requests, results = 0, []
        elif d.get('type') == 'assistant':
            m = d.get('message') or {}
            for b in m.get('content') or []:
                if isinstance(b, dict) and b.get('type') == 'tool_use':
                    names[b.get('id')] = b.get('name', '')
            if m.get('id') and m['id'] not in seen and m.get('model', '').startswith('claude-'):
                seen.add(m['id']); requests += 1; model = m['model']
                n = (m.get('usage') or {}).get('output_tokens') or 0
                out_tokens[model] = out_tokens.get(model, 0) + n
        elif d.get('type') == 'user' and 'toolUseResult' in d:
            r = d['toolUseResult']
            if isinstance(r, dict) and 'persistedOutputPath' in r:
                continue
            ids = [b.get('tool_use_id') for b in (d.get('message') or {}).get('content') or [] if isinstance(b, dict) and b.get('type') == 'tool_result']
            name = names.get(ids[0], '') if ids else ''
            if not (name in TOOLS or name.startswith('mcp__')):
                continue
            size = len(json.dumps(r, ensure_ascii=False).encode())
            results.append((requests, size))
            if model:
                tool_bytes[model] = tool_bytes.get(model, 0) + size
    later += [requests - i for i, _ in results]

span = max(len(days), 1)
per30 = 30 / span
med_later = statistics.median(later) if later else 0
plugins = [a for a in arms['arms'] if a != 'none']
spend = 0
for model, n in out_tokens.items():
    p = price(model)
    if p:
        spend += n / 1e6 * p[1]
    else:
        unpriced[model] = n
rows = []
for a in plugins:
    out_share = 1 - arms['overall'][a]['total_pct'] / 100
    tool_share = replay['arms'].get(a, {}).get('saved_pct', 0) / 100
    o = sum(n / 1e6 * price(m)[1] * out_share for m, n in out_tokens.items() if price(m))
    t = sum(b / 4 / 1e6 * tool_share * (1.25 * price(m)[0] + med_later * price(m)[2]) for m, b in tool_bytes.items() if price(m))
    rows.append((a, o * per30, t * per30))

print('%d days of transcripts, %s output tokens (%s), output spend $%.0f per 30 days at list price;'
      % (span, format(sum(out_tokens.values()), ','), ', '.join('%s %s' % (m, format(n, ',')) for m, n in sorted(out_tokens.items(), key=lambda x: -x[1])), spend * per30))
print('tool results re-read by a median of %g later requests.\n' % med_later)
print('| Plugin | Output, per 30 days | Tool output, per 30 days | Total per 30 days |')
print('|---|--:|--:|--:|')
for a, o, t in sorted(rows, key=lambda r: -(r[1] + r[2])):
    print('| %s | $%.2f | $%.2f | **$%.2f** |' % (a, o, t, o + t))
if unpriced:
    print('\nNot priced (unknown model): ' + ', '.join('%s %s tokens' % (m, format(n, ',')) for m, n in unpriced.items()))
