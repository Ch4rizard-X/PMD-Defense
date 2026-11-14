"""Weather screens from the user's PMD Red ROM (already extracted move backgrounds): rain = efbg004, sandstorm = efbg006, hail = efbg002.
PMD Red has no sunlight screen, so sun stays a tint. Writes web/img/wx/<k>.png and web/data/wx.json (frame size, count, ms per frame)."""
import json, shutil
from PIL import Image
B = '/home/claude/pmd/pmd_red_effects/backgrounds/'; W = '/home/claude/routedef/web/'
out = {}
for k, n in (('rain', 4), ('sand', 6), ('hail', 2)):
    d = B + 'efbg%03d/' % n; g = Image.open(d + 'preview.gif')
    frames = getattr(g, 'n_frames', 1); fw, fh = g.size
    shutil.copy(d + 'frames.png', W + f'img/wx/{k}.png')
    im = Image.open(d + 'frames.png')
    out[k] = dict(n=frames, fw=fw, fh=fh, per=im.width // fw, ms=g.info.get('duration', 33), blend='lighter' if k != 'sand' else 'alpha')
json.dump(out, open(W + 'data/wx.json', 'w'))
print(out)
