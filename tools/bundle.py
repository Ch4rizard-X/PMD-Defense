"""Bundle Route Defense into one self-contained HTML file.
Assets go in as plain-text base64 blocks the browser never runs as code (fast to load on phones); the game turns each into a blob URL on first use."""
import base64, json, os, re, sys
W='/home/claude/routedef/web/'; out=sys.argv[1] if len(sys.argv)>1 else '/home/claude/routedef/dist/RouteDefense.html'
os.makedirs(os.path.dirname(out),exist_ok=True)
html=open(W+'index.html').read()
D={k:json.load(open(W+f'data/{k}.json')) for k in ['dex','anim','ts','fx','snd','tree','icons','wx','mk','micons']}
mime={'.png':'image/png','.mp3':'audio/mpeg','.webp':'image/webp'}
font='data:font/ttf;base64,'+base64.b64encode(open(W+'pmd.ttf','rb').read()).decode()
html=html.replace('<style>','<style id="__S">',1)
html=html.replace('src: url(pmd.ttf)',f'src: url({font})')
js=''.join(open(W+f'js/{n}.js').read()+'\n' for n in ['core','map','battle','ui'])
# --- online code updates: the code is stored as text and started by a small loader that can run a newer copy
#     downloaded from GitHub instead. version.json: v = code version (bumped here whenever the code or styles change),
#     data = fingerprint of the data + graphics this code was built with (an update only installs onto a matching app).
import hashlib
style=html[html.index('>',html.index('<style'))+1:html.index('</style>')]
# optional pictures: the code hides them when missing, so an older app can still take a code update without them
OPTIONAL={'img/ui/pokeball.png'}
assets=sorted((os.path.relpath(os.path.join(r,f),W),os.path.getsize(os.path.join(r,f))) for r,_,fs in os.walk(W) for f in fs if os.path.splitext(f)[1] in mime and os.path.relpath(os.path.join(r,f),W) not in OPTIONAL)
dh=hashlib.md5((json.dumps(D,sort_keys=True)+json.dumps(assets)).encode()).hexdigest()[:10]
ch=hashlib.md5((js+style).encode()).hexdigest()[:10]
VF=W+'version.json'; V=json.load(open(VF)) if os.path.exists(VF) else {'v':0}
if V.get('code')!=ch: V['v']=V.get('v',0)+1
V.update(code=ch,data=dh); json.dump(V,open(VF,'w'))
LOADER=r'''<script>
(function(){ var code=document.getElementById('__C').textContent, v=window.__CODEV, u=null;
  try { u=JSON.parse(localStorage.getItem('rd_upd')||'null'); } catch(e){}
  if (u && u.v>v && u.data===window.__DATAH && u.js) {
    if (localStorage.getItem('rd_upd_try')==String(u.v)) { localStorage.removeItem('rd_upd'); localStorage.removeItem('rd_upd_try'); }  // this update failed to start last time: back to the built-in code
    else { localStorage.setItem('rd_upd_try',String(u.v)); code=u.js; v=u.v;
      if (u.css) { var S=document.getElementById('__S'); window.__S0=S.textContent; var f=/url\((data:font[^)]*)\)/.exec(S.textContent); S.textContent=f?u.css.replace('url(pmd.ttf)','url('+f[1]+')'):u.css; } }
  }
  window.__CODEV_RUN=v; window.__updOK=function(){ localStorage.removeItem('rd_upd_try'); };
  var run=function(c){ var sc=document.createElement('script'); sc.text=c; document.body.appendChild(sc); };
  try { run(code); } catch(e){}
  if (v!==window.__CODEV && typeof boot!=='function') {   // the downloaded code did not load: drop it and start the built-in code now
    localStorage.removeItem('rd_upd'); localStorage.removeItem('rd_upd_try'); window.__CODEV_RUN=window.__CODEV;
    var S=document.getElementById('__S'); if (window.__S0) S.textContent=window.__S0; run(document.getElementById('__C').textContent);
  }
})();
</script>
'''

html=re.sub(r'<script src="js/[^"]+"></script>\s*','',html)
parts=[f'<script>window.__BUNDLE=1;window.__CODEV={V["v"]};window.__DATAH="{dh}";</script>\n<script id="__D" type="application/json">'+json.dumps(D,separators=(',',':'),ensure_ascii=False).replace('</','<\\/')+'</script>\n<script id="__C" type="text/plain">\n'+js.replace('</script','<\\/script')+'</script>\n'+LOADER]
for root,_,fs in os.walk(W):
    for f in sorted(fs):
        p=os.path.join(root,f); rel=os.path.relpath(p,W); ext=os.path.splitext(f)[1]
        if ext in mime and not rel.startswith('data'):
            parts.append(f'<script type="text/plain" data-a="{rel}" data-m="{mime[ext]}">'+base64.b64encode(open(p,'rb').read()).decode()+'</script>\n')
html=html.replace('</body>',''.join(parts)+'</body>')
open(out,'w').write(html)
print(out, os.path.getsize(out)//1048576,'MB', 'code v%d' % V['v'], 'data', dh)
