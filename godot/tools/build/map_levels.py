import json, glob, re, struct, os
# ---- PMD Red: floor-weighted average wild level per dungeon (pmd-red decomp tables; table names carry their floors)
R={}
for d in sorted(glob.glob('/tmp/pmdred/data/dungeon/*/pokemon_found.json')):
    nm=os.path.basename(os.path.dirname(d)); T=json.load(open(d))['tables']
    tot=0; n=0; mx=0
    for t in T:
        fl=[int(x) for x in re.findall(r'(\d+)F', t['name'])]
        span=(fl[-1]-fl[0]+1) if fl else 1
        ps=[p for p in t['pokemon'] if p['probability']>0]
        if not ps: continue
        a=sum(p['level']*p['probability'] for p in ps)/sum(p['probability'] for p in ps)
        tot+=a*span; n+=span; mx=max(mx,a)
    if n: R[nm]=(round(tot/n,1), round(mx,1), n)
# ---- Explorers of Sky: mappa_s monster lists (level = raw / 512), floor-weighted
E='/tmp/pf_work/eos/'
arm9=open(E+'arm9.bin','rb').read(); mp=open(E+'fs/BALANCE/mappa_s.bin','rb').read()
st=open(E+'fs/MESSAGE/text_e.str','rb').read(); n0=struct.unpack_from('<I',st,0)[0]//4
offs=[struct.unpack_from('<I',st,4*i)[0] for i in range(n0)]
S=[st[o:(st.find(b'\0',o) if st.find(b'\0',o)>=0 else len(st))].decode('cp1252','replace') for o in offs]
u32=lambda o: struct.unpack_from('<I',mp,o)[0]
hdr=u32(4); dl,fl,il,ml,tl=struct.unpack_from('<5I',mp,hdr)
def floors_of(mi):
    p=u32(dl+4*mi)+18; out=[]
    while mp[p:p+18]!=bytes(18) and p<dl: out.append(struct.unpack_from('<9H',mp,p)); p+=18
    return out
def mlist(i):
    p=u32(ml+4*i); out=[]
    while True:
        lv,w1,w2,md=struct.unpack_from('<4H',mp,p); p+=8
        if md==0: break
        out.append((lv//512,w1,md))
    return out
Eo={}
for did in range(180):
    name=S[16564+did]; nf,mi,sf,tot=arm9[0x9E3A0+4*did:0x9E3A0+4*did+4]
    fls=floors_of(mi)[sf:sf+nf]; acc=0; c=0; mx=0
    for f in fls:
        L=mlist(f[1]); prev=0; ws=[]
        for lv,w,md in L: ws.append((lv,w-prev if w>=prev else 0)); prev=max(prev,w)
        sw=sum(w for _,w in ws)
        if sw<=0: continue
        a=sum(l*w for l,w in ws)/sw; acc+=a; c+=1; mx=max(mx,a)
    if c and name not in Eo: Eo[name]=(round(acc/c,1), round(mx,1), c)
json.dump({'R':R,'E':Eo},open('/tmp/eosd/levels.json','w'),indent=0)
for k in ['WishCave','TinyWoods','PurityForest','SkyTower','WesternCave','UproarForest']: print('R',k,R.get(k))
for k in ['Beach Cave','Temporal Tower','Mystery Jungle','Giant Volcano','Dark Crater','Tiny Meadow']: print('E',k,Eo.get(k))
