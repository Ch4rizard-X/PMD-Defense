import sys, os
sys.path.insert(0, '/tmp/claude-0/-home-claude/279b538a-126a-505c-9ac1-5cdb23e31079/scratchpad/eos')
from nds import NDS
r = NDS(sys.argv[1]); out = sys.argv[2]
for name, fid in r.files.items():
    s, t = r.fat[fid]; p = os.path.join(out, name); os.makedirs(os.path.dirname(p) or out, exist_ok=True); open(p, 'wb').write(r.d[s:t])
for oid, b in r.overlays.items(): open(f'{out}/overlay_{oid:04d}.bin', 'wb').write(b)
open(f'{out}/arm9.bin', 'wb').write(r.arm9); print(len(r.files), 'files', len(r.overlays), 'overlays')
