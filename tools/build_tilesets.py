"""Settings for random maps, from both PMD Red and Explorers of Sky (tilesets + auto-tile rules + music, all from the user's ROMs).
Ordered from easy to hard; later settings open as the player clears higher difficulty tiers."""
import json, shutil, os, subprocess, glob
from PIL import Image
RED='/home/claude/pmd/pmd_red_all_tilesets/'; EOS='/home/claude/eos_floors/dungeon_tilesets/'
RMUS='/home/claude/pmd/pmd_red_audio/music/'; EMUS='/home/claude/eos_music/eos_audio/music/'
OUT='/home/claude/routedef/web/'
T=dict(normal=0,fighting=1,flying=2,poison=3,ground=4,rock=5,bug=6,ghost=7,steel=8,fire=9,water=10,grass=11,electric=12,psychic=13,ice=14,dragon=15,dark=16,fairy=17)
RM={'Tiny Woods':125,'Purity Forest':121,'Howling Forest':15,'Uproar Forest':127,'Silent Chasm':113,'Remains Island':118,'Lightning Field':14,
'Desert Region':105,'Great Canyon':20,'Wish Cave':35,'Murky Cave':3,'Buried Relic':114,'Frosty Forest':104,'Lapis Cave':102,'Northern Range':36,
'Mt Steel':120,'Mt Thunder':111,'Magma Cavern':108,'Fiery Field':25,'Meteor Cave':37,'Wyvern Hill':28,'Sky Tower':22,'Mt Freeze':115,'Southern Cavern':31}
EM={'Apple Woods':25,'Beach Cave':21,'Tiny Meadow':156,'Mt Bristle':23,'Lush Prairie':176,'Amp Plains':32,'Craggy Coast':26,'Mt Horn':28,'Foggy Forest':29,
'Oran Forest':155,'Steam Cave':30,'Northern Desert':34,'Serenity River':98,'Crystal Cave':37,'Brine Cave':46,'Dark Hill':40,'Sealed Ruin':41,
'Landslide Cave':139,'Southern Jungle':96,'Mystery Jungle':97,'Dusk Forest':43,'Treeshroud Forest':61,'Limestone Cavern':143,'Shimmer Desert':35,
'Murky Forest':94,'Mt Travail':58,'Blizzard Island':53,'Mystifying Forest':52,'Rock Aegis Cave':56,'Icicle Forest':152,'Mt Avalanche':157,
'Inferno Cave':63,'Mt Mistral':158,'Dark Crater':62,'Giant Volcano':31,'Temporal Tower':50,'Temporal Spire':51}
S=[('R','Tiny Woods',14,'grass bug normal'),('E','Apple Woods',5,'grass bug normal'),('E','Beach Cave',1,'water rock bug'),
('E','Tiny Meadow',65,'normal grass flying'),('R','Uproar Forest',52,'normal fighting grass'),('E','Mt Bristle',3,'normal flying rock'),
('R','Silent Chasm',2,'bug ground poison'),('E','Lush Prairie',90,'normal grass fairy'),('E','Amp Plains',14,'electric normal steel'),
('R','Lightning Field',29,'electric steel normal'),('E','Craggy Coast',6,'water rock'),('R','Remains Island',6,'water rock normal'),
('E','Mt Horn',8,'rock ground normal'),('E','Foggy Forest',10,'normal ghost grass'),('E','Oran Forest',105,'grass bug normal'),
('E','Steam Cave',12,'fire ground'),('R','Desert Region',21,'ground rock fire'),('E','Northern Desert',17,'ground bug'),
('R','Wish Cave',3,'fairy psychic normal'),('E','Serenity River',96,'water grass'),('R','Howling Forest',51,'normal dark grass'),
('E','Crystal Cave',22,'rock psychic ice'),('R','Great Canyon',44,'ground flying fighting'),('E','Brine Cave',39,'water poison'),
('R','Murky Cave',4,'dark ghost poison'),('E','Dark Hill',28,'ghost dark'),('R','Frosty Forest',36,'ice grass bug'),
('E','Sealed Ruin',30,'rock ghost'),('R','Lapis Cave',45,'water ice dark'),('E','Landslide Cave',103,'rock ground fighting'),
('R','Buried Relic',17,'rock ghost psychic'),('E','Southern Jungle',44,'grass bug poison'),('R','Northern Range',34,'ice rock flying'),
('E','Mystery Jungle',61,'grass bug fighting'),('R','Mt Steel',39,'steel fighting rock'),('E','Dusk Forest',33,'dark grass poison'),
('R','Mt Thunder',42,'electric flying normal'),('E','Treeshroud Forest',37,'grass psychic bug'),('E','Limestone Cavern',130,'water rock'),
('R','Magma Cavern',48,'fire rock ground'),('E','Shimmer Desert',85,'ground fire'),('E','Murky Forest',128,'poison dark bug'),
('R','Southern Cavern',55,'rock ground steel'),('E','Mt Travail',53,'fighting rock'),('R','Fiery Field',59,'fire fighting dragon'),
('E','Blizzard Island',88,'ice water'),('R','Meteor Cave',28,'psychic fairy rock'),('E','Mystifying Forest',48,'fairy psychic grass'),
('E','Rock Aegis Cave',49,'rock steel'),('R','Mt Freeze',47,'ice water steel'),('E','Icicle Forest',139,'ice grass'),
('E','Mt Avalanche',111,'ice flying'),('E','Inferno Cave',110,'fire'),('R','Purity Forest',11,'grass bug fairy'),
('R','Wyvern Hill',10,'dragon flying grass'),('E','Mt Mistral',119,'flying normal electric'),('E','Dark Crater',57,'fire dark'),
('E','Giant Volcano',123,'fire rock dragon'),('R','Sky Tower',35,'flying dragon psychic'),('E','Temporal Tower',45,'psychic steel dragon'),
('E','Temporal Spire',135,'dragon steel psychic')]
# ---- the rest of PMD Red's dungeon tilesets: name, types and music all come from the ROM's floor and spawn data ----
import re, collections
RA='/home/claude/pmd/pmd_red_all_tilesets/'; PD='/home/claude/pmd/pmd_red_data/'
FL=json.load(open(PD+'floors.json')); SPN=json.load(open(PD+'dungeon_spawns.json')); CR={c['name']:c for c in json.load(open(PD+'creatures.json'))}
used={n for g,_,n,_ in S if g=='R'}
def fnum(x): m=re.match(r'B?(\d+)F',x.strip()); return int(m.group(1)) if m else None
def frange(t):
    a,_,b=t.partition('-'); a=fnum(a); b=fnum(b) if b else a
    return (a,b) if a is not None and b is not None else (999,-1)   # odd labels in the dump match no floor
