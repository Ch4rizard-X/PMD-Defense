"""Item icons: PMD Red's own icon where the ROM has one, otherwise the main-series bag sprite (PokeAPI sprites).
Writes web/img/item/<identifier>.png and web/data/icons.json {item id: identifier}."""
import csv, json, os, shutil
W = '/home/claude/routedef/web/'; PMD = '/home/claude/pmd/pmd_red_icons/items/'; BAG = '/home/claude/pokesprites/sprites/items/'
os.makedirs(W + 'img/item', exist_ok=True)
it = {int(r['id']): r['identifier'] for r in csv.DictReader(open('/home/claude/pokeapi/data/v2/csv/items.csv'))}
dex = json.load(open(W + 'data/dex.json'))
ids = [int(k) for k in dex['items']] + [int(k) for k in dex['held']] + [int(k) for k in dex['tools']]
PMDMAP = {'thunder-stone': 'Thunderstone', 'sun-stone': 'Sun_Stone', 'moon-stone': 'Moon_Stone', 'fire-stone': 'Fire_Stone', 'water-stone': 'Water_Stone',
          'leaf-stone': 'Leaf_Stone', 'metal-coat': 'Metal_Coat', 'kings-rock': 'King_s_Rock', 'dragon-scale': 'Dragon_Scale', 'up-grade': 'Upgrade',
          'deep-sea-scale': 'Deepseascale', 'deep-sea-tooth': 'Deepseatooth', 'scope-lens': 'Scope_Lens', 'link-cable': 'Link_Cable'}
pmdfiles = {f.split('_', 1)[1][:-4]: f for f in os.listdir(PMD) if '_' in f}
out, src = {}, {'pmd': 0, 'bag': 0}
for i in ids:
    k = it[i]
    if k in PMDMAP and PMDMAP[k] in pmdfiles and False: shutil.copy(PMD + pmdfiles[PMDMAP[k]], W + f'img/item/{k}.png'); src['pmd'] += 1   # user chose main-series bag sprites for every item
    elif os.path.exists(BAG + k + '.png'): shutil.copy(BAG + k + '.png', W + f'img/item/{k}.png'); src['bag'] += 1
    else: print('no icon', k); continue
    out[i] = k
json.dump(out, open(W + 'data/icons.json', 'w'), separators=(',', ':'))
print(len(out), 'icons', src)
