"""Move effects, Explorers of Sky first (the user's choice):
  1. Explorers of Sky (the user's EoS dump: eos_move_effects.zip, made from their ROM)
  2. PMD Explorers Remixed 2.3.28 (the user's patch applied to that same ROM): its new moves reuse EoS effect files,
     and the hack's own table (BALANCE/anim.bin) says which effect each new move uses
  3. PMD Red (the current fx.json from build_fx.py + fix_black_fx.py)
  4. still nothing: borrow from a move of the same type whose effect reaches the target (see fix_borrowed_fx.py)
EoS sheets keep their anchor point (origin_in_frame), so effects sit where the game puts them."""
import json, re, struct, zipfile, io, os
from PIL import Image
W = '/home/claude/routedef/web/'; Z = zipfile.ZipFile('/home/claude/eos/eos_move_effects.zip'); RX = '/home/claude/remix/unpacked/'
dex = json.load(open(W + 'data/dex.json'))['moves']
red = json.load(open('/home/claude/routedef/fx_red_backup.json'))
norm = lambda s: re.sub(r'[^a-z0-9]', '', s.lower())
ALIAS = {'faintattack': 'feintattack', 'hijumpkick': 'highjumpkick', 'smellingsalt': 'smellingsalts', 'vicegrip': 'visegrip'}
key = lambda s: ALIAS.get(norm(s), norm(s))
# --- 1. EoS
eos = {key(m['name']): m for m in json.loads(Z.read('eos_move_effects/move_effects.json'))}
# --- 2. Remixed: names from its text, stages from BALANCE/anim.bin
t = open(RX + 'MESSAGE/text_e.str', 'rb').read(); n = struct.unpack_from('<I', t, 0)[0] // 4; ptr = struct.unpack_from('<%dI' % n, t, 0)
def s(i): e = t.find(b'\0', ptr[i]); return t[ptr[i]:e if e >= 0 else len(t)].decode('cp1252', 'replace')
a = open(RX + 'BALANCE/anim.bin', 'rb').read(); mo, eo = struct.unpack_from('<I', a, 8)[0], struct.unpack_from('<I', a, 12)[0]
EF = [struct.unpack_from('<IIIIiIBBBB', a, eo + i * 28) for i in range(700)]
KIND = {1: 'wan (effect 0)', 2: 'wan (effect 1)', 3: 'wan', 4: 'wat (ground wan)', 5: 'screen effect', 6: 'wba'}
remix = {}
for m in range(1, 561):
    a1, a2, a3, a4, flags, speed, uanim, point, se, ns, sp = struct.unpack_from('<HHHHIIBBHHH', a, mo + m * 24)
    st = []
    for si, k in enumerate((a1, a2, a3, a4)):
        if k:
            ty, fi, pal, an = EF[k][:4]
            st.append(dict(stage=si + 1, kind=KIND.get(ty, ty), effect_file=fi if ty in (1, 2, 3, 4) else None, animation=an))
    nm = s(8173 + m)
    if nm and key(nm) not in eos: remix[key(nm)] = dict(name=nm, stages=st, user_animation=uanim)
# --- sheets
anims = {}; INFO = {}
def anim(fi, an):
    ref = f'eos{fi:03d}/anim{an:02d}'
    if ref in anims: return ref
    base = f'eos_move_effects/effect_files/effect_{fi:03d}/'
    if fi not in INFO:
        try: INFO[fi] = {x['animation_index']: x for x in json.loads(Z.read(base + 'info.json'))['animations']}
        except KeyError: INFO[fi] = {}
    i = INFO[fi].get(an)
    if not i: return None
    im = Image.open(io.BytesIO(Z.read(base + f"{i['file']}_sheet.png"))).convert('RGBA')
    if im.getbbox() is None: return None
    name = f'eos{fi:03d}_anim{an:02d}'; im.save(W + f'img/fx/{name}.png')
    fw, fh = i['frame_size']; anims[ref] = dict(f=name, fw=fw, fh=fh, n=i['frames'], r=1, d=i['durations_60fps'], ox=i['origin_in_frame'][0], oy=i['origin_in_frame'][1])
    return ref
def entry(m, src):
    e = dict(b=m.get('user_animation', 99), src=src)
    for st in sorted(m['stages'], key=lambda x: x['stage']):
        if st['effect_file'] is None: continue
        k = {1: 'u', 2: 'u', 3: 'p', 4: 'h'}[st['stage']]
        if k in e: continue   # stage 1 wins over stage 2 for the user effect
        r = anim(st['effect_file'], st['animation'])
        if r: e[k] = r
    return e if any(k in e for k in 'uph') else None
mv = {}; cnt = {'eos': 0, 'remix': 0, 'red': 0}
for mid, m in dex['moves'].items() if 'moves' in dex else dex.items():
    k = key(m['n']); e = None
    if k in eos: e = entry(eos[k], 'eos')
    if not e and k in remix: e = entry(remix[k], 'remix')
    if not e:
        r = red['moves'].get(mid)
        if r and not r.get('borrowed'):
            e = dict(r, src='red')
            for x in 'uph':
                if x in e and e[x] not in anims: anims[e[x]] = red['anims'][e[x]]
    if e: mv[mid] = e; cnt[e['src']] += 1
# 4. borrow: same type; a damaging move only takes an effect that reaches its target (projectile or hit);
#    prefer the same category, and EoS/Remixed effects over Red's so the look stays consistent
reach = lambda e: 'p' in e or 'h' in e
nat = sorted(mv, key=int); fill = 0
for mid, m in dex.items():
    if mid in mv: continue
    dmg = m['p'] > 0
    for f in (lambda x: x['t'] == m['t'] and x['c'] == m['c'], lambda x: x['t'] == m['t'] and (x['p'] > 0) == dmg, lambda x: x['t'] == m['t']):
        c = [mv[k] for k in nat if f(dex[k]) and (reach(mv[k]) or not dmg)]
        if c:
            c = [x for x in c if x['src'] != 'red'] or c
            if dmg: c = [x for x in c if ('p' in x) == (m['c'] == 3)] or c   # ranged attacks prefer a projectile, contact ones a hit
            mv[mid] = dict(c[int(mid) * 7 % len(c)], borrowed=1); fill += 1; break
print(fill, 'borrowed;', len(dex) - len(mv), 'with no effect at all')
json.dump(dict(anims=anims, moves=mv), open(W + 'data/fx.json', 'w'), separators=(',', ':'))
print(cnt, 'moves with a real effect;', len(dex) - len(mv), 'left to borrow;', len(anims), 'sheets')
print('remixed moves used:', sorted(remix[k]['name'] for k in remix if any(v.get('src') == 'remix' and key(dex[i]['n']) == k for i, v in mv.items())))
