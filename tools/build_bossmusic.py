"""Boss-specific themes from the user's ROMs: when the boss wave's boss has its own song in PMD Red / Explorers of Sky, that plays.
Rayquaza: Red 032 Battle With Rayquaza; Dialga: EoS 016 Dialga's Fight To The Finish; Palkia: EoS 123 Palkia's Onslaught; Dusknoir: EoS 017 Battle Against Dusknoir.
Writes web/snd/<key>.mp3 (mono 56k, like the other songs) and snd.json "bossTheme": {species id: music key}."""
import json, glob, os, subprocess
W = '/home/claude/routedef/web/'; RED = '/home/claude/pmd/pmd_red_audio/music/'; EOS = '/home/claude/eos_music/eos_audio/music/'
# Explorers of Sky: overlay 10 holds a music number per boss floor (array at 0x8BD6, one u16 per fixed floor; checked: floor 10 Temporal Pinnacle = 16, floor 18 Spacial Rift Bottom = 123).
# Each boss below fights on the floor named in the comment; PMD Red keeps boss music in its event scripts, so only Rayquaza's own song comes from Red.
EOS_FLOOR_MUSIC = (0x8BD6, '/home/claude/eos/eos_unpacked/_code/overlay_0010.bin')
BOSSES = {   # species: fixed floor it is fought on
    477: 9,    # Dusknoir - Old Ruins
    483: 10,   # Dialga - Temporal Pinnacle (Vast Ice Mountain Pinnacle, floor 36, plays the same song)
    484: 18,   # Palkia - Spacial Rift Bottom
    491: 19,   # Darkrai - Dark Crater Pit
    378: 14, 377: 15, 379: 16, 486: 17,   # Regice, Regirock, Registeel, Regigigas - their chambers
    485: 20,   # Heatran - Giant Volcano Peak
    383: 21,   # Groudon - Shimmer Desert Pit
    144: 22,   # Articuno - Mt. Avalanche Peak
    382: 23,   # Kyogre - Bottomless Sea Depths
    487: 24,   # Giratina - World Abyss Pit
    151: 25,   # Mew - Deep Mystery Jungle
}
import struct
_ov = open(EOS_FLOOR_MUSIC[1], 'rb').read()
THEMES = {384: (RED, 32, 'm32')}   # Rayquaza: PMD Red's Battle With Rayquaza (its own song; in Explorers of Sky it shares Defy The Legends)
for sid, fl in BOSSES.items():
    n = struct.unpack_from('<H', _ov, EOS_FLOOR_MUSIC[0] + fl * 2)[0]; THEMES[sid] = (EOS, n, 'e%d' % n)
snd = json.load(open(W + 'data/snd.json')); snd['bossTheme'] = {}
for sid, (base, n, key) in THEMES.items():
    src = glob.glob(base + '%03d *.mp3' % n)[0]; out = W + 'snd/' + key + '.mp3'
    if not os.path.exists(out): subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', src, '-ac', '1', '-b:a', '56k', out], check=True)
    snd['music']['_boss' + str(sid)] = key; snd['bossTheme'][str(sid)] = '_boss' + str(sid); print(sid, os.path.basename(src), '->', key)
# heavy waves (every 5th): Explorers of Sky's Monster House song (the same table gives it to Fortune Ravine Pit's monster-house fight)
mh = glob.glob(EOS + '011 *.mp3')[0]; out = W + 'snd/e11.mp3'
if not os.path.exists(out): subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', mh, '-ac', '1', '-b:a', '56k', out], check=True)
snd['music']['_heavy'] = 'e11'; print('heavy waves:', os.path.basename(mh))
json.dump(snd, open(W + 'data/snd.json', 'w'))
