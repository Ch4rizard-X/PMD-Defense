"""Run after build_fx.py and fix_black_fx.py.
Later-generation attacks borrow a PMD Red move's effect (same type). An attack must show something reaching its target,
so a borrowed damaging move only takes an effect that has a projectile (p) or a hit-on-target animation (h):
first from PMD moves of the same type and category, then same type any damaging category, then same type any move."""
import json
W = '/home/claude/routedef/web/'
dex = json.load(open(W + 'data/dex.json'))['moves']; F = json.load(open(W + 'data/fx.json')); mv = F['moves']
reach = lambda e: 'p' in e or 'h' in e
native = {k: e for k, e in mv.items() if not e.get('borrowed')}
def pool(f):
    return [native[k] for k in sorted(native, key=int) if reach(native[k]) and f(dex[k])]
changed = []
for k, e in mv.items():
    m = dex[k]
    if not e.get('borrowed') or m['p'] <= 0 or reach(e): continue
    for f in (lambda x: x['t'] == m['t'] and x['c'] == m['c'] and x['p'] > 0, lambda x: x['t'] == m['t'] and x['p'] > 0, lambda x: x['t'] == m['t']):
        c = pool(f)
        if c:
            ranged = m['c'] == 3; pref = [x for x in c if ('p' in x) == ranged] or c   # ranged attacks prefer a projectile, contact ones a hit
            mv[k] = dict(pref[int(k) * 7 % len(pref)], borrowed=1); changed.append((m['n'], [x for x in ('u', 'p', 'h') if x in mv[k]])); break
json.dump(F, open(W + 'data/fx.json', 'w'), separators=(',', ':'))
print(len(changed), 'borrowed attacks now reach their target'); print(changed)
