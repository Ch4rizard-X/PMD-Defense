"""Bundle Route Defense into one self-contained HTML file.
Assets go in as plain-text base64 blocks the browser never runs as code (fast to load on phones); the game turns each into a blob URL on first use."""
import base64, json, os, re, sys
W='/home/claude/routedef/web/'; out=sys.argv[1] if len(sys.argv)>1 else '/home/claude/routedef/dist/RouteDefense.html'
os.makedirs(os.path.dirname(out),exist_ok=True)
html=open(W+'index.html').read()
D={k:json.load(open(W+f'data/{k}.json')) for k in ['dex','anim','ts','fx','snd','tree','icons','wx','mk','micons']}
mime={'.png':'image/png','.mp3':'audio/mpeg','.webp':'image/webp'}
font='data:font/ttf;base64,'+base64.b64encode(open(W+'pmd.ttf','rb').read()).decode()
html=html.replace('src: url(pmd.ttf)',f'src: url({font})')
js=''.join(open(W+f'js/{n}.js').read()+'\n' for n in ['core','map','battle','ui'])
html=re.sub(r'<script src="js/[^"]+"></script>\s*','',html)
parts=['<script>window.__BUNDLE=1;</script>\n<script id="__D" type="application/json">'+json.dumps(D,separators=(',',':'),ensure_ascii=False).replace('</','<\\/')+'</script>\n<script>\n'+js+'</script>\n']
for root,_,fs in os.walk(W):
    for f in sorted(fs):
        p=os.path.join(root,f); rel=os.path.relpath(p,W); ext=os.path.splitext(f)[1]
        if ext in mime and not rel.startswith('data'):
            parts.append(f'<script type="text/plain" data-a="{rel}" data-m="{mime[ext]}">'+base64.b64encode(open(p,'rb').read()).decode()+'</script>\n')
html=html.replace('</body>',''.join(parts)+'</body>')
open(out,'w').write(html)
print(out, os.path.getsize(out)//1048576,'MB')