def avglv(dname, floors):
    l=[(sp['level'],sp['chance_percent']) for sp in SPN if sp['dungeon']==dname and any(frange(sp['floors'])[0]<=f<=frange(sp['floors'])[1] for f in floors)]
    return sum(a*b for a,b in l)/max(1e-9,sum(b for a,b in l)) if l else None
def info(n, prefer=None):
    fl=[f for f in FL if f['tileset']==n]
    by=collections.defaultdict(list)
    for f in fl: by[f['dungeon']].append(f['floor'])
    cand=[d for d in by if d!='Dojo Registration'] or list(by)
    d=prefer if prefer in by else max(cand,key=lambda k:len(by[k])); floors=sorted(by[d])
    return d, floors, collections.Counter(f['music'] for f in fl if f['dungeon']==d).most_common(1)[0][0]
# the ROM's own table (at 0xF5668): floor music number -> song number (= the music file's number)
import struct
_rom=open('/home/claude/pmd/rom.gba','rb').read(); MUSTAB=[struct.unpack_from('<H',_rom,0xF5668+i*2)[0] for i in range(80)]
FILLER={i for i in range(80) if MUSTAB[i]==125 and i!=1}   # unused slots are filled with 125; a floor pointing at one is flagged, not trusted
names=collections.Counter()
EXTRA=[]; skipped=[]
for n in range(64):
    if n in used: continue
    d,floors,mi=info(n) if any(f['tileset']==n for f in FL) else (None,None,None)
    if d is None: continue                        # tilesets no floor uses
    tw=collections.Counter()
    for sp in SPN:
        if sp['dungeon']!=d: continue
        a,b=frange(sp['floors'])
        if a is None or not any(a<=f<=b for f in floors): continue
        c=CR.get(sp['creature'])
        if not c: continue
        for t in (c['type1'],c['type2']):
            if t: tw[t.lower()]+=sp['chance_percent']
    types=[t for t,_ in tw.most_common(3)]
    track=MUSTAB[mi] if mi not in FILLER else None
    if not types or not track: skipped.append((n,d,'types' if not types else 'music')); continue
    nm=d if not any(x[1]==d for x in S) and d not in [e['name'] for e in EXTRA] else f"{d} {floors[0]}F-{floors[-1]}F" if floors[0]!=floors[-1] else f"{d} {floors[0]}F"
    EXTRA.append(dict(n=n,name=nm,types=' '.join(types),track=track,lv=avglv(d,floors)))
print(len(EXTRA),'extra PMD Red settings; skipped',skipped)
# put each new one right after the existing PMD Red setting whose wild Pokémon are closest in level
lvR={}
for g,name,n,_ in S:
    if g=='R': d,fs,_m=info(n, name); lvR[name]=avglv(d,fs) or 0
