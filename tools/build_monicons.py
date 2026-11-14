"""One small icon atlas: the first idle frame of every Pokémon, trimmed and centred in a 40x40 cell (used by the Pokédex and cards so
they don't have to decode each full sprite sheet). Writes web/img/ui/monicons.png and web/data/micons.json {id: index}."""
import json
from PIL import Image
W='/home/claude/routedef/web/'; C=40; COLS=32
anim=json.load(open(W+'data/anim.json')); ids=sorted(int(k) for k in anim)
rows=(len(ids)+COLS-1)//COLS; atlas=Image.new('RGBA',(COLS*C,rows*C)); idx={}
for n,i in enumerate(ids):
    a=anim[str(i)]; m=a.get('Idle') or a.get('Walk'); im=Image.open(W+'img/mon/%04d.webp'%i).convert('RGBA')
    fr=im.crop((0,m['y'],m['fw'],m['y']+m['fh'])); bb=fr.getbbox()
    if bb: fr=fr.crop(bb)
    if max(fr.size)>C: s=C/max(fr.size); fr=fr.resize((max(1,round(fr.width*s)),max(1,round(fr.height*s))),Image.NEAREST)
    x=(n%COLS)*C+(C-fr.width)//2; y=(n//COLS)*C+(C-fr.height)
    atlas.alpha_composite(fr,(x,y)); idx[i]=n
atlas.save(W+'img/ui/monicons.png',optimize=True); json.dump({'cols':COLS,'c':C,'i':idx},open(W+'data/micons.json','w'),separators=(',',':'))
import os; print(len(idx),'icons',atlas.size,os.path.getsize(W+'img/ui/monicons.png')//1024,'KB')
