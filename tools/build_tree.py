"""Route Defense — the Rescue Points tree (like BTD6 Monkey Knowledge): 8 branches of paths from a root; deeper nodes cost more.
Writes web/data/tree.json, read by both the HTML and Unity versions. Effects are small, permanent bonuses (nothing touches XP)."""
import json
ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII']
TYPES = ['Normal', 'Fighting', 'Flying', 'Poison', 'Ground', 'Rock', 'Bug', 'Ghost', 'Steel', 'Fire', 'Water', 'Grass', 'Electric', 'Psychic', 'Ice', 'Dragon', 'Dark', 'Fairy']
nodes = []
def cost(k, n):  # k = position in the path (1-based); deeper costs more, last node of long paths up to 8-10
    return [1, 2, 3, 4, 6, 8, 10, 10][min(k, 8) - 1] if n >= 4 else [2, 3, 4, 5][min(k, 4) - 1]
def branch(bid, name, root, paths, cap=None):
    nodes.append(dict(id=bid + '.root', br=bid, path='root', name=root[0], desc=root[1], cost=1, req=[], eff=root[2]))
    for pid, pname, n, fmt, eff in paths:
        prev = bid + '.root'
        for k in range(1, n + 1):
            nid = f'{bid}.{pid}{k}'
            nodes.append(dict(id=nid, br=bid, path=pname, name=f'{pname} {ROMAN[k - 1]}' if n > 1 else pname, desc=fmt, cost=cost(k, n), req=[prev], eff=eff))
            prev = nid
        if cap and cap[0] == pid:
            nodes.append(dict(id=f'{bid}.cap', br=bid, path=pname, name=cap[1], desc=cap[2], cost=10, req=[prev], eff=cap[3]))
BR = []
def B(bid, name, blurb): BR.append(dict(id=bid, name=name, blurb=blurb))

B('cash', 'Placement & Cash', 'Cheaper Pokémon, more starting cash, bigger wave bonuses.')
branch('cash', 'Placement & Cash', ('Team Basics', '+25 starting cash', {'startCash': 25}), [
    ('thr', 'Thrift', 6, 'Placing costs 2% less', {'placeCost': -0.02}),
    ('hs', 'Head Start', 6, '+20 starting cash', {'startCash': 20}),
    ('wp', 'Wave Pay', 5, '+10% cash for clearing a wave', {'waveBonus': 0.10}),
    ('kp', 'Knockout Pay', 4, '+5% cash per knockout', {'koCash': 0.05})])
B('battle', 'Battle Power', 'Range, attack speed, move power, critical hits.')
branch('battle', 'Battle Power', ('Battle Training', '+2% range', {'range': 0.02}), [
    ('rch', 'Long Reach', 6, '+2% range', {'range': 0.02}),
    ('qm', 'Quick Moves', 6, '+2% attack speed', {'atkSpeed': 0.02}),
    ('hh', 'Hard Hitter', 6, '+2% move power', {'power': 0.02}),
    ('se', 'Sharp Eye', 5, '+1% critical hit chance', {'crit': 0.01}),
    ('stab', 'Same-Type Focus', 4, 'Same-type bonus +0.03', {'stab': 0.03})],
    cap=('hh', "Champion's Spirit", '+5% move power', {'power': 0.05}))
B('weather', 'Weather & Field', 'Longer, stronger, cheaper weather; ponds and lava help their types.')
branch('weather', 'Weather & Field', ('Forecaster', 'Weather: every 3 of these = +1 wave', {'weatherDur': 0.10}), [
    ('lw', 'Long Weather', 5, 'Weather: every 3 of these = +1 wave', {'weatherDur': 0.10}),
    ('sw', 'Strong Weather', 4, 'Weather boosts +5% stronger', {'weatherPower': 0.05}),
    ('cs', 'Chip Storm', 4, 'Sandstorm / Hail chip damage +10%', {'weatherChip': 0.10}),
    ('pp', 'Pond Power', 3, 'Water / Fire Pokémon standing in water / lava attack 5% faster', {'pondSpeed': 0.05}),
    ('wb', 'Weather Bargain', 3, 'Weather costs 5% less', {'weatherCost': -0.05})])
