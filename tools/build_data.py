"""Route Defense data: every Pokémon's real stats, types, evolutions, level-up moves and catch rate, from PokeAPI's CSVs."""
import csv, json, os
C='/home/claude/pokeapi/data/v2/csv/'; SC='/home/claude/spritecollab/sprite/'
R=lambda f: list(csv.DictReader(open(C+f+'.csv',encoding='utf-8')))
I=lambda v: int(v) if v not in ('',None) else None
sp={int(r['id']):r for r in R('pokemon_species')}
names={int(r['pokemon_species_id']):r['name'] for r in R('pokemon_species_names') if r['local_language_id']=='9'}
mon={int(r['species_id']):r for r in R('pokemon') if r['is_default']=='1'}
pid2sp={int(r['id']):int(r['species_id']) for r in mon.values()}
stats={};types={}
for r in R('pokemon_stats'):
    p=int(r['pokemon_id'])
    if p in pid2sp: stats.setdefault(pid2sp[p],[0]*6)[int(r['stat_id'])-1]=int(r['base_stat'])
for r in R('pokemon_types'):
    p=int(r['pokemon_id'])
    if p in pid2sp: types.setdefault(pid2sp[p],{})[int(r['slot'])]=int(r['type_id'])-1
evo={}
for r in R('pokemon_evolution'):
    t=int(r['evolved_species_id']); f=I(sp[t]['evolves_from_species_id'])
    if not f or r['is_default']=='0': continue
    e=dict(to=t,tr=int(r['evolution_trigger_id']))
    if r['minimum_level']: e['lv']=int(r['minimum_level'])
    if r['trigger_item_id']: e['item']=int(r['trigger_item_id'])
    if r['minimum_happiness']: e['happy']=1
    if r['known_move_id'] or r['known_move_type_id']: e['move']=1
    lst=evo.setdefault(f,[])
    if not any(x['to']==t for x in lst): lst.append(e)
vg_order={int(r['id']):int(r['order']) for r in R('version_groups')}
learn={}
for r in R('pokemon_moves'):
    if r['pokemon_move_method_id']!='1': continue
    p=int(r['pokemon_id'])
    if p not in pid2sp: continue
    s=pid2sp[p]; vg=int(r['version_group_id'])
    learn.setdefault(s,{}).setdefault(vg,set()).add((int(r['level']),int(r['move_id'])))
mvn={int(r['move_id']):r['name'] for r in R('move_names') if r['local_language_id']=='9'}
meta={int(r['move_id']):r for r in R('move_meta')}
ail={int(r['id']):r['identifier'] for r in R('move_meta_ailments')}
moves={int(r['id']):r for r in R('moves')}
stc={}
for r in R('move_meta_stat_changes'): stc.setdefault(int(r['move_id']),[]).append([int(r['stat_id']),int(r['change'])])
used=set(); D=[]
for s in sorted(sp):
    if s>10000: continue
    L=learn.get(s,{})
    best=max(L,key=lambda v:(vg_order[v] if len(L[v])>=3 else -1)) if L else None
    ls=sorted(L[best]) if best else []
    ls=[[max(1,l),m] for l,m in ls if m in moves]
    for _,m in ls: used.add(m)
    folder='%04d'%s
    D.append(dict(id=s,n=names.get(s,sp[s]['identifier']),t=[types[s][k] for k in sorted(types[s])],b=stats[s],
        cr=int(sp[s]['capture_rate']),g=int(sp[s]['generation_id']),gr=int(sp[s]['growth_rate_id']),
        x=I(mon[s]['base_experience']) or 60,f=I(sp[s]['evolves_from_species_id']),ev=evo.get(s,[]),
        lg=1 if sp[s]['is_legendary']=='1' else (2 if sp[s]['is_mythical']=='1' else 0),bb=1 if sp[s]['is_baby']=='1' else 0,
        spr=1 if os.path.exists(SC+folder+'/AnimData.xml') else 0,ls=ls))
