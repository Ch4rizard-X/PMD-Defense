import csv, json
P='/tmp/pokeapi/data/v2/csv/'
R=lambda n: list(csv.DictReader(open(P+n+'.csv')))
mv={int(r['id']):r for r in R('moves')}; meta={int(r['move_id']):r for r in R('move_meta')}
ail={int(r['id']):r['identifier'] for r in R('move_meta_ailments')}
sc={}
for r in R('move_meta_stat_changes'): sc.setdefault(int(r['move_id']),[]).append([int(r['stat_id']),int(r['change'])])
names={int(r['move_id']):r['name'] for r in R('move_names') if r['local_language_id']=='9'}
i=lambda x,d=0: int(x) if x not in ('',None) else d
def conv(m):
    r=mv[m]; me=meta.get(m,{})
    return {'n':names.get(m,r['identifier']),'t':int(r['type_id'])-1,'p':i(r['power']),'pp':i(r['pp']),'a':i(r['accuracy']),'c':int(r['damage_class_id']),
      'tg':int(r['target_id']),'pr':int(r['priority']),'ai':ail.get(i(me.get('meta_ailment_id'),0),'none'),'ac':i(me.get('ailment_chance')),
      'h':[i(me.get('min_hits'),1),i(me.get('max_hits'),1)],'dr':i(me.get('drain')),'hl':i(me.get('healing')),'cr':i(me.get('crit_rate')),
      'fl':i(me.get('flinch_chance')),'cat':i(me.get('meta_category_id')),'sc':sc.get(m,[]),'sch':i(me.get('stat_chance'))}
D=json.load(open('/tmp/tm_dump.json'))
bad=0; n=0
for k,v in D['moves'].items():
    k=int(k)
    if k not in mv: continue
    c=conv(k); n+=1
    diff={f:(v.get(f),c[f]) for f in c if v.get(f)!=c[f]}
    if diff:
        bad+=1
        if bad<6: print(k,diff)
print('checked',n,'differ',bad)

# ---- TM / HM learnsets: each Pokémon's newest game that teaches it anything by machine (method 4)
vg={int(r['id']):int(r['order']) for r in R('version_groups')}; vgn={int(r['id']):r['identifier'] for r in R('version_groups')}
L={}
for r in R('pokemon_moves'):
    if r['pokemon_move_method_id']!='4': continue
    L.setdefault(int(r['pokemon_id']),{}).setdefault(int(r['version_group_id']),set()).add(int(r['move_id']))
mon=set(int(x) for x in D['mon'])
species_of={int(r['id']):int(r['species_id']) for r in R('pokemon')}
default_of={}
for r in R('pokemon'):
    if r['is_default']=='1': default_of[int(r['species_id'])]=int(r['id'])
out={}; latest={}; miss=[]
for pid in sorted(mon):
    src=pid if pid in L else default_of.get(species_of.get(pid,-1))   # a form with no own list: its species' default
    if src not in L: miss.append(pid); continue
    best=max(L[src],key=lambda g: vg[g]); out[pid]=sorted(L[src][best]); latest[vgn[best]]=latest.get(vgn[best],0)+1
used=sorted({m for v in out.values() for m in v})
have={int(k) for k in D['moves']}
new={m:conv(m) for m in used if m not in have}
print('species with TMs',len(out),'without',len(miss),miss[:20])
print('latest games',sorted(latest.items(),key=lambda x:-x[1])[:12])
print('TM moves',len(used),'new moves',len(new))
json.dump({'ls':{str(k):v for k,v in out.items()},'moves':{str(k):v for k,v in new.items()}},open('/tmp/tm/tm.json','w'))
