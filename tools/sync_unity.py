"""Copy the HTML game's data and assets into the Unity project (sprite sheets WebP -> PNG for Unity), and zip only what changed.
Usage: python3 tools/sync_unity.py   -> writes /mnt/user-data/outputs/rd_sync.zip (paths relative to the Unity project's Assets/RouteDefense)."""
import os, shutil, zipfile, hashlib
from PIL import Image
W = '/home/claude/routedef/web/'; U = '/home/claude/rdunity/Assets/RouteDefense/'
OUT = '/mnt/user-data/outputs/rd_sync.zip'
changed = []
def same(a, b):
    if not os.path.exists(b): return False
    return hashlib.md5(open(a, 'rb').read()).digest() == hashlib.md5(open(b, 'rb').read()).digest()
def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not same(src, dst): shutil.copy(src, dst); changed.append(dst)
for f in os.listdir(W + 'data'): copy(W + 'data/' + f, U + 'Resources/Data/' + f)
for f in os.listdir(W + 'img/ts'): copy(W + 'img/ts/' + f, U + 'Resources/Ts/' + f)
for f in os.listdir(W + 'img/fx'): copy(W + 'img/fx/' + f, U + 'Resources/Fx/' + f)
for f in ('dmg_r.png', 'dmg_b.png'): copy(W + 'img/' + f, U + 'Resources/Ui/' + f)
copy(W + 'img/ui/pokeball.png', U + 'Resources/Ui/pokeball.png')   # join popup: already-owned marker
for f in os.listdir(W + 'snd'): copy(W + 'snd/' + f, U + 'Resources/Snd/' + f)
for f in os.listdir(W + 'img/item'): copy(W + 'img/item/' + f, U + 'Resources/Items/' + f)
for f in os.listdir(W + 'img/wx'): copy(W + 'img/wx/' + f, U + 'Resources/Wx/' + f)
for f in os.listdir(W + 'img/mon'):          # WebP sheets -> PNG bytes, only when the WebP is newer
    # saved as .bytes (the PNG file itself): Unity keeps it as-is in the APK and the game decodes it on first use.
    # As textures, Unity stored them uncompressed and the APK passed Android's 4 GB limit.
    src = W + 'img/mon/' + f; dst = U + 'Resources/Mon/' + f.replace('.webp', '.bytes')
    if not os.path.exists(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
        Image.open(src).save(dst, format='PNG', optimize=True); changed.append(dst)
if changed:
    with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
        for p in changed: z.write(p, os.path.relpath(p, U))
print(len(changed), 'changed files', '->', OUT if changed else '(nothing to send)')
