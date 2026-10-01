#!/usr/bin/env python3
"""Draw the README charts from an analyze-arms.py JSON file.

  python3 benchmarks/charts.py ARMS.json OUTDIR

Writes NAME-light.png and NAME-dark.png for each chart, so the README can
pick one with <picture> and prefers-color-scheme. Needs matplotlib.
Output tokens are shown as a percentage of the no-plugin arm (lower is better).
"""
import json, os, sys
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
d = json.load(open(src))
NAMES = json.loads(os.environ.get('ARM_NAMES', '{}'))
def name(a): return NAMES.get(a, a)
ORDER = ['skinflint', 'chisle', 'ponytail', 'caveman']
plugins = sorted((a for a in d['arms'] if a != 'none'), key=lambda a: ORDER.index(a) if a in ORDER else len(ORDER))

# Categorical slots in fixed order (validated palette, adjacent pairs),
# light and dark steps; the highlight is always slot 1.
THEMES = {
    'light': dict(bg='#fcfcfb', ink='#0b0b0b', ink2='#52514e', grid='#e4e3df', muted='#b9b8b3',
                  series=['#2a78d6', '#eb6834', '#1baf7a', '#eda100']),
    'dark': dict(bg='#1a1a19', ink='#ffffff', ink2='#c3c2b7', grid='#383835', muted='#6b6a65',
                 series=['#3987e5', '#d95926', '#199e70', '#c98500']),
}

def frame(ax, t):
    ax.set_facecolor(t['bg'])
    for s in ('top', 'right', 'left'):
        ax.spines[s].set_visible(False)
    ax.spines['bottom'].set_color(t['grid'])
    ax.tick_params(colors=t['ink2'], length=0)
    ax.xaxis.grid(True, color=t['grid'], linewidth=0.8)
    ax.set_axisbelow(True)

def top_legend(ax, t, n):
    ax.legend(loc='lower left', bbox_to_anchor=(0, 1.0), ncol=n, frameon=False, fontsize=9.5,
              labelcolor=t['ink'], handlelength=1.2, borderaxespad=0.2)

def save(fig, stem, mode):
    fig.savefig(os.path.join(out, '%s-%s.png' % (stem, mode)), dpi=200, facecolor=fig.get_facecolor())
    plt.close(fig)

def overall(mode, t):
    rows = sorted(plugins, key=lambda a: d['overall'][a]['total_pct'], reverse=True)
    vals = [d['overall'][a]['total_pct'] for a in rows]
    fig, ax = plt.subplots(figsize=(7.2, 2.9), facecolor=t['bg'])
    frame(ax, t)
    colors = [t['series'][0] if a == 'skinflint' else t['muted'] for a in rows]
    bars = ax.barh([name(a) for a in rows], vals, color=colors, height=0.62)
    for b, v, a in zip(bars, vals, rows):
        ax.text(v + 1.2, b.get_y() + b.get_height() / 2, '%d%%' % v, va='center', fontsize=10,
                color=t['ink'], fontweight='bold' if a == 'skinflint' else 'normal')
    ax.set_xlim(0, 100)
    ax.set_xticks([0, 25, 50, 75, 100]); ax.set_xticklabels(['0', '25%', '50%', '75%', '100%'])
    ax.tick_params(axis='y', labelsize=10.5, labelcolor=t['ink'])
    ax.set_title('Output tokens, % of no plugin (lower is better)', loc='left', color=t['ink'], fontsize=11.5, pad=10)
    fig.tight_layout()
    save(fig, 'output-overall', mode)

def by_group(mode, t):
    groups = ['coding/short', 'coding/long', 'explain/short', 'explain/long']
    labels = ['coding, short', 'coding, long', 'explain, short', 'explain, long']
    n = len(plugins); h = 0.8 / n
    fig, ax = plt.subplots(figsize=(7.2, 4.4), facecolor=t['bg'])
    frame(ax, t)
    for i, a in enumerate(plugins):
        ys = [g - 0.4 + h / 2 + i * h for g in range(len(groups))]   # skinflint on top
        vals = [d['by_size'][g][a]['total_pct'] for g in groups]
        ax.barh(ys, vals, height=h - 0.03, color=t['series'][i], label=name(a))
        for y, v in zip(ys, vals):
            ax.text(v + 1, y, '%d' % v, va='center', fontsize=8.5, color=t['ink'],
                    fontweight='bold' if a == 'skinflint' else 'normal')
    ax.set_yticks(range(len(groups))); ax.set_yticklabels(labels)
    ax.invert_yaxis()
    ax.set_xlim(0, 100)
    ax.set_xticks([0, 25, 50, 75, 100]); ax.set_xticklabels(['0', '25%', '50%', '75%', '100%'])
    ax.tick_params(axis='y', labelsize=10.5, labelcolor=t['ink'])
    top_legend(ax, t, n)
    ax.set_title('Output tokens by kind of task, % of no plugin (lower is better)', loc='left', color=t['ink'], fontsize=11.5, pad=30)
    fig.tight_layout()
    save(fig, 'output-by-kind', mode)

def speed_rows():
    # Prompt-hook medians from the committed speed tables (speed.py, speed.ps1).
    def table(path):
        rows = {}
        for line in open(path):
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            if len(cells) > 2 and not cells[0].startswith(('ms', '---')):
                rows[cells[0]] = cells
        return rows
    res = os.path.dirname(src)
    lin, win = table(os.path.join(res, 'speed-linux.md')), table(os.path.join(res, 'speed-windows.md'))
    out = []
    for env, key in (('Linux, sh', None), ('Windows, Git Bash', 'Git Bash'),
                     ('Windows, PowerShell 5.1', 'PowerShell 5.1'), ('Windows, PowerShell 7', 'PowerShell 7')):
        vals = {}
        for a in plugins:
            c = lin.get(a) if key is None else win.get('%s, %s' % (a, key))
            vals[a] = c[2] if c else '-'           # column 2 is "prompt"
        out.append((env, vals))
    return out

def speed(mode, t):
    rows = speed_rows()
    n = len(plugins); h = 0.8 / n
    fig, ax = plt.subplots(figsize=(7.2, 4.6), facecolor=t['bg'])
    frame(ax, t)
    top = max(float(v.rstrip('!')) for _, vals in rows for v in vals.values() if v not in ('-',))
    for i, a in enumerate(plugins):
        for g, (env, vals) in enumerate(rows):
            y = g - 0.4 + h / 2 + i * h
            v = vals[a]
            if v == '-':
                continue
            if v.endswith('!'):
                ax.text(4, y, '%s fails' % name(a), va='center', fontsize=8.5, color=t['ink2'], style='italic')
                continue
            ms = float(v)
            ax.barh(y, ms, height=h - 0.03, color=t['series'][i], label=name(a) if g == 0 else None)
            ax.text(ms + top * 0.01, y, '%d' % ms, va='center', fontsize=8.5, color=t['ink'],
                    fontweight='bold' if a == 'skinflint' else 'normal')
    ax.set_yticks(range(len(rows))); ax.set_yticklabels([r[0] for r in rows])
    ax.invert_yaxis()
    ax.set_xlim(0, top * 1.12)
    ax.tick_params(axis='y', labelsize=10.5, labelcolor=t['ink'])
    top_legend(ax, t, n)
    ax.set_title('Hook time on every prompt, milliseconds (lower is better)', loc='left', color=t['ink'], fontsize=11.5, pad=30)
    fig.tight_layout()
    save(fig, 'speed', mode)

for mode, t in THEMES.items():
    overall(mode, t)
    by_group(mode, t)
    speed(mode, t)
print('wrote', sorted(os.listdir(out)))