M={}
for m in sorted(used):
    r=moves[m]; mt=meta.get(m,{})
    M[m]=dict(n=mvn.get(m,r['identifier']),t=int(r['type_id'])-1,p=I(r['power']) or 0,pp=I(r['pp']) or 10,a=I(r['accuracy']) or 0,
        c=int(r['damage_class_id']),tg=int(r['target_id']),pr=int(r['priority']),
        ai=ail.get(I(mt.get('meta_ailment_id')) or 0,'none'),ac=I(mt.get('ailment_chance')) or 0,
        h=[I(mt.get('min_hits')) or 1,I(mt.get('max_hits')) or 1],dr=I(mt.get('drain')) or 0,hl=I(mt.get('healing')) or 0,
        cr=I(mt.get('crit_rate')) or 0,fl=I(mt.get('flinch_chance')) or 0,cat=I(mt.get('meta_category_id')) or 0,sc=stc.get(m,[]),sch=I(mt.get('stat_chance')) or 0)
T=[[1]*18 for _ in range(18)]
for r in R('type_efficacy'):
    a,b=int(r['damage_type_id'])-1,int(r['target_type_id'])-1
    if a<18 and b<18: T[a][b]=int(r['damage_factor'])/100
XP={}
for r in R('experience'): XP.setdefault(int(r['growth_rate_id']),[0]*101)[int(r['level'])]=int(r['experience'])
TN=[r['identifier'] for r in R('types')][:18]
inames={int(r['item_id']):r['name'] for r in R('item_names') if r['local_language_id']=='9'}
items={e['item']:inames.get(e['item']) for d in D for e in d['ev'] if 'item' in e}
# abilities (real per-species slots, hidden flagged) and the held items the game uses
pab={}
for r in R('pokemon_abilities'):
    p_=int(r['pokemon_id'])
    if p_ in pid2sp: pab.setdefault(pid2sp[p_],[]).append([int(r['ability_id']),int(r['is_hidden'])])
for d in D: d['ab']=pab.get(d['id'],[])
abn={int(r['ability_id']):r['name'] for r in R('ability_names') if r['local_language_id']=='9'}
abp={int(r['ability_id']):r['short_effect'] for r in R('ability_prose') if r['local_language_id']=='9'}
abk={int(r['id']):r['identifier'] for r in R('abilities')}
usedab={a for d in D for a,_ in d['ab']}
AB={a:dict(k=abk[a],n=abn.get(a,abk[a]),d=abp.get(a,'')) for a in sorted(usedab)}
HELD='choice-band choice-specs choice-scarf life-orb expert-belt scope-lens razor-claw wide-lens zoom-lens quick-claw kings-rock razor-fang muscle-band wise-glasses charcoal mystic-water miracle-seed magnet never-melt-ice black-belt poison-barb soft-sand sharp-beak twisted-spoon silver-powder hard-stone spell-tag dragon-fang black-glasses metal-coat silk-scarf fairy-feather light-clay binding-band lucky-egg amulet-coin metronome'.split()
itk={r['identifier']:int(r['id']) for r in R('items')}
itp={int(r['item_id']):r['short_effect'] for r in R('item_prose') if r['local_language_id']=='9'}
HI={}
for k in HELD:
    if k in itk: i=itk[k]; HI[i]=dict(k=k,n=inames.get(i,k),d=itp.get(i,''))
    else: print('missing item',k)
# natures (stat index 0 HP .. 5 Speed; up == dn means neutral) and the real items that change them / IVs
natn={int(r['nature_id']):r['name'] for r in R('nature_names') if r['local_language_id']=='9'}
NAT=[dict(id=int(r['id']),k=r['identifier'],n=natn.get(int(r['id']),r['identifier']),up=int(r['increased_stat_id'])-1,dn=int(r['decreased_stat_id'])-1) for r in R('natures')]
TOOLS={}
for n in NAT:
    k=n['k']+'-mint'
    if k in itk: TOOLS[itk[k]]=dict(k=k,n=inames.get(itk[k],k),d=itp.get(itk[k],''),kind='mint',nat=n['id'])
for k in ('bottle-cap','gold-bottle-cap'): TOOLS[itk[k]]=dict(k=k,n=inames.get(itk[k],k),d=itp.get(itk[k],''),kind=k)
print(len(NAT),'natures',len(TOOLS),'tools')
out=dict(mon=D,moves=M,types=TN,chart=T,xp=XP,items=items,abil=AB,held=HI,nat=NAT,tools=TOOLS)
json.dump(out,open('/home/claude/routedef/web/data/dex.json','w'),separators=(',',':'),ensure_ascii=False)
print(len(D),'species',sum(d['spr'] for d in D),'with sprites',len(M),'moves',os.path.getsize('/home/claude/routedef/web/data/dex.json')//1024,'KB')
print([ (d['n'],d['ev']) for d in D if d['id'] in (1,133,64,25,265)])
