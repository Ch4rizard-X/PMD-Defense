"""Pack each Pokémon's SpriteCollab animations (Idle, Walk, Attack, Shoot, Hurt; 8 directions) into one sheet + metadata."""
import os, json, xml.etree.ElementTree as ET
from multiprocessing import Pool
from PIL import Image
SC='/home/claude/spritecollab/sprite/'; OUT='/home/claude/routedef/web/img/mon/'
WANT=['Idle','Walk','Attack','Shoot','Hurt','Hover']
OPTIONAL={'Hover'}   # only packed when the sheet has them (no stand-ins)
def one(folder):
    p=SC+folder+'/'
    try: root=ET.parse(p+'AnimData.xml').getroot()
    except Exception: return None
    A={}
    for a in root.iter('Anim'):
        A[a.findtext('Name')]=a
    def res(n,depth=0):
        a=A.get(n)
        if a is None or depth>4: return None,None
        c=a.findtext('CopyOf')
        return res(c,depth+1) if c else (n,a)
    parts=[];meta={}
    for n in WANT:
        src,a=res(n)
        if a is None and n=='Hover':
            # no Hover: use FlapAround's own frames that face each row's direction (it spins through the 8 directions,
            # a group of frames per direction, so the first group of every row is that direction flapping)
            s2,fa=res('FlapAround')
            if fa is not None and os.path.exists(p+s2+'-Anim.png'):
                im=Image.open(p+s2+'-Anim.png').convert('RGBA'); fw,fh=int(fa.findtext('FrameWidth')),int(fa.findtext('FrameHeight'))
                nf=im.width//fw; rows=im.height//fh; per=nf//8 if nf%8==0 else (nf-2)//8
                if per>=2 and rows==8:
                    du=[int(d.text) for d in fa.iter('Duration')][:per]
                    strip=Image.new('RGBA',(per*fw,rows*fh)); strip.paste(im.crop((0,0,per*fw,rows*fh)),(0,0))
                    meta[n]=dict(fw=fw,fh=fh,n=per,r=rows,d=du,hit=0,y=0,src='FlapAround')
                    sf=p+s2+'-Shadow.png'
                    if os.path.exists(sf):
                        sh=Image.open(sf).convert('RGBA'); pts=[]
                        for r_ in range(rows):
                            box=sh.crop((0,r_*fh,fw,r_*fh+fh)).getchannel('A').point(lambda v:255 if v else 0); bb=box.getbbox()
                            pts.append([round((bb[0]+bb[2])/2,1),round((bb[1]+bb[3])/2,1)] if bb else [fw/2,fh/2])
                        meta[n]['sh']=pts
                    parts.append((n,strip))
            continue
        if a is None and n in OPTIONAL: continue
        if a is None:
            src,a=res('Attack' if n=='Shoot' else 'Idle' if n!='Walk' else 'Walk')
            if a is None: continue
        f=p+src+'-Anim.png'
        if not os.path.exists(f): continue
        im=Image.open(f).convert('RGBA'); fw,fh=int(a.findtext('FrameWidth')),int(a.findtext('FrameHeight'))
        du=[int(d.text) for d in a.iter('Duration')]
        nf=im.width//fw; rows=im.height//fh; du=du[:nf] or [8]*nf
        bb=im.getbbox()
        meta[n]=dict(fw=fw,fh=fh,n=nf,r=rows,d=du,hit=int(a.findtext('HitFrame') or max(0,nf//2)),y=0)
        # ground point per facing: the centre of the sheet's own shadow layer (first frame of each row)
        sf=p+src+'-Shadow.png'
        if os.path.exists(sf):
            sh=Image.open(sf).convert('RGBA'); pts=[]
            for r_ in range(rows):
                box=sh.crop((0,r_*fh,fw,r_*fh+fh)).getchannel('A').point(lambda v:255 if v else 0); bb=box.getbbox()
                pts.append([round((bb[0]+bb[2])/2,1),round((bb[1]+bb[3])/2,1)] if bb else [fw/2,fh/2])
            meta[n]['sh']=pts
        parts.append((n,im))
    if 'Walk' not in meta: return None
    W=max(im.width for _,im in parts); H=sum(im.height for _,im in parts)
    sheet=Image.new('RGBA',(W,H)); y=0
    for n,im in parts: sheet.paste(im,(0,y)); meta[n]['y']=y; y+=im.height
    sheet.save(OUT+folder+'.webp','WEBP',lossless=True,method=6)
    return folder,meta
if __name__=='__main__':
    import sys
    fs=sorted(f for f in os.listdir(SC) if f.isdigit() and int(f)>0)
    if len(sys.argv)>1:   # repack only some folders and merge into the existing data
        fs=sys.argv[1:]; old=json.load(open('/home/claude/routedef/web/data/anim.json'))
        with Pool(8) as P: res=[r for r in P.map(one,fs) if r]
        for k,v in res: old[str(int(k))]=v
        json.dump(old,open('/home/claude/routedef/web/data/anim.json','w'),separators=(',',':')); print(len(res),'repacked'); sys.exit()
    with Pool(8) as P: res=[r for r in P.map(one,fs) if r]
    json.dump({int(k):v for k,v in res},open('/home/claude/routedef/web/data/anim.json','w'),separators=(',',':'))
    tot=sum(os.path.getsize(OUT+f) for f in os.listdir(OUT))
    print(len(res),'packed',tot//1048576,'MB')