base=lambda nm: re.sub(r' \d+F(-\d+F)?$','',nm)
def fstart(nm, n):
    m=re.search(r' (\d+)F(-\d+F)?$',nm)
    if m: return int(m.group(1))
    d,fs,_=info(n, base(nm)); return fs[0]
# dungeons the game didn't have: placed by wild level; tilesets of a dungeon it already has: next to it, in floor order
for e in sorted([e for e in EXTRA if not any(base(x[1])==base(e['name']) for x in S)],key=lambda e:-(e['lv'] or 0)):
    if any(base(x[1])==base(e['name']) for x in S): continue
    best=min(lvR,key=lambda k:abs(lvR[k]-(e['lv'] or 0)))
    i=[x[1] for x in S].index(best); S.insert(i+1,('R',e['name'],e['n'],e['types'])); RM[e['name']]=e['track']; e['done']=1
for e in sorted([e for e in EXTRA if not e.get('done')],key=lambda e:fstart(e['name'],e['n'])):
    grp=[k for k,x in enumerate(S) if x[0]=='R' and base(x[1])==base(e['name'])]
    if not grp:
        best=min(lvR,key=lambda k:abs(lvR[k]-(e['lv'] or 0))); i=[x[1] for x in S].index(best)
    else:
        fs=fstart(e['name'],e['n']); before=[k for k in grp if fstart(S[k][1],S[k][2])<=fs]
        i=before[-1] if before else grp[0]-1
    S.insert(i+1,('R',e['name'],e['n'],e['types'])); RM[e['name']]=e['track']
os.makedirs(OUT+'img/ts',exist_ok=True); os.makedirs(OUT+'snd',exist_ok=True)
for f in glob.glob(OUT+'img/ts/*.png'): os.remove(f)
snd=json.load(open(OUT+'data/snd.json'))
def mus(src,key):
    o=OUT+f'snd/{key}.mp3'
    if not os.path.exists(o): subprocess.run(['ffmpeg','-y','-loglevel','error','-i',src,'-ac','1','-b:a','56k',o])
    return key
out=[]; CHANGED=[]
for g,name,n,types in S:
    base=RED if g=='R' else EOS
    d=[x for x in os.listdir(base) if x.startswith('tileset_%02d_'%n) or x.startswith('tileset_%03d_'%n) or x in ('tileset_%02d'%n,'tileset_%03d'%n)][0]
    if g=='R': r=json.load(open(base+d+'/tileset.json'))['autotile']['rules']; src=base+d+'/blocks.png'; cols=10
    else: r=json.load(open(base+d+'/tileset.json'))['rules']; src=base+d+'/all_chunks.png'; cols=16
    key=f'{g.lower()}{n}'; shutil.copy(src,OUT+f'img/ts/{key}.png')
    im=Image.open(src).convert('RGBA'); bi=r[(255+256)*3]
    blk=im.crop((bi%cols*24,bi//cols*24,bi%cols*24+24,bi//cols*24+24)).resize((1,1),Image.BOX).getpixel((0,0))
    liq='lava' if blk[0]>blk[2]+40 else 'water' if blk[2]>blk[0]+15 else 'chasm'
    if g=='R':
        _d,_f,_mi=info(n, name.split(' ')[0] and next((k for k in [name, re.sub(r' \d+F(-\d+F)?$','',name)] if any(f['dungeon']==k for f in FL)), None)); tr=MUSTAB[_mi] if _mi not in FILLER else RM[name]
        if tr!=RM.get(name): CHANGED.append((name,RM.get(name),tr))
        m=glob.glob(RMUS+'%03d *.mp3'%tr)[0]; mk=mus(m,'m%d'%tr)
    else: m=glob.glob(EMUS+'%03d *.mp3'%EM[name])[0]; mk=mus(m,'e%d'%EM[name])
    snd['music'][name]=mk
    out.append(dict(name=name,game=g,ts=key,cols=cols,types=[T[t] for t in types.split()],liq=liq,rules=r))
for k,n in (('_eboss',15),('_elegend',18),('_ewin',20),('_elose',19)):
    snd['music'][k]=mus(glob.glob(EMUS+'%03d *.mp3'%n)[0],'e%d'%n)
json.dump(out,open(OUT+'data/ts.json','w'),separators=(',',':')); json.dump(snd,open(OUT+'data/snd.json','w'))
print(len(out),'settings', sum(os.path.getsize(OUT+'snd/'+f) for f in os.listdir(OUT+'snd'))//1048576,'MB audio')
print('music fixed:',CHANGED)