B('recruit', 'Recruiting & Pokédex', 'Wild Pokémon ask to join a little more often; rarer finds.')
branch('recruit', 'Recruiting & Pokédex', ('Friend Area', 'Join chance +2%', {'recruit': 0.02}), [
    ('fa', 'Friendly Aura', 6, 'Join chance +3%', {'recruit': 0.03}),
    ('ht', 'Hidden Talent', 4, 'Hidden ability chance +2%', {'hidden': 0.02}),
    ('rf', 'Rare Finder', 4, 'Rare Pokémon show up 5% more', {'rare': 0.05}),
    ('bf', 'Boss Friend', 3, 'Bosses +1% more likely to ask to join', {'bossRecruit': 0.01})])
B('status', 'Status & Effects', 'Longer statuses, more added effects, stronger damage over time.')
branch('status', 'Status & Effects', ('Status Study', 'Statuses last 5% longer', {'statusDur': 0.05}), [
    ('lg', 'Lingering', 6, 'Statuses last 5% longer', {'statusDur': 0.05}),
    ('le', 'Lucky Effects', 6, 'Added effects 5% more likely', {'effChance': 0.05}),
    ('tt', 'Toxic Touch', 5, 'Burn / poison / trap damage +8%', {'dot': 0.08}),
    ('dd', 'Deep Drop', 4, 'Lowered stats last 10% longer', {'debuffDur': 0.10})])
B('types', 'Type Mastery', 'One path per type: stronger and faster moves of that type.')
nodes.append(dict(id='types.root', br='types', path='root', name='Type Knowledge', desc='+1% power for every type', cost=1, req=[], eff={'power': 0.01}))
for t, tn in enumerate(TYPES):
    a, b_, c = f'types.{t}a', f'types.{t}b', f'types.{t}c'
    nodes.append(dict(id=a, br='types', path=tn, name=f'{tn} Power I', desc=f'{tn} moves +3% power', cost=2, req=['types.root'], eff={f'tp{t}': 0.03}))
    nodes.append(dict(id=b_, br='types', path=tn, name=f'{tn} Power II', desc=f'{tn} moves +4% power', cost=3, req=[a], eff={f'tp{t}': 0.04}))
    nodes.append(dict(id=c, br='types', path=tn, name=f'{tn} Speed', desc=f'{tn}-type Pokémon attack 4% faster', cost=4, req=[b_], eff={f'ts{t}': 0.04}))
B('items', 'Evolution & Items', 'Cheaper shop, more item drops, rarer finds.')
branch('items', 'Evolution & Items', ('Item Bag', 'Shop prices 3% lower', {'shop': -0.03}), [
    ('bh', 'Bargain Hunter', 5, 'Shop prices 3% lower', {'shop': -0.03}),
    ('tf', 'Treasure Finder', 5, 'Held item drops 5% more likely', {'drop': 0.05}),
    ('rt', 'Rare Treasure', 3, 'Choice items / Life Orb / Expert Belt drop from 1 tier earlier', {'rareTier': -1}),
    ('sc', 'Stone Collector', 4, 'Evolution item drops 5% more likely', {'stone': 0.05})])
B('boss', 'Bosses & Legendaries', 'More damage to bosses, bigger boss rewards, legendary bosses.')
branch('boss', 'Bosses & Legendaries', ('Boss Study', '+3% damage to bosses', {'bossDmg': 0.03}), [
    ('bs', 'Boss Slayer', 6, '+3% damage to bosses', {'bossDmg': 0.03}),
    ('bo', 'Bounty', 5, '+10% ₽ when you beat a boss', {'bossPay': 0.10}),
    ('ls', 'Legend Seeker', 4, 'Legendary bosses 5% more likely (tier 5+)', {'legend': 0.05}),
    ('vl', 'Victory Lap', 3, '+4% ₽ for clearing a map', {'pay': 0.04})])

json.dump(dict(branches=BR, nodes=nodes), open('/home/claude/routedef/web/data/tree.json', 'w'), separators=(',', ':'), ensure_ascii=False)
tot = sum(n['cost'] for n in nodes)
print(len(nodes), 'nodes,', tot, 'points to fill;', {b['id']: sum(1 for n in nodes if n['br'] == b['id']) for b in BR})
