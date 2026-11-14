"""Move effects from the user's PMD Red ROM (already extracted): for each move, the projectile and the hit animation.
Moves PMD Red doesn't have (later generations) borrow the effect of a PMD move with the same type and kind."""
import csv, json, os, re, shutil
from PIL import Image
FX='/home/claude/pmd/pmd_red_effects/'; OUT='/home/claude/routedef/web/'
dex=json.load(open(OUT+'data/dex.json'))
norm=lambda s: re.sub(r'[^a-z0-9]','',s.lower())
rows={norm(r['move']):r for r in csv.DictReader(open(FX+'moves.csv'))}
anims={}
def anim(ref):
    if not ref or '/' not in ref: return None
    if ref in anims: return ref
    d,a=ref.split('/'); png=FX+f'effects/{d}/{a}.png'; gif=FX+f'effects/{d}/{a}_preview.gif'
    if not os.path.exists(png) or not os.path.exists(gif): return None
    g=Image.open(gif); n=getattr(g,'n_frames',1); du=[]
    for i in range(n): g.seek(i); du.append(max(1,round(g.info.get('duration',33)*60/1000)))
    im=Image.open(png); fw=im.width//n; fh=g.height//2
    if fh<=0 or im.height%fh: fh=im.height
    rows_=max(1,im.height//fh)
    if im.getbbox() is None: return None
    shutil.copy(png,OUT+f'img/fx/{d}_{a}.png')
    anims[ref]=dict(f=f'{d}_{a}',fw=fw,fh=fh,n=n,r=rows_,d=du); return ref
mv={}
for mid,m in dex['moves'].items():
    r=rows.get(norm(m['n']))
    if not r: continue
    e=dict(b=int(r['attacker_body_anim'] or 99))
    for k,c in (('u','2_on_user'),('p','3_travelling'),('h','4_on_target')):
        a=anim(r[c])
        if a: e[k]=a
    if len(e)>1: mv[int(mid)]=e
# borrow for the rest: same type + damage class, most common effect set among PMD moves
by={}
for mid,e in mv.items():
    m=dex['moves'][str(mid)]; by.setdefault((m['t'],m['c'],'p' in e),[]).append(e)
fill=0
for mid,m in dex['moves'].items():
    if int(mid) in mv: continue
    ranged=m['c']==3
    c=by.get((m['t'],m['c'],ranged)) or by.get((m['t'],m['c'],not ranged)) or by.get((m['t'],3,True)) or by.get((0,2,False))
    if c: mv[int(mid)]=dict(c[(int(mid)*7)%len(c)],borrowed=1); fill+=1
json.dump(dict(anims=anims,moves=mv),open(OUT+'data/fx.json','w'),separators=(',',':'))
tot=sum(os.path.getsize(OUT+'img/fx/'+f) for f in os.listdir(OUT+'img/fx'))
print(len(mv),'moves with effects (',fill,'borrowed);',len(anims),'anims',tot//1024,'KB')
print(anims[mv[52]['p']], anims[mv[52]['h']])
