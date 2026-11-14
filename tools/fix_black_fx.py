"""Five PMD Red effect sheets lost their palette when extracted (solid black: Thief, Encore, Smokescreen, Night Shade, Morning Sun).
Replaces them with the same effects from the user's Explorers of Sky dump (eos_move_effects.zip), with EoS frame sizes and timings."""
import json, zipfile, io
from PIL import Image
Z = zipfile.ZipFile('/home/claude/eos/eos_move_effects.zip'); W = '/home/claude/routedef/web/'
fx = json.load(open(W + 'data/fx.json'))
for e, an in (('017', 0), ('025', 1), ('056', 0), ('075', 0), ('113', 0)):
    base = f'eos_move_effects/effect_files/effect_{e}/'
    info = [a for a in json.loads(Z.read(base + 'info.json'))['animations'] if a['animation_index'] == an][0]
    im = Image.open(io.BytesIO(Z.read(base + f'anim_{an:02d}_sheet.png'))).convert('RGBA')
    name = f'efob{e}_anim{an:02d}'; im.save(W + f'img/fx/{name}.png')
    fw, fh = info['frame_size']; a = fx['anims'][f'efob{e}/anim{an:02d}']
    a.update(fw=fw, fh=fh, n=info['frames'], d=info['durations_60fps'], r=1); a.pop('sh', None)
    print(name, im.size, fw, fh, info['frames'])
json.dump(fx, open(W + 'data/fx.json', 'w'), separators=(',', ':'))
